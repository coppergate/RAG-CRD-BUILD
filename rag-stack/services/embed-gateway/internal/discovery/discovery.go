package discovery

import (
	"context"
	"fmt"
	"sync"
	"time"

	"app-builds/common/logging"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

// NodeLocalURLs discovers and caches the HTTP URLs of Ollama embed pods running
// on the same node as the embed-gateway. Re-discovery is triggered on demand
// (e.g. after receiving a 503 or connection-refused from a local pod).
type NodeLocalURLs struct {
	mu          sync.RWMutex
	urls        []string
	idx         int
	nodeName    string
	namespace   string
	fallbackURL string
	k8sClient   kubernetes.Interface
}

// NewNodeLocalURLs returns a discoverer for embed pods on nodeName.
// Call Refresh once before first use.
func NewNodeLocalURLs(nodeName, namespace, fallbackURL string) (*NodeLocalURLs, error) {
	cfg, err := rest.InClusterConfig()
	if err != nil {
		return nil, fmt.Errorf("in-cluster config: %w", err)
	}
	client, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return nil, fmt.Errorf("k8s client: %w", err)
	}
	return &NodeLocalURLs{
		nodeName:    nodeName,
		namespace:   namespace,
		fallbackURL: fallbackURL,
		k8sClient:   client,
	}, nil
}

// Refresh re-queries the k8s API for local embed pod IPs. Safe to call concurrently.
func (d *NodeLocalURLs) Refresh() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pods, err := d.k8sClient.CoreV1().Pods(d.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "ollama-role=embed",
		FieldSelector: "spec.nodeName=" + d.nodeName + ",status.phase=Running",
	})
	if err != nil {
		logging.Printf("[discovery] failed to list embed pods on node %s: %v — using fallback", d.nodeName, err)
		d.mu.Lock()
		d.urls = nil
		d.mu.Unlock()
		return
	}

	var fresh []string
	for _, pod := range pods.Items {
		if pod.Status.PodIP != "" {
			fresh = append(fresh, fmt.Sprintf("http://%s:11434", pod.Status.PodIP))
		}
	}

	if len(fresh) == 0 {
		logging.Printf("[discovery] no running embed pods found on node %s — using fallback URL", d.nodeName)
	} else {
		logging.Printf("[discovery] discovered %d embed pod(s) on node %s: %v", len(fresh), d.nodeName, fresh)
	}

	d.mu.Lock()
	d.urls = fresh
	d.idx = 0
	d.mu.Unlock()
}

// Next returns the next URL to use (round-robin across local pods). Falls back to
// the cluster-wide service URL when no local pods are known.
func (d *NodeLocalURLs) Next() (string, bool) {
	d.mu.Lock()
	defer d.mu.Unlock()

	if len(d.urls) == 0 {
		return d.fallbackURL, false
	}
	url := d.urls[d.idx%len(d.urls)]
	d.idx++
	return url, true
}

// NewFallback returns a NodeLocalURLs that always uses fallbackURL.
// Used when in-cluster discovery is not available.
func NewFallback(fallbackURL string) *NodeLocalURLs {
	return &NodeLocalURLs{
		fallbackURL: fallbackURL,
	}
}
