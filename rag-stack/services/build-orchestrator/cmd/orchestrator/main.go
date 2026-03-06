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

	"github.com/apache/pulsar-client-go/pulsar"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
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
	msg  pulsar.Message
	task BuildTask
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

func main() {
	pulsarURL := os.Getenv("PULSAR_URL")
	topic := os.Getenv("BUILD_TOPIC")
	if pulsarURL == "" || topic == "" {
		log.Fatal("PULSAR_URL and BUILD_TOPIC must be set")
	}

	statusTopic := getenvDefault("BUILD_STATUS_TOPIC", "persistent://public/default/build-status")
	httpAddr := getenvDefault("HTTP_ADDR", ":8080")
	maxConcurrent := getenvIntDefault("MAX_CONCURRENT_BUILDS", 3)
	if maxConcurrent < 1 {
		maxConcurrent = 1
	}

	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("Error building in-cluster config: %v", err)
	}
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Error creating kubernetes client: %v", err)
	}

	client, err := pulsar.NewClient(pulsar.ClientOptions{URL: pulsarURL})
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer client.Close()

	consumer, err := client.Subscribe(pulsar.ConsumerOptions{
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
		statusProducer, err = client.CreateProducer(pulsar.ProducerOptions{Topic: statusTopic})
		if err != nil {
			log.Fatalf("Could not create status topic producer: %v", err)
		}
		defer statusProducer.Close()
	}

	hub := newStatusHub(250)
	publisher := &statusPublisher{hub: hub, producer: statusProducer}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var activeBuilds int32
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

					jobName := buildJobName(env.task)
					atomic.AddInt32(&activeBuilds, 1)
					publisher.Publish(BuildStatusEvent{
						ServiceName: env.task.ServiceName,
						Version:     env.task.Version,
						JobName:     jobName,
						Status:      "running",
						Message:     fmt.Sprintf("Picked up by worker-%d", workerID),
					})

					err := processTask(ctx, clientset, env.task, publisher)
					if err != nil {
						publisher.Publish(BuildStatusEvent{
							ServiceName: env.task.ServiceName,
							Version:     env.task.Version,
							JobName:     jobName,
							Status:      "failed",
							Message:     err.Error(),
						})
						consumer.Nack(env.msg)
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

	go runHTTPServer(ctx, httpAddr, hub, &activeBuilds, maxConcurrent)

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
				log.Printf("Error unmarshaling task: %v", err)
				consumer.Ack(msg)
				continue
			}

			jobName := buildJobName(task)
			publisher.Publish(BuildStatusEvent{
				ServiceName: task.ServiceName,
				Version:     task.Version,
				JobName:     jobName,
				Status:      "queued",
				Message:     "Build request received",
			})

			select {
			case taskQueue <- buildTaskEnvelope{msg: msg, task: task}:
			default:
				publisher.Publish(BuildStatusEvent{
					ServiceName: task.ServiceName,
					Version:     task.Version,
					JobName:     jobName,
					Status:      "queued",
					Message:     "Waiting for available worker",
				})
				taskQueue <- buildTaskEnvelope{msg: msg, task: task}
			}
		}
	}()

	log.Printf("Build Orchestrator listening on %s; status topic=%s; max concurrent builds=%d", topic, statusTopic, maxConcurrent)

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan
	log.Println("Shutting down build orchestrator")
	cancel()
}

func processTask(ctx context.Context, clientset *kubernetes.Clientset, task BuildTask, publisher *statusPublisher) error {
	namespace := "build-pipeline"
	jobName := buildJobName(task)

	publisher.Publish(BuildStatusEvent{
		ServiceName: task.ServiceName,
		Version:     task.Version,
		JobName:     jobName,
		Status:      "job_created",
		Message:     "Creating Kaniko job",
	})

	if err := launchKanikoJob(ctx, clientset, task); err != nil {
		return fmt.Errorf("launch job: %w", err)
	}

	return waitForJobCompletion(ctx, clientset, namespace, task, publisher)
}

func waitForJobCompletion(ctx context.Context, clientset *kubernetes.Clientset, namespace string, task BuildTask, publisher *statusPublisher) error {
	jobName := buildJobName(task)
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

func runHTTPServer(ctx context.Context, addr string, hub *statusHub, activeBuilds *int32, maxConcurrent int) {
	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte("ok"))
	})

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

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Printf("HTTP server error: %v", err)
	}
}

func launchKanikoJob(ctx context.Context, clientset *kubernetes.Clientset, task BuildTask) error {
	jobName := buildJobName(task)
	namespace := "build-pipeline"

	_ = clientset.BatchV1().Jobs(namespace).Delete(ctx, jobName, metav1.DeleteOptions{
		PropagationPolicy: ptr(metav1.DeletePropagationForeground),
	})

	contextURL := task.SourceURL
	if contextURL == "" {
		contextURL = "s3://$(BUCKET_NAME)/" + task.SourceTarball
	}

	job := &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      jobName,
			Namespace: namespace,
		},
		Spec: batchv1.JobSpec{
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					InitContainers: []corev1.Container{
						{
							Name:    "fetch-context",
							Image:   "busybox",
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
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:  "kaniko",
							Image: "gcr.io/kaniko-project/executor:latest",
							Args: []string{
								"--dockerfile=" + task.DockerfilePath,
								"--context=dir:///workspace",
								"--destination=" + task.Registry + "/" + task.ServiceName + ":" + task.Version,
								"--destination=" + task.Registry + "/" + task.ServiceName + ":latest",
								"--insecure",
								"--skip-tls-verify",
							},
							SecurityContext: &corev1.SecurityContext{AllowPrivilegeEscalation: ptr(true)},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "workspace", MountPath: "/workspace"},
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
					Volumes:       []corev1.Volume{{Name: "workspace", VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}}}},
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
	return err
}

func buildJobName(task BuildTask) string {
	return fmt.Sprintf("kaniko-build-%s-%s", task.ServiceName, task.Version)
}

func statusKey(service, version string) string {
	return strings.TrimSpace(service) + ":" + strings.TrimSpace(version)
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
