package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"app-builds/common/health"
	"github.com/apache/pulsar-client-go/pulsar"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

type BuildTask struct {
	ServiceName    string `json:"service_name"`
	Version        string `json:"version"`
	DockerfilePath string `json:"dockerfile_path"`
	SourceTarball  string `json:"source_tarball"`
	SourceURL      string `json:"source_url"`
	Registry       string `json:"registry"`
}

type BuildStatusEvent struct {
	EventID     string `json:"event_id"`
	ServiceName string `json:"service_name"`
	Version     string `json:"version"`
	JobName     string `json:"job_name"`
	Status      string `json:"status"`
	Message     string `json:"message,omitempty"`
	Timestamp   string `json:"timestamp"`
}

type BuildStatusSnapshot struct {
	ActiveBuilds   int                `json:"active_builds"`
	MaxConcurrent  int                `json:"max_concurrent_builds"`
	LatestStatuses []BuildStatusEvent `json:"latest_statuses"`
	RecentEvents   []BuildStatusEvent `json:"recent_events"`
	UpdatedAt      string             `json:"updated_at"`
}

type buildTaskEnvelope struct {
	msg       pulsar.Message
	task      BuildTask
	requestID string
	jobName   string
}

type statusHub struct {
	mu          sync.RWMutex
	subscribers map[chan BuildStatusEvent]struct{}
	latest      map[string]BuildStatusEvent
	history     []BuildStatusEvent
	maxHistory  int
	updatedAt   time.Time
}

func newStatusHub(maxHistory int) *statusHub {
	return &statusHub{
		subscribers: make(map[chan BuildStatusEvent]struct{}),
		latest:      make(map[string]BuildStatusEvent),
		maxHistory:  maxHistory,
		updatedAt:   time.Now().UTC(),
	}
}

func (h *statusHub) publish(evt BuildStatusEvent) {
	h.mu.Lock()
	key := statusKey(evt.ServiceName, evt.Version)
	h.latest[key] = evt
	h.history = append(h.history, evt)
	if len(h.history) > h.maxHistory {
		h.history = h.history[len(h.history)-h.maxHistory:]
	}
	h.updatedAt = time.Now().UTC()

	subs := make([]chan BuildStatusEvent, 0, len(h.subscribers))
	for ch := range h.subscribers {
		subs = append(subs, ch)
	}
	h.mu.Unlock()

	for _, ch := range subs {
		select {
		case ch <- evt:
		default:
		}
	}
}

func (h *statusHub) subscribe() (chan BuildStatusEvent, func()) {
	ch := make(chan BuildStatusEvent, 32)
	h.mu.Lock()
	h.subscribers[ch] = struct{}{}
	h.mu.Unlock()

	cancel := func() {
		h.mu.Lock()
		if _, ok := h.subscribers[ch]; ok {
			delete(h.subscribers, ch)
			close(ch)
		}
		h.mu.Unlock()
	}

	return ch, cancel
}

func (h *statusHub) snapshot(activeBuilds, maxConcurrent int) BuildStatusSnapshot {
	h.mu.RLock()
	latest := make([]BuildStatusEvent, 0, len(h.latest))
	for _, evt := range h.latest {
		latest = append(latest, evt)
	}
	history := append([]BuildStatusEvent(nil), h.history...)
	updatedAt := h.updatedAt
	h.mu.RUnlock()

	sort.Slice(latest, func(i, j int) bool {
		return latest[i].Timestamp > latest[j].Timestamp
	})

	return BuildStatusSnapshot{
		ActiveBuilds:   activeBuilds,
		MaxConcurrent:  maxConcurrent,
		LatestStatuses: latest,
		RecentEvents:   history,
		UpdatedAt:      updatedAt.Format(time.RFC3339),
	}
}

type statusPublisher struct {
	hub      *statusHub
	producer pulsar.Producer
}

type failedTaskPublisher struct {
	producer pulsar.Producer
	topic    string
}

func (p *statusPublisher) Publish(evt BuildStatusEvent) {
	if evt.Timestamp == "" {
		evt.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}
	if evt.EventID == "" {
		evt.EventID = strconv.FormatInt(time.Now().UTC().UnixNano(), 10)
	}

	p.hub.publish(evt)

	if p.producer == nil {
		return
	}

	payload, err := json.Marshal(evt)
	if err != nil {
		log.Printf("Error marshaling status event: %v", err)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if _, err := p.producer.Send(ctx, &pulsar.ProducerMessage{Payload: payload}); err != nil {
		log.Printf("Error publishing status event to Pulsar: %v", err)
	}
}

func (p *failedTaskPublisher) Publish(task BuildTask, msg pulsar.Message, reason string, requestID string, jobName string) {
	if p == nil || p.producer == nil {
		return
	}
	payload := map[string]interface{}{
		"task":             task,
		"original_payload": string(msg.Payload()),
		"reason":           reason,
		"request_id":       requestID,
		"job_name":         jobName,
		"redelivery_count": msg.RedeliveryCount(),
		"published_at":     time.Now().UTC().Format(time.RFC3339),
	}
	b, err := json.Marshal(payload)
	if err != nil {
		log.Printf("Error marshaling failed task payload: %v", err)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if _, err := p.producer.Send(ctx, &pulsar.ProducerMessage{Payload: b}); err != nil {
		log.Printf("Error publishing failed task to %s: %v", p.topic, err)
	}
}

func main() {
	pulsarURL := os.Getenv("PULSAR_URL")
	topic := os.Getenv("BUILD_TOPIC")
	if pulsarURL == "" || topic == "" {
		log.Fatal("PULSAR_URL and BUILD_TOPIC must be set")
	}

	statusTopic := getenvDefault("BUILD_STATUS_TOPIC", "persistent://public/default/build-status")
	failedTaskTopic := strings.TrimSpace(os.Getenv("FAILED_TASK_TOPIC"))
	httpAddr := getenvDefault("HTTP_ADDR", ":8080")
	healthAddr := getenvDefault("HEALTH_ADDR", ":8081")
	maxConcurrent := getenvIntDefault("MAX_CONCURRENT_BUILDS", 3)
	maxTaskRetries := getenvIntDefault("MAX_TASK_RETRIES", 2)
	if maxConcurrent < 1 {
		maxConcurrent = 1
	}
	if maxTaskRetries < 0 {
		maxTaskRetries = 0
	}

	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("Error building in-cluster config: %v", err)
	}
	k8sClientset, err = kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Error creating kubernetes client: %v", err)
	}

	pulsarOpts := pulsar.ClientOptions{URL: pulsarURL}
	if strings.HasPrefix(pulsarURL, "pulsar+ssl://") {
		if caFile := os.Getenv("SSL_CERT_FILE"); caFile != "" {
			pulsarOpts.TLSTrustCertsFilePath = caFile
		} else {
			log.Printf("WARNING: Pulsar URL uses TLS but SSL_CERT_FILE is not set")
		}
	}

	pulsarClient, err = pulsar.NewClient(pulsarOpts)
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer pulsarClient.Close()

	consumer, err := pulsarClient.Subscribe(pulsar.ConsumerOptions{
		Topic:            topic,
		SubscriptionName: "build-orchestrator-sub",
		Type:             pulsar.Shared,
	})
	if err != nil {
		log.Fatalf("Could not subscribe to topic: %v", err)
	}
	defer consumer.Close()

	var statusProducer pulsar.Producer
	if statusTopic != "" {
		statusProducer, err = pulsarClient.CreateProducer(pulsar.ProducerOptions{Topic: statusTopic})
		if err != nil {
			log.Fatalf("Could not create status topic producer: %v", err)
		}
		defer statusProducer.Close()
	}
	var failedProducer pulsar.Producer
	if failedTaskTopic != "" {
		failedProducer, err = pulsarClient.CreateProducer(pulsar.ProducerOptions{Topic: failedTaskTopic})
		if err != nil {
			log.Fatalf("Could not create failed-task topic producer: %v", err)
		}
		defer failedProducer.Close()
	}

	hub := newStatusHub(250)
	publisher := &statusPublisher{hub: hub, producer: statusProducer}
	failedPublisher := &failedTaskPublisher{producer: failedProducer, topic: failedTaskTopic}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var activeBuilds int32

	// Launch HTTP server
	taskQueue := make(chan buildTaskEnvelope, maxConcurrent*8)

	for i := 0; i < maxConcurrent; i++ {
		workerID := i + 1
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case env, ok := <-taskQueue:
					if !ok {
						return
					}

					jobName := env.jobName
					atomic.AddInt32(&activeBuilds, 1)
					publisher.Publish(BuildStatusEvent{
						ServiceName: env.task.ServiceName,
						Version:     env.task.Version,
						JobName:     jobName,
						Status:      "running",
						Message:     fmt.Sprintf("Picked up by worker-%d", workerID),
					})

					err := processTask(ctx, k8sClientset, env.task, jobName, publisher)
					if err != nil {
						redelivery := int(env.msg.RedeliveryCount())
						if redelivery >= maxTaskRetries {
							publisher.Publish(BuildStatusEvent{
								ServiceName: env.task.ServiceName,
								Version:     env.task.Version,
								JobName:     jobName,
								Status:      "failed_terminal",
								Message:     fmt.Sprintf("%s (redelivery=%d max=%d)", err.Error(), redelivery, maxTaskRetries),
							})
							failedPublisher.Publish(env.task, env.msg, err.Error(), env.requestID, jobName)
							consumer.Ack(env.msg)
						} else {
							publisher.Publish(BuildStatusEvent{
								ServiceName: env.task.ServiceName,
								Version:     env.task.Version,
								JobName:     jobName,
								Status:      "retrying",
								Message:     fmt.Sprintf("%s (redelivery=%d max=%d)", err.Error(), redelivery, maxTaskRetries),
							})
							consumer.Nack(env.msg)
						}
					} else {
						publisher.Publish(BuildStatusEvent{
							ServiceName: env.task.ServiceName,
							Version:     env.task.Version,
							JobName:     jobName,
							Status:      "succeeded",
							Message:     "Build job completed",
						})
						consumer.Ack(env.msg)
					}
					atomic.AddInt32(&activeBuilds, -1)
				}
			}
		}()
	}

	go runStatusServer(ctx, httpAddr, hub, &activeBuilds, maxConcurrent)
	go runHealthServer(ctx, healthAddr)

	go func() {
		for {
			msg, err := consumer.Receive(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				log.Printf("Error receiving message: %v", err)
				continue
			}

			var task BuildTask
			if err := json.Unmarshal(msg.Payload(), &task); err != nil {
				preview := strings.TrimSpace(string(msg.Payload()))
				if len(preview) > 160 {
					preview = preview[:160] + "..."
				}
				log.Printf("Error unmarshaling task: %v payload=%q", err, preview)
				consumer.Ack(msg)
				continue
			}

			requestID := requestIDFromMessage(msg)
			jobName := buildJobName(task, requestID)
			publisher.Publish(BuildStatusEvent{
				ServiceName: task.ServiceName,
				Version:     task.Version,
				JobName:     jobName,
				Status:      "queued",
				Message:     "Build request received",
			})

			select {
			case taskQueue <- buildTaskEnvelope{msg: msg, task: task, requestID: requestID, jobName: jobName}:
			default:
				publisher.Publish(BuildStatusEvent{
					ServiceName: task.ServiceName,
					Version:     task.Version,
					JobName:     jobName,
					Status:      "queued",
					Message:     "Waiting for available worker",
				})
				taskQueue <- buildTaskEnvelope{msg: msg, task: task, requestID: requestID, jobName: jobName}
			}
		}
	}()

	log.Printf("Build Orchestrator listening on %s; status topic=%s; failed-topic=%s; max concurrent builds=%d; max task retries=%d", topic, statusTopic, failedTaskTopic, maxConcurrent, maxTaskRetries)

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan
	log.Println("Shutting down build orchestrator")
	cancel()
}

func processTask(ctx context.Context, clientset *kubernetes.Clientset, task BuildTask, jobName string, publisher *statusPublisher) error {
	namespace := "build-pipeline"

	publisher.Publish(BuildStatusEvent{
		ServiceName: task.ServiceName,
		Version:     task.Version,
		JobName:     jobName,
		Status:      "job_created",
		Message:     "Creating Kaniko job",
	})

	if err := launchKanikoJob(ctx, clientset, task, jobName); err != nil {
		return fmt.Errorf("launch job: %w", err)
	}

	return waitForJobCompletion(ctx, clientset, namespace, task, jobName, publisher)
}

func waitForJobCompletion(ctx context.Context, clientset *kubernetes.Clientset, namespace string, task BuildTask, jobName string, publisher *statusPublisher) error {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	runningSent := false

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			job, err := clientset.BatchV1().Jobs(namespace).Get(ctx, jobName, metav1.GetOptions{})
			if err != nil {
				return fmt.Errorf("get job %s: %w", jobName, err)
			}

			if !runningSent {
				pods, podErr := clientset.CoreV1().Pods(namespace).List(ctx, metav1.ListOptions{LabelSelector: "job-name=" + jobName})
				if podErr == nil {
					for _, p := range pods.Items {
						if p.Status.Phase == corev1.PodRunning {
							publisher.Publish(BuildStatusEvent{
								ServiceName: task.ServiceName,
								Version:     task.Version,
								JobName:     jobName,
								Status:      "pod_running",
								Message:     "Kaniko pod is running",
							})
							runningSent = true
							break
						}
					}
				}
			}

			if job.Status.Succeeded > 0 {
				return nil
			}
			if job.Status.Failed > 0 {
				return fmt.Errorf("job %s failed", jobName)
			}
		}
	}
}

var (
	pulsarClient pulsar.Client
	k8sClientset *kubernetes.Clientset
)

func runStatusServer(ctx context.Context, addr string, hub *statusHub, activeBuilds *int32, maxConcurrent int) {
	certFile := os.Getenv("TLS_CERT")
	keyFile := os.Getenv("TLS_KEY")
	log.Printf("Starting status dashboard server on %s (TLS_CERT=%q, TLS_KEY=%q)", addr, certFile, keyFile)

	mux := http.NewServeMux()

	mux.HandleFunc("/status", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		snap := hub.snapshot(int(atomic.LoadInt32(activeBuilds)), maxConcurrent)
		_ = json.NewEncoder(w).Encode(snap)
	})

	mux.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming unsupported", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("X-Accel-Buffering", "no")

		ch, cancel := hub.subscribe()
		defer cancel()

		snap := hub.snapshot(int(atomic.LoadInt32(activeBuilds)), maxConcurrent)
		for _, evt := range snap.RecentEvents {
			payload, _ := json.Marshal(evt)
			_, _ = fmt.Fprintf(w, "event: status\ndata: %s\n\n", payload)
		}
		flusher.Flush()

		heartbeat := time.NewTicker(15 * time.Second)
		defer heartbeat.Stop()

		for {
			select {
			case <-r.Context().Done():
				return
			case <-heartbeat.C:
				_, _ = fmt.Fprint(w, ": ping\n\n")
				flusher.Flush()
			case evt := <-ch:
				payload, _ := json.Marshal(evt)
				_, _ = fmt.Fprintf(w, "event: status\ndata: %s\n\n", payload)
				flusher.Flush()
			}
		}
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(dashboardHTML))
	})

	srv := &http.Server{Addr: addr, Handler: mux}

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	if certFile != "" && keyFile != "" {
		if err := srv.ListenAndServeTLS(certFile, keyFile); err != nil && err != http.ErrServerClosed {
			log.Printf("Status HTTPS server error: %v", err)
		}
	} else {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("Status HTTP server error: %v", err)
		}
	}
}

func runHealthServer(ctx context.Context, addr string) {
	certFile := os.Getenv("TLS_CERT")
	keyFile := os.Getenv("TLS_KEY")
	log.Printf("Starting health server on %s (TLS_CERT=%q, TLS_KEY=%q)", addr, certFile, keyFile)

	mux := http.NewServeMux()
	healthSrv := health.NewServer()
	healthSrv.RegisterCheck("pulsar", func() error {
		if pulsarClient == nil {
			return fmt.Errorf("pulsar client is nil")
		}
		return nil
	})
	healthSrv.RegisterCheck("kubernetes", func() error {
		if k8sClientset == nil {
			return fmt.Errorf("kubernetes clientset is nil")
		}
		ns := os.Getenv("POD_NAMESPACE")
		if ns == "" {
			ns = "build-pipeline"
		}
		_, err := k8sClientset.CoreV1().Pods(ns).List(ctx, metav1.ListOptions{Limit: 1})
		return err
	})
	healthSrv.RegisterRoutes(mux)

	srv := &http.Server{Addr: addr, Handler: mux}

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	if certFile != "" && keyFile != "" {
		if err := srv.ListenAndServeTLS(certFile, keyFile); err != nil && err != http.ErrServerClosed {
			log.Printf("Health HTTPS server error: %v", err)
		}
	} else {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("Health HTTP server error: %v", err)
		}
	}
}

func launchKanikoJob(ctx context.Context, clientset *kubernetes.Clientset, task BuildTask, jobName string) error {
	namespace := "build-pipeline"

	contextURL := task.SourceURL
	internalRegistryAddr := getenvDefault("INTERNAL_REGISTRY_ADDR", "")
	externalRegistryName := getenvDefault("EXTERNAL_REGISTRY_NAME", "registry.hierocracy.home:5000")

	pushRegistry := task.Registry
	if pushRegistry == "" {
		pushRegistry = externalRegistryName
	}
	if internalRegistryAddr != "" && pushRegistry == externalRegistryName {
		pushRegistry = internalRegistryAddr
	}

	toolingRegistry := pushRegistry
	if contextURL == "" {
		contextURL = "s3://$(BUCKET_NAME)/" + task.SourceTarball
	}

	job := &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      jobName,
			Namespace: namespace,
			Labels: map[string]string{
				"app":     "kaniko-build",
				"service": sanitizeNamePart(task.ServiceName),
				"version": sanitizeNamePart(task.Version),
			},
		},
		Spec: batchv1.JobSpec{
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					InitContainers: []corev1.Container{
						{
							Name:    "fetch-context",
							Image:   toolingRegistry + "/busybox:1.37.0",
							Command: []string{"sh", "-c"},
							Args: []string{
								fmt.Sprintf("wget -O /workspace/context.tar.gz \"%s\" && tar -xzof /workspace/context.tar.gz -C /workspace && rm /workspace/context.tar.gz", contextURL),
							},
							SecurityContext: &corev1.SecurityContext{
								AllowPrivilegeEscalation: ptr(false),
								Capabilities: &corev1.Capabilities{
									Drop: []corev1.Capability{"ALL"},
								},
								RunAsNonRoot: ptr(true),
								RunAsUser:    ptr(int64(1000)),
								SeccompProfile: &corev1.SeccompProfile{
									Type: corev1.SeccompProfileTypeRuntimeDefault,
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "workspace", MountPath: "/workspace"},
								{Name: "registry-ca", MountPath: "/etc/ssl/certs/ca-certificates.crt", SubPath: "ca.crt"},
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:  "kaniko",
							Image: toolingRegistry + "/gcr.io/kaniko-project/executor:v1.24.0",
							Args: []string{
								"--dockerfile=" + task.DockerfilePath,
								"--context=dir:///workspace",
								"--destination=" + pushRegistry + "/" + task.ServiceName + ":" + task.Version,
								"--destination=" + pushRegistry + "/" + task.ServiceName + ":latest",
								"--cache=true",
								"--cache-repo=" + pushRegistry + "/kaniko-cache",
        // "--insecure",
        // "--insecure-pull",
        // "--insecure-registry=" + pushRegistry,
        // "--skip-tls-verify",
        // "--skip-tls-verify-registry=" + pushRegistry,
							},
							SecurityContext: &corev1.SecurityContext{AllowPrivilegeEscalation: ptr(true)},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "workspace", MountPath: "/workspace"},
								{Name: "registry-ca", MountPath: "/kaniko/ssl/certs/ca-certificates.crt", SubPath: "ca.crt"},
							},
							Resources: corev1.ResourceRequirements{
								Requests: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("2"),
									corev1.ResourceMemory: resource.MustParse("4Gi"),
								},
								Limits: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("4"),
									corev1.ResourceMemory: resource.MustParse("8Gi"),
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{Name: "workspace", VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}}},
						{Name: "registry-ca", VolumeSource: corev1.VolumeSource{ConfigMap: &corev1.ConfigMapVolumeSource{LocalObjectReference: corev1.LocalObjectReference{Name: "registry-ca-cm"}}}},
					},
					RestartPolicy: corev1.RestartPolicyNever,
				},
			},
			BackoffLimit: ptr(int32(1)),
		},
	}

	if task.SourceURL == "" {
		job.Spec.Template.Spec.InitContainers[0].EnvFrom = []corev1.EnvFromSource{
			{SecretRef: &corev1.SecretEnvSource{LocalObjectReference: corev1.LocalObjectReference{Name: "build-pipeline-bucket"}}},
			{ConfigMapRef: &corev1.ConfigMapEnvSource{LocalObjectReference: corev1.LocalObjectReference{Name: "build-pipeline-bucket"}}},
		}
	}

	_, err := clientset.BatchV1().Jobs(namespace).Create(ctx, job, metav1.CreateOptions{})
	if apierrors.IsAlreadyExists(err) {
		// Retries for the same request should observe the same job object.
		return nil
	}
	return err
}

func buildJobName(task BuildTask, requestID string) string {
	base := fmt.Sprintf("kaniko-build-%s-%s", sanitizeNamePart(task.ServiceName), sanitizeNamePart(task.Version))
	suffix := sanitizeNamePart(requestID)
	if suffix == "" {
		suffix = "req"
	}
	maxBase := 63 - 1 - len(suffix)
	if maxBase < 1 {
		maxBase = 1
	}
	if len(base) > maxBase {
		base = strings.Trim(base[:maxBase], "-")
		if base == "" {
			base = "kaniko"
		}
	}
	return base + "-" + suffix
}

func statusKey(service, version string) string {
	return strings.TrimSpace(service) + ":" + strings.TrimSpace(version)
}

func requestIDFromMessage(msg pulsar.Message) string {
	raw := fmt.Sprintf("%v", msg.ID())
	if strings.TrimSpace(raw) == "" {
		raw = strconv.FormatInt(time.Now().UTC().UnixNano(), 36)
	}
	id := sanitizeNamePart(raw)
	if len(id) > 12 {
		id = id[len(id)-12:]
	}
	if id == "" {
		id = "req"
	}
	return id
}

func sanitizeNamePart(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	var b strings.Builder
	lastDash := false
	for _, r := range s {
		alnum := (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9')
		if alnum {
			b.WriteRune(r)
			lastDash = false
			continue
		}
		if !lastDash {
			b.WriteByte('-')
			lastDash = true
		}
	}
	out := strings.Trim(b.String(), "-")
	if out == "" {
		return "x"
	}
	return out
}

func getenvDefault(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func getenvIntDefault(key string, fallback int) int {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}

func ptr[T any](v T) *T { return &v }

const dashboardHTML = `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Build Pipeline Status</title>
  <style>
    body { font-family: sans-serif; margin: 20px; background: #f5f7fb; color: #111827; }
    h1 { margin: 0 0 12px 0; }
    .meta { margin-bottom: 14px; font-size: 14px; }
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 10px; margin-bottom: 16px; }
    .card { background: #fff; border: 1px solid #e5e7eb; border-radius: 8px; padding: 10px; }
    .status { font-weight: 700; text-transform: uppercase; font-size: 12px; }
    .queued { color: #1d4ed8; }
    .running, .pod_running, .job_created { color: #b45309; }
    .succeeded { color: #15803d; }
    .failed { color: #b91c1c; }
    table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #e5e7eb; }
    th, td { text-align: left; padding: 8px; border-bottom: 1px solid #e5e7eb; font-size: 13px; }
  </style>
</head>
<body>
  <h1>Build Pipeline Status</h1>
  <div class="meta" id="meta">Connecting...</div>
  <div class="cards" id="cards"></div>
  <table>
    <thead>
      <tr><th>Time</th><th>Service</th><th>Version</th><th>Status</th><th>Job</th><th>Message</th></tr>
    </thead>
    <tbody id="events"></tbody>
  </table>

<script>
const latest = new Map();
const events = [];
const maxEvents = 150;

function statusClass(status) {
  return (status || '').toLowerCase();
}

function render() {
  const cards = document.getElementById('cards');
  cards.innerHTML = '';
  [...latest.values()].sort((a, b) => (b.timestamp || '').localeCompare(a.timestamp || '')).forEach((e) => {
    const el = document.createElement('div');
    el.className = 'card';
    el.innerHTML =
      '<div><strong>' + (e.service_name || '') + ':' + (e.version || '') + '</strong></div>' +
      '<div class=\"status ' + statusClass(e.status) + '\">' + (e.status || '') + '</div>' +
      '<div>' + (e.job_name || '') + '</div>' +
      '<div>' + (e.message || '') + '</div>' +
      '<div>' + (e.timestamp || '') + '</div>';
    cards.appendChild(el);
  });

  const body = document.getElementById('events');
  body.innerHTML = '';
  events.forEach((e) => {
    const row = document.createElement('tr');
    row.innerHTML =
      '<td>' + (e.timestamp || '') + '</td>' +
      '<td>' + (e.service_name || '') + '</td>' +
      '<td>' + (e.version || '') + '</td>' +
      '<td class=\"status ' + statusClass(e.status) + '\">' + (e.status || '') + '</td>' +
      '<td>' + (e.job_name || '') + '</td>' +
      '<td>' + (e.message || '') + '</td>';
    body.appendChild(row);
  });
}

function ingest(evt) {
  if (!evt || !evt.service_name || !evt.version) return;
  latest.set((evt.service_name || '') + ':' + (evt.version || ''), evt);
  events.unshift(evt);
  if (events.length > maxEvents) events.length = maxEvents;
  render();
}

async function bootstrap() {
  try {
    const res = await fetch('/status');
    const data = await res.json();
    document.getElementById('meta').textContent =
      'Active builds: ' + data.active_builds + ' / ' + data.max_concurrent_builds + ' | Updated: ' + data.updated_at;
    (data.latest_statuses || []).forEach(ingest);
    (data.recent_events || []).forEach(ingest);
  } catch (_) {
    document.getElementById('meta').textContent = 'Unable to load initial status.';
  }
}

function connect() {
  const es = new EventSource('/events');
  es.addEventListener('status', (e) => {
    try {
      const data = JSON.parse(e.data);
      ingest(data);
    } catch (_) {}
  });
  es.onerror = () => {
    document.getElementById('meta').textContent = 'Stream disconnected, retrying...';
  };
}

bootstrap().then(connect);
</script>
</body>
</html>`
