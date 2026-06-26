# Horizontal Scale-Out: Embedding & Planner CPU Pods with Pulsar Fan-out

**Status:** Design — decisions finalized, ready for implementation
**Target nodes:** worker-0 through worker-2 (10.0.0.110–112, 8 vCPU, 28 GB RAM each)

---

## Design Decisions

| # | Decision |
|---|---|
| 1 | embed-gateway deployed as Deployment with per-instance nodeSelector (not DaemonSet) |
| 2 | **Option C**: per-worker-instance stable result topics + in-process dispatch map (mux) |
| 3 | Qdrant searches parallelized with `errgroup` after embedding fan-out gather |
| 4 | embed-gateway RBAC generated and applied; uses dedicated ServiceAccount |
| 5 | Feature-flag fallback to serial HTTP with explicit log lines on every fallback event |
| 6 | Model seeding expected at initial deploy and on model updates; `seed-models.sh` extended |

---

## 1. Current State

```
inference-0 (10.0.0.120, llama3.1)
  ollama-llama3          GPU  1 replica  NUM_PARALLEL=1  MAX_LOADED=2
  ollama-embed-0         CPU  1 replica  NUM_PARALLEL=2  MAX_LOADED=2  [all-minilm + nomic]
  ollama-planner-cpu-0   CPU  1 replica  NUM_PARALLEL=1  MAX_LOADED=1  [llama3.2:3b]

inference-1 (10.0.0.121, granite3.1-dense-8b)
  ollama-granite31-8b    GPU  1 replica  NUM_PARALLEL=1  MAX_LOADED=2
  ollama-embed-1         CPU  1 replica  NUM_PARALLEL=2  MAX_LOADED=2  [all-minilm + nomic]
  ollama-planner-cpu-1   CPU  1 replica  NUM_PARALLEL=1  MAX_LOADED=1  [llama3.2:3b]

Services (llms-ollama namespace):
  ollama-embed         ClusterIP  selector: ollama-role=embed       → 2 endpoints
  ollama-planner-cpu   ClusterIP  selector: ollama-role=planner-cpu → 2 endpoints
```

Serial embedding call path in `searchEmbeddingModelOnce` (`pipeline.go:744`):
```
for each subQuery:
  embedder.GetEmbeddings(ctx, sq)   ← sequential Ollama HTTP ~1-5s
  h.searcher.Search(...)            ← sequential Qdrant
```
With 3 sub-queries × 2 embedding models = 6 serial Ollama calls before any Qdrant work.

---

## 2. Target Topology

```
inference-0 (10.0.0.120)            ← unchanged
  ollama-llama3          GPU
  ollama-embed-0         CPU  NUM_PARALLEL=2  [unchanged — shares node with GPU pod]
  ollama-planner-cpu-0   CPU  NUM_PARALLEL=1  [unchanged]

inference-1 (10.0.0.121)            ← unchanged
  ollama-granite31-8b    GPU
  ollama-embed-1         CPU  NUM_PARALLEL=2  [unchanged]
  ollama-planner-cpu-1   CPU  NUM_PARALLEL=1  [unchanged]

worker-0 (10.0.0.110)  embed-instance=0
  ollama-embed-2         CPU  NUM_PARALLEL=4  MAX_LOADED=2
  ollama-embed-3         CPU  NUM_PARALLEL=4  MAX_LOADED=2
  ollama-planner-cpu-2   CPU  NUM_PARALLEL=2  MAX_LOADED=1
  embed-gateway-0        (new service — Pulsar consumer → node-local embed → result topic)

worker-1 (10.0.0.111)  embed-instance=1
  ollama-embed-4         CPU  NUM_PARALLEL=4  MAX_LOADED=2
  ollama-embed-5         CPU  NUM_PARALLEL=4  MAX_LOADED=2
  ollama-planner-cpu-3   CPU  NUM_PARALLEL=2  MAX_LOADED=1
  embed-gateway-1

worker-2 (10.0.0.112)  embed-instance=2
  ollama-embed-6         CPU  NUM_PARALLEL=4  MAX_LOADED=2
  ollama-embed-7         CPU  NUM_PARALLEL=4  MAX_LOADED=2
  ollama-planner-cpu-4   CPU  NUM_PARALLEL=2  MAX_LOADED=1
  embed-gateway-2

Services (updated):
  ollama-embed         ClusterIP  → 8 endpoints  (2 existing + 6 new)
  ollama-planner-cpu   ClusterIP  → 5 endpoints   (2 existing + 3 new)
```

Total concurrent embedding capacity:
- 10 pods × avg NUM_PARALLEL=3.6 ≈ **36 concurrent embedding slots**
- Each pod holds both models resident: all-minilm (46 MB) + nomic (274 MB) = 320 MB per pod

Total concurrent planner-cpu capacity:
- 6 pods × avg NUM_PARALLEL=1.3 ≈ **8 concurrent planning slots**

---

## 3. Resource Budget Per Worker Node

| Component | CPU req | CPU limit | Mem req | Mem limit | Model in-mem |
|---|---|---|---|---|---|
| ollama-embed (×2) | 500m | 2000m | 512Mi | 2Gi | 320 MB each |
| ollama-planner-cpu (×1) | 1000m | 4000m | 3Gi | 6Gi | ~2.2 GB |
| embed-gateway (×1) | 100m | 500m | 128Mi | 256Mi | none |
| **Node total (requests)** | **2100m / 8000m** | — | **~4.3Gi / 28Gi** | — | ~2.8 GB |

26% CPU, 15% RAM reserved at request baseline. Substantial burst headroom remains.

---

## 4. Kubernetes Changes

### 4.1 Node Labels

```bash
kubectl label nodes worker-0 role=worker-node embed-instance=0 --overwrite
kubectl label nodes worker-1 role=worker-node embed-instance=1 --overwrite
kubectl label nodes worker-2 role=worker-node embed-instance=2 --overwrite
```

### 4.2 values-embed-worker.yaml (new file for worker-node embed pods)

Worker nodes carry `role=storage-node` (not `role=worker-node`). The base nodeSelector
uses that label; `embed-instance=N` is added per-release via `--set` at deploy time.

```yaml
# values-embed-worker.yaml — CPU-only Ollama for embedding on worker nodes
# Higher NUM_PARALLEL than inference-node embed pods (no GPU pod to compete with).

replicaCount: 1

image:
  repository: registry.container-registry.svc.cluster.local:5000/ollama/ollama
  pullPolicy: IfNotPresent
  tag: ""

namespaceOverride: "llms-ollama"

service:
  enabled: false

ollama:
  port: 11434
  gpu:
    enabled: false
  models:
    pull: []
    run: []
    create: []
    clean: false
  insecure: false

podLabels:
  ollama-role: embed

volumes:
  - name: registry-ca
    configMap:
      name: registry-ca-cm

volumeMounts:
  - name: registry-ca
    mountPath: /etc/ssl/certs/ca-certificates.crt
    subPath: ca.crt

extraEnv:
  - name: OLLAMA_HOST
    value: "0.0.0.0:11434"
  - name: OLLAMA_REGISTRY_INSECURE
    value: "0"
  - name: SSL_CERT_FILE
    value: "/etc/ssl/certs/ca-certificates.crt"
  - name: OLLAMA_KEEP_ALIVE
    value: "-1"
  - name: OLLAMA_NUM_PARALLEL
    value: "4"
  - name: OLLAMA_MAX_LOADED_MODELS
    value: "2"

resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "2000m"
    memory: "2Gi"

persistentVolume:
  enabled: true
  accessModes:
    - ReadWriteMany
  size: 10Gi
  storageClass: "rook-cephfs"
  volumeMode: "Filesystem"

# Base nodeSelector — embed-instance=N added at deploy time via --set
nodeSelector:
  role: storage-node   # worker nodes already carry this label

updateStrategy:
  type: "Recreate"

terminationGracePeriodSeconds: 30

livenessProbe:
  enabled: true
  path: /
  initialDelaySeconds: 60
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6
  successThreshold: 1

readinessProbe:
  enabled: true
  path: /
  initialDelaySeconds: 30
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 6
  successThreshold: 1
```

### 4.3 values-planner-cpu-worker.yaml (new file)

```yaml
# values-planner-cpu-worker.yaml — CPU-only Ollama for planner on worker nodes
# NUM_PARALLEL=2 since worker nodes have more available CPU than inference nodes.

replicaCount: 1

image:
  repository: registry.container-registry.svc.cluster.local:5000/ollama/ollama
  pullPolicy: IfNotPresent
  tag: ""

namespaceOverride: "llms-ollama"

service:
  enabled: false

ollama:
  port: 11434
  gpu:
    enabled: false
  models:
    pull: []
    run: []
    create: []
    clean: false
  insecure: false

podLabels:
  ollama-role: planner-cpu

volumes:
  - name: registry-ca
    configMap:
      name: registry-ca-cm

volumeMounts:
  - name: registry-ca
    mountPath: /etc/ssl/certs/ca-certificates.crt
    subPath: ca.crt

extraEnv:
  - name: OLLAMA_HOST
    value: "0.0.0.0:11434"
  - name: OLLAMA_REGISTRY_INSECURE
    value: "0"
  - name: SSL_CERT_FILE
    value: "/etc/ssl/certs/ca-certificates.crt"
  - name: OLLAMA_KEEP_ALIVE
    value: "-1"
  - name: OLLAMA_NUM_PARALLEL
    value: "2"
  - name: OLLAMA_MAX_LOADED_MODELS
    value: "1"
  - name: OLLAMA_NUM_CTX
    value: "4096"

resources:
  requests:
    cpu: "1000m"
    memory: "3Gi"
  limits:
    cpu: "4000m"
    memory: "6Gi"

persistentVolume:
  enabled: true
  accessModes:
    - ReadWriteMany
  size: 10Gi
  storageClass: "rook-cephfs"
  volumeMode: "Filesystem"

# Base nodeSelector — embed-instance=N added at deploy time via --set
nodeSelector:
  role: storage-node   # worker nodes already carry this label

updateStrategy:
  type: "Recreate"

terminationGracePeriodSeconds: 60

livenessProbe:
  enabled: true
  path: /
  initialDelaySeconds: 60
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6
  successThreshold: 1

readinessProbe:
  enabled: true
  path: /
  initialDelaySeconds: 30
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 6
  successThreshold: 1
```

### 4.4 Helm Release Commands (additions to ollama.sh)

```bash
# 2 embed pods per worker node, pinned by embed-instance label
for INSTANCE in 0 1 2; do
  for OFFSET in 0 1; do
    IDX=$(( INSTANCE * 2 + OFFSET + 2 ))   # pods 2-7
    helm upgrade --install ollama-embed-${IDX} otwld/ollama \
      --namespace llms-ollama \
      -f "$SCRIPT_DIR/values-embed-worker.yaml" \
      --set "nodeSelector.embed-instance=${INSTANCE}" \
      --set image.repository="${REGISTRY}/ollama/ollama" \
      --set image.tag="0.15.6"
  done
done

# 1 planner-cpu pod per worker node
for INSTANCE in 0 1 2; do
  IDX=$(( INSTANCE + 2 ))   # pods 2-4
  helm upgrade --install ollama-planner-cpu-${IDX} otwld/ollama \
    --namespace llms-ollama \
    -f "$SCRIPT_DIR/values-planner-cpu-worker.yaml" \
    --set "nodeSelector.embed-instance=${INSTANCE}" \
    --set image.repository="${REGISTRY}/ollama/ollama" \
    --set image.tag="0.15.6"
done
```

---

## 5. Pulsar Topics

### 5.1 Topic Design — Option C: Per-Worker-Instance Result Topics

```
persistent://rag-pipeline/embed/jobs
  Partitions:  8
  Retention:   10 min / 100 MB
  TTL:         60 s  (stale jobs with expired deadline_unix are discarded by gateway)

persistent://rag-pipeline/embed/results-{workerPodName}
  e.g. results-rag-worker-0, results-rag-worker-1, ...
  Partitions:  1 per topic (non-partitioned)
  Retention:   10 min / 50 MB
  TTL:         5 min
  Auto-create: yes, on first rag-worker startup
```

**Why Option C over alternatives:**

| | A: Per-request ephemeral | B: Shared topic | C: Per-worker-instance |
|---|---|---|---|
| Topic count | O(req/s) — high churn | 1 | O(worker replicas) — stable |
| ZooKeeper pressure | High at scale | None | Minimal |
| Routing accuracy | Exact (by reqID in topic name) | Requires client-side filter | Exact (gateway routes by worker_instance_id) |
| Multi-request mux | Not needed | Not needed | Required — in-process dispatch map |
| Monitoring | Noisy | Easy | Easy (one topic per worker) |
| Cleanup | TTL auto | N/A | TTL auto |

### 5.2 Namespace Policies

```bash
pulsar-admin namespaces create rag-pipeline/embed
pulsar-admin namespaces set-retention rag-pipeline/embed \
  --size 500M --time 10m
pulsar-admin namespaces set-message-ttl rag-pipeline/embed \
  --messageTTL 300
pulsar-admin namespaces set-auto-topic-creation rag-pipeline/embed \
  --enable --type non-partitioned
pulsar-admin topics create-partitioned-topic \
  persistent://rag-pipeline/embed/jobs --partitions 8
```

---

## 6. embed-gateway Service

New Go service: `rag-stack/services/embed-gateway/`

### 6.1 embed-gateway Deployment (per worker node, embed-instance=N)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: embed-gateway-0
  namespace: rag-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: embed-gateway
      instance: "0"
  template:
    metadata:
      labels:
        app: embed-gateway
        instance: "0"
    spec:
      serviceAccountName: embed-gateway
      nodeSelector:
        embed-instance: "0"
      containers:
        - name: embed-gateway
          image: registry.container-registry.svc.cluster.local:5000/embed-gateway:latest
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: PULSAR_URL
              value: "pulsar+ssl://pulsar-proxy.apache-pulsar.svc.cluster.local:6651"
            - name: EMBED_JOBS_TOPIC
              value: "persistent://rag-pipeline/embed/jobs"
            - name: EMBED_SUBSCRIPTION
              value: "embed-gw-sub"
            - name: EMBED_GATEWAY_WORKERS
              value: "8"
            - name: EMBED_GATEWAY_ID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: OLLAMA_EMBED_NAMESPACE
              value: "llms-ollama"
            - name: OLLAMA_EMBED_FALLBACK_URL
              value: "http://ollama-embed.llms-ollama.svc.cluster.local:11434"
            - name: SSL_CERT_FILE
              value: "/etc/ssl/certs/ca-certificates.crt"
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
          volumeMounts:
            - name: registry-ca
              mountPath: /etc/ssl/certs/ca-certificates.crt
              subPath: ca.crt
      volumes:
        - name: registry-ca
          configMap:
            name: registry-ca-cm
---
# Repeat for embed-gateway-1 (instance: "1"), embed-gateway-2
```

### 6.2 RBAC

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: embed-gateway
  namespace: rag-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: embed-gateway-pod-reader
  namespace: llms-ollama
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: embed-gateway-pod-reader
  namespace: llms-ollama
subjects:
  - kind: ServiceAccount
    name: embed-gateway
    namespace: rag-system
roleRef:
  kind: Role
  name: embed-gateway-pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### 6.3 Node-Local Embed URL Discovery

On startup, embed-gateway reads its node name from the downward API env var and queries
the Kubernetes API for pods with `ollama-role=embed` on the same node:

```go
func discoverLocalEmbedURL(k8sClient kubernetes.Interface, nodeName, namespace string) (string, error) {
    pods, err := k8sClient.CoreV1().Pods(namespace).List(context.Background(), metav1.ListOptions{
        LabelSelector: "ollama-role=embed",
        FieldSelector: "spec.nodeName=" + nodeName + ",status.phase=Running",
    })
    if err != nil || len(pods.Items) == 0 {
        return "", fmt.Errorf("no local embed pods found on node %s: %w", nodeName, err)
    }
    // Round-robin across local pods; re-discover on connection failure
    urls := make([]string, 0, len(pods.Items))
    for _, pod := range pods.Items {
        if pod.Status.PodIP != "" {
            urls = append(urls, fmt.Sprintf("http://%s:11434", pod.Status.PodIP))
        }
    }
    return urls[0], nil  // initial selection; gateway rotates on error
}
```

Fallback to `OLLAMA_EMBED_FALLBACK_URL` (cluster-wide service) if discovery fails, with log:
```
[embed-gateway-0] Node-local embed discovery failed on node worker-0: no local embed pods found — falling back to cluster service
```

Re-discovery is triggered on each HTTP 503/connection-refused from the local pod.

### 6.4 Message Schemas

**EmbedJob** (rag-worker → `embed/jobs`):
```json
{
  "request_id":         "abc-123-def",
  "sub_query_index":    2,
  "sub_query":          "what is the authentication token",
  "embedding_model":    "all-minilm:l6-v2",
  "vector_size":        384,
  "worker_instance_id": "rag-worker-0",
  "deadline_unix":      1748484060
}
```

Pulsar message properties (header):
```
request_id:  abc-123-def
worker_id:   rag-worker-0
model:       all-minilm:l6-v2
```

**EmbedResult** (embed-gateway → `embed/results-rag-worker-0`):
```json
{
  "request_id":       "abc-123-def",
  "sub_query_index":  2,
  "embedding_model":  "all-minilm:l6-v2",
  "vector":           [0.123, 0.456, ...],
  "error":            "",
  "duration_ms":      47,
  "gateway_id":       "embed-gateway-2"
}
```

### 6.5 embed-gateway Worker Loop

```go
func (g *Gateway) Run(ctx context.Context) {
    sem := make(chan struct{}, g.workers)
    for {
        msg, err := g.consumer.Receive(ctx)
        if err != nil {
            logging.Printf("[%s] consumer receive error: %v", g.gatewayID, err)
            return
        }

        sem <- struct{}{}
        go func(m pulsar.Message) {
            defer func() { <-sem }()
            g.processJob(ctx, m)
        }(msg)
    }
}

func (g *Gateway) processJob(ctx context.Context, msg pulsar.Message) {
    var job EmbedJob
    if err := json.Unmarshal(msg.Payload(), &job); err != nil {
        logging.Printf("[%s] malformed embed job — acking and discarding: %v", g.gatewayID, err)
        g.consumer.Ack(msg)
        return
    }

    if time.Now().Unix() > job.DeadlineUnix {
        logging.Printf("[%s] embed job for request %s sub-query %d expired (deadline %d) — discarding",
            g.gatewayID, job.RequestID, job.SubQueryIndex, job.DeadlineUnix)
        g.consumer.Ack(msg)
        return
    }

    start := time.Now()
    vector, err := g.ollamaClient.GetEmbeddings(ctx, job.SubQuery, job.EmbeddingModel)
    durationMs := time.Since(start).Milliseconds()

    result := EmbedResult{
        RequestID:      job.RequestID,
        SubQueryIndex:  job.SubQueryIndex,
        EmbeddingModel: job.EmbeddingModel,
        DurationMs:     durationMs,
        GatewayID:      g.gatewayID,
    }

    if err != nil {
        logging.Printf("[%s] Ollama embed failed for request %s sub-query %d model=%s: %v",
            g.gatewayID, job.RequestID, job.SubQueryIndex, job.EmbeddingModel, err)
        result.Error = err.Error()
        // Nack on transient Ollama errors — another gateway may pick it up
        if isTransientOllamaError(err) {
            g.consumer.NackID(msg.ID())
            return
        }
    } else {
        result.Vector = vector
        logging.Printf("[%s] embed complete request=%s sub_query=%d model=%s dims=%d duration=%dms",
            g.gatewayID, job.RequestID, job.SubQueryIndex, job.EmbeddingModel, len(vector), durationMs)
    }

    replyTopic := fmt.Sprintf("persistent://rag-pipeline/embed/results-%s", job.WorkerInstanceID)
    if err := g.publishResult(ctx, replyTopic, result); err != nil {
        logging.Printf("[%s] failed to publish result for request %s sub-query %d to %s: %v",
            g.gatewayID, job.RequestID, job.SubQueryIndex, replyTopic, err)
        g.consumer.NackID(msg.ID())
        return
    }

    g.consumer.Ack(msg)
}
```

---

## 7. rag-worker Changes

### 7.1 New Config Fields (config.go)

```go
PulsarEmbedJobsTopic    string        // "persistent://rag-pipeline/embed/jobs"
PulsarEmbedNamespace    string        // "persistent://rag-pipeline/embed/"
EmbedFanoutTimeout      time.Duration // default 30s
EmbedFanoutEnabled      bool          // default false; set EMBED_FANOUT_ENABLED=true to activate
WorkerInstanceID        string        // read from POD_NAME env (downward API)
```

Env var additions:
```go
EmbedFanoutEnabled:   envutil.GetEnvBool("EMBED_FANOUT_ENABLED", false),
WorkerInstanceID:     envutil.GetEnv("POD_NAME", "rag-worker-unknown"),
PulsarEmbedJobsTopic: envutil.GetEnv("PULSAR_EMBED_JOBS_TOPIC",
                        "persistent://rag-pipeline/embed/jobs"),
PulsarEmbedNamespace: envutil.GetEnv("PULSAR_EMBED_NAMESPACE",
                        "persistent://rag-pipeline/embed/"),
EmbedFanoutTimeout:   envutil.GetEnvDuration("EMBED_FANOUT_TIMEOUT", 30*time.Second),
```

### 7.2 ResultDispatcher — In-Process Mux for Per-Worker Result Topic

One dispatcher per rag-worker instance. It owns a single Pulsar consumer on
`persistent://rag-pipeline/embed/results-{POD_NAME}` and dispatches incoming results
to the correct in-flight request channel by `request_id`.

```go
// pkg/embed/dispatcher.go

type EmbedResult struct {
    RequestID      string    `json:"request_id"`
    SubQueryIndex  int       `json:"sub_query_index"`
    EmbeddingModel string    `json:"embedding_model"`
    Vector         []float32 `json:"vector"`
    Error          string    `json:"error"`
    DurationMs     int64     `json:"duration_ms"`
    GatewayID      string    `json:"gateway_id"`
}

type ResultDispatcher struct {
    mu       sync.RWMutex
    pending  map[string]chan EmbedResult  // requestID → buffered channel
    consumer pulsar.Consumer
    topic    string
}

func NewResultDispatcher(pulsarClient pulsar.Client, workerInstanceID string) (*ResultDispatcher, error) {
    topic := fmt.Sprintf("persistent://rag-pipeline/embed/results-%s", workerInstanceID)
    consumer, err := pulsarClient.Subscribe(pulsar.ConsumerOptions{
        Topic:            topic,
        SubscriptionName: "embed-results-sub",
        Type:             pulsar.Exclusive,
        // Exclusive: only this worker instance consumes from its own result topic.
        // No competing consumers — guaranteed delivery to correct pod.
    })
    if err != nil {
        return nil, fmt.Errorf("result dispatcher subscribe to %s: %w", topic, err)
    }
    return &ResultDispatcher{
        pending:  make(map[string]chan EmbedResult),
        consumer: consumer,
        topic:    topic,
    }, nil
}

// Register allocates a buffered channel for an in-flight request.
// Must be called BEFORE publishing embed jobs to avoid missing results.
// n = number of results expected (len(subQueries)).
func (d *ResultDispatcher) Register(requestID string, n int) <-chan EmbedResult {
    ch := make(chan EmbedResult, n)
    d.mu.Lock()
    d.pending[requestID] = ch
    d.mu.Unlock()
    return ch
}

// Deregister removes the channel mapping. Called in a defer after gather completes.
func (d *ResultDispatcher) Deregister(requestID string) {
    d.mu.Lock()
    delete(d.pending, requestID)
    d.mu.Unlock()
}

// Run is the dispatcher's main loop. Runs as a background goroutine for the
// lifetime of the rag-worker process.
func (d *ResultDispatcher) Run(ctx context.Context) {
    logging.Printf("[result-dispatcher] started on topic %s", d.topic)
    for {
        msg, err := d.consumer.Receive(ctx)
        if err != nil {
            if ctx.Err() != nil {
                logging.Printf("[result-dispatcher] shutting down: %v", ctx.Err())
                return
            }
            logging.Printf("[result-dispatcher] receive error: %v — retrying", err)
            continue
        }

        var result EmbedResult
        if err := json.Unmarshal(msg.Payload(), &result); err != nil {
            logging.Printf("[result-dispatcher] malformed result message — discarding: %v", err)
            d.consumer.Ack(msg)
            continue
        }

        d.mu.RLock()
        ch, ok := d.pending[result.RequestID]
        d.mu.RUnlock()

        if ok {
            ch <- result
            logging.Printf("[result-dispatcher] dispatched result request=%s sub_query=%d model=%s gateway=%s duration=%dms",
                result.RequestID, result.SubQueryIndex, result.EmbeddingModel,
                result.GatewayID, result.DurationMs)
        } else {
            // Stale result — request already timed out or completed
            logging.Printf("[result-dispatcher] stale result for request %s sub_query=%d model=%s gateway=%s — no pending handler (request may have timed out)",
                result.RequestID, result.SubQueryIndex, result.EmbeddingModel, result.GatewayID)
        }
        d.consumer.Ack(msg)
    }
}
```

### 7.3 Handler Additions

`Handler` gains:
```go
type Handler struct {
    // ... existing fields ...
    pulsarClient     pulsar.Client
    embedProducer    pulsar.Producer
    resultDispatcher *embed.ResultDispatcher
    instanceID       string  // POD_NAME from env
}
```

On startup, `NewHandler` initializes:
1. `embedProducer` — long-lived producer on `embed/jobs` topic
2. `resultDispatcher` — starts its `Run()` goroutine in the background
3. `instanceID` — from `cfg.WorkerInstanceID`

### 7.4 embedFanout Function

```go
// embedFanout fans out embedding calls for all subQueries to the Pulsar
// embed/jobs topic and gathers results via the per-worker result dispatcher.
// On any error, returns a non-nil error and the caller falls back to serial HTTP.
func (h *Handler) embedFanout(
    ctx context.Context,
    reqID string,
    embeddingModel string,
    subQueries []string,
) ([]embedQueryResult, error) {

    n := len(subQueries)

    // Register BEFORE publishing — avoids a race where a fast gateway
    // publishes results before we are listening.
    resultCh := h.resultDispatcher.Register(reqID, n)
    defer h.resultDispatcher.Deregister(reqID)

    deadline := time.Now().Add(h.cfg.EmbedFanoutTimeout)

    // Fan out: one job per sub-query
    for i, sq := range subQueries {
        job := EmbedJob{
            RequestID:        reqID,
            SubQueryIndex:    i,
            SubQuery:         sq,
            EmbeddingModel:   embeddingModel,
            VectorSize:       vectorSizeFor(embeddingModel),
            WorkerInstanceID: h.instanceID,
            DeadlineUnix:     deadline.Unix(),
        }
        payload, _ := json.Marshal(job)
        if _, err := h.embedProducer.Send(ctx, &pulsar.ProducerMessage{
            Payload: payload,
            Properties: map[string]string{
                "request_id": reqID,
                "worker_id":  h.instanceID,
                "model":      embeddingModel,
            },
        }); err != nil {
            return nil, fmt.Errorf("embed fanout: publish sub-query %d: %w", i, err)
        }
    }
    logging.Printf("[%s] embed fanout: published %d jobs model=%s timeout=%s",
        reqID, n, embeddingModel, h.cfg.EmbedFanoutTimeout)

    // Gather results
    results := make([]embedQueryResult, n)
    gathered := 0
    gatherCtx, cancel := context.WithDeadline(ctx, deadline)
    defer cancel()

    for gathered < n {
        select {
        case result := <-resultCh:
            if result.Error != "" {
                logging.Printf("[%s] embed fanout: sub-query %d error from gateway %s: %s — marking as empty",
                    reqID, result.SubQueryIndex, result.GatewayID, result.Error)
                gathered++
                continue
            }
            results[result.SubQueryIndex] = embedQueryResult{
                SubQuery: subQueries[result.SubQueryIndex],
                Vector:   result.Vector,
            }
            gathered++
        case <-gatherCtx.Done():
            logging.Printf("[%s] embed fanout: TIMEOUT — gathered %d/%d results model=%s "+
                "timeout=%s — falling back to serial HTTP",
                reqID, gathered, n, embeddingModel, h.cfg.EmbedFanoutTimeout)
            return nil, fmt.Errorf("embed fanout timeout: %d/%d", gathered, n)
        case <-ctx.Done():
            return nil, ctx.Err()
        }
    }

    logging.Printf("[%s] embed fanout: complete %d/%d results gathered model=%s",
        reqID, gathered, n, embeddingModel)
    return results, nil
}
```

### 7.5 searchEmbeddingModelOnce Integration

The sub-query loop in `searchEmbeddingModelOnce` becomes:

```go
// --- Embedding phase ---
type embedQueryResult struct {
    SubQuery string
    Vector   []float32
}

var embeddedQueries []embedQueryResult

if h.cfg.EmbedFanoutEnabled {
    fanoutResults, err := h.embedFanout(ctx, req.Id, embeddingModel, subQueries)
    if err != nil {
        logging.Printf("[%s][SID:%d] embed fanout failed — falling back to serial HTTP: %v",
            req.Id, req.SessionId, err)
        // fall through to serial loop below
    } else {
        embeddedQueries = fanoutResults
    }
}

if embeddedQueries == nil {
    // Serial fallback — existing behaviour, unchanged
    logging.Printf("[%s][SID:%d] embed fanout disabled or failed — using serial HTTP for %d sub-queries model=%s",
        req.Id, req.SessionId, len(subQueries), embeddingModel)
    for _, sq := range subQueries {
        vector, err := embedder.GetEmbeddings(ctx, sq)
        if err != nil { /* ... existing error handling ... */ continue }
        embeddedQueries = append(embeddedQueries, embedQueryResult{SubQuery: sq, Vector: vector})
    }
}

// --- Parallel Qdrant search phase ---
var (
    mu              sync.Mutex
    missingColl     bool
)
g, gCtx := errgroup.WithContext(ctx)
qdrantResults := make([][]interface{}, len(embeddedQueries))

for i, eq := range embeddedQueries {
    if len(eq.Vector) == 0 {
        continue
    }
    i, eq := i, eq
    g.Go(func() error {
        logging.Printf("[%s][SID:%d] qdrant search start sub_query=%d model=%s dims=%d",
            req.Id, req.SessionId, i, embeddingModel, len(eq.Vector))
        res, err := h.searcher.Search(
            gCtx, embeddingModel, eq.Vector, tags,
            req.SessionId, req.IncludeGlobal, h.cfg.QdrantSearchLimit,
        )
        if err != nil {
            if isMissingCollectionError(err) {
                mu.Lock()
                missingColl = true
                mu.Unlock()
                return nil
            }
            logging.Printf("[%s][SID:%d] qdrant search failed sub_query=%d: %v",
                req.Id, req.SessionId, i, err)
            return nil  // non-fatal; continue with other queries
        }
        logging.Printf("[%s][SID:%d] qdrant search complete sub_query=%d results=%d",
            req.Id, req.SessionId, i, len(res))
        qdrantResults[i] = res
        return nil
    })
}
if err := g.Wait(); err != nil {
    return nil, missingColl, err
}

for _, res := range qdrantResults {
    allRawResults = append(allRawResults, res...)
}
return allRawResults, missingColl, nil
```

---

## 8. Planner CPU Scaling

No Pulsar changes required. The existing `plan` topic consumers and `ollama-planner-cpu` ClusterIP
service handle distribution automatically:

- Multiple rag-worker pods each subscribe to `plan` topic (Shared subscription) — work is distributed
- Each rag-worker HTTP POSTs planning requests to `ollama-planner-cpu` service
- ClusterIP kube-proxy round-robins across all planner-cpu pod endpoints
- Adding 4 new pods on worker nodes expands the endpoint list from 2 → 6 transparently

Changes needed:
1. New Helm releases (`ollama-planner-cpu-2` through `-5`) per Section 4.4
2. `seed-models.sh` extended to seed `llama3.2:3b` on new pods (Section 9)
3. `NUM_PARALLEL=2` in `values-planner-cpu-worker.yaml` allows 2 concurrent plan calls per pod

---

## 9. Model Seeding (Extended)

Models must be seeded into new pods at initial deploy and whenever models are updated.
`seed-models.sh` additions:

```bash
# Seed new embed pods on worker nodes
for IDX in 2 3 4 5 6 7 8 9; do
  POD="ollama-embed-${IDX}"
  echo "Seeding embed models in ${POD}..."
  kubectl exec -n llms-ollama ${POD} -- \
    ollama pull all-minilm:l6-v2
  kubectl exec -n llms-ollama ${POD} -- \
    ollama pull nomic-embed-text
done

# Seed new planner-cpu pods on worker nodes
for IDX in 2 3 4 5; do
  POD="ollama-planner-cpu-${IDX}"
  echo "Seeding planner model in ${POD}..."
  kubectl exec -n llms-ollama ${POD} -- \
    ollama pull llama3.2:3b
done
```

Models are stored in `rook-cephfs` PVCs (ReadWriteMany). After the initial pull, subsequent
pod restarts on the same PVC load from disk without re-downloading. Seeding is idempotent —
re-running the script on already-seeded pods is safe (Ollama skips the pull if the model exists).

---

## 10. Data Flow After Implementation

```
rag-worker handleSearch (request abc-123)
  │
  ├─ resolveEmbeddingModelCandidates → [all-minilm, nomic-embed-text]
  │
  └─ for each embeddingModel:
       │
       ├─ resultDispatcher.Register("abc-123", 3)  ← allocate channel FIRST
       │
       ├─ embedProducer.Send × 3 → embed/jobs (8 partitions)
       │         │
       │         ├─ embed-gateway-0 (worker-0) picks job 0
       │         │    └─ local ollama-embed pod HTTP → result
       │         │         └─ publish → embed/results-rag-worker-0
       │         │
       │         ├─ embed-gateway-1 (worker-1) picks job 1
       │         │    └─ local ollama-embed pod HTTP → result
       │         │         └─ publish → embed/results-rag-worker-0
       │         │
       │         └─ embed-gateway-2 (worker-2) picks job 2
       │              └─ local ollama-embed pod HTTP → result
       │                   └─ publish → embed/results-rag-worker-0
       │
       ├─ resultDispatcher.Run() receives 3 results → dispatches to channel
       │
       ├─ embedFanout gather loop collects all 3 vectors
       │
       └─ parallel errgroup Qdrant searches (3 goroutines, same timeout context)
            ├─ searcher.Search(vector[0]) → results[0]
            ├─ searcher.Search(vector[1]) → results[1]
            └─ searcher.Search(vector[2]) → results[2]
                       ↓
               allRawResults merged, deduped, chunked → exec stage
```

**Latency projection (3 sub-queries, 2 embedding models):**

| Phase | Before | After |
|---|---|---|
| Embedding (6 calls) | ~6 × 2 s = 12 s serial | max(3 parallel) ≈ 2 s + ~10 ms Pulsar |
| Qdrant search (6 calls) | ~6 × 50 ms = 300 ms serial | max(3 parallel) ≈ 50 ms |
| **Total search stage** | **~12.3 s** | **~2.1 s** |

---

## 11. Rollout Sequence

1. Apply Pulsar namespace policies and create `embed/jobs` partitioned topic
2. Label worker nodes (`embed-instance=0..3`)
3. Deploy Helm releases: 8 embed pods, 4 planner-cpu pods on worker nodes
4. Wait for rollout; seed models into new pods
5. Apply RBAC (ServiceAccount, Role, RoleBinding)
6. Build and push `embed-gateway` image to internal registry
7. Deploy embed-gateway-0 through embed-gateway-3 (one per worker node)
8. Deploy rag-worker with `EMBED_FANOUT_ENABLED=false` (new config fields, dispatcher starts, no fanout yet)
9. Verify result topics are auto-created and dispatcher receives no messages (expected)
10. Enable `EMBED_FANOUT_ENABLED=true` on one rag-worker replica; monitor logs for fallback events
11. Roll out to all replicas once fanout is confirmed stable
