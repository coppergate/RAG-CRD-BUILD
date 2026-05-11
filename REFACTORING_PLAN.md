# Refactoring & Improvement Plan

**Version**: 3.0.x → 3.1.x
**Status**: Planned
**Principle**: Changes that affect multiple services are implemented in `common/` first. Each individual service then wires in the new common functionality with minimal edits (typically 1–5 lines). This batching strategy prevents editing the same service file repeatedly across unrelated tasks.

---

## Reading Order

Work through this document top to bottom. Each section assumes the previous is done.
Sections are ordered by blast radius and dependency:

1. [Critical Cross-Service Fixes](#1-critical-cross-service-fixes) — affects all services, do first
2. [Flutter UI Refactoring](#2-flutter-ui-refactoring) — independent, can run in parallel
3. [Eliminate Sync-Over-Async Patterns](#3-eliminate-sync-over-async-patterns) — architectural changes
4. [Monitoring Gap Remediation](#4-monitoring-gap-remediation) — infrastructure changes
5. [Priority Backlog](#5-priority-backlog) — ordered remaining work
6. [Alerting Rules](#6-alerting-rules) — last, depends on metrics being stable

---

## 1. Critical Cross-Service Fixes

These are single-file changes in `common/` that fix problems present in all services simultaneously. After completing each step, do a sweep of all services to wire in the change.

---

### 1.1 Fix the Pulsar Health Check (No-op Ping)

**Problem**: `common/pulsar/pulsar.go` `Ping()` returns `nil` without actually verifying connectivity. Every service registers this as a readiness check, so `/readyz` always passes even when Pulsar is unreachable.

**File to change**: `rag-stack/services/common/pulsar/pulsar.go`

**What to do**:

Replace the `Ping()` method. The Pulsar Go client does not expose a direct ping, but you can verify connectivity by attempting to get the partition metadata of a known topic. A lighter approach is to use the admin REST API, but the simplest correct approach within the existing client API is to create a producer on a temporary topic and immediately close it.

```go
// Ping verifies that the Pulsar broker is reachable by checking topic metadata.
func (c *Client) Ping() error {
    if c.Client == nil {
        return fmt.Errorf("pulsar client is nil")
    }
    ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
    defer cancel()
    // GetPartitionsForTopic is a lightweight admin call that requires broker
    // connectivity. Use a known durable topic that always exists.
    partitions, err := c.Client.TopicPartitions("persistent://public/default/health-ping")
    if err != nil {
        // Topic not existing is still a successful broker round-trip.
        // Only connection-level errors indicate a real failure.
        if strings.Contains(err.Error(), "connection refused") ||
            strings.Contains(err.Error(), "i/o timeout") ||
            strings.Contains(err.Error(), "no such host") {
            return fmt.Errorf("pulsar broker unreachable: %w", err)
        }
    }
    _ = partitions
    _ = ctx
    return nil
}
```

Add `"strings"` to imports. This single change propagates to all services that call `healthSrv.RegisterCheck("pulsar", pulsarClient.Ping)`.

**Verify**: After deploying, restart one service and kill the Pulsar proxy pod. The service's `/readyz` should return 503 within the 3-second timeout window.

---

### 1.2 Fix Silent Consumer Failures in db-adapter

**Problem**: `setupConsumers()` in `db-adapter/cmd/adapter/main.go` logs an error and continues if a consumer fails to subscribe. The service starts without that consumer, silently dropping all messages on that topic.

**File to change**: `rag-stack/services/db-adapter/cmd/adapter/main.go`

**What to do**:

Change `setupConsumers` to return an error instead of logging and continuing. Any consumer that fails to initialize is a fatal startup error — the service cannot function correctly without it.

```go
func setupConsumers(ctx context.Context, client *pulsarCommon.Client, cfg *config.Config,
    dlqHandler *dlq.Handler, processor *service.PulsarProcessor) error {

    consumers := []struct {
        topic        string
        subscription string
        handler      func(context.Context, pulsar.Message) (dlq.ProcessResult, error)
    }{
        {cfg.PromptTopic, cfg.Subscription, processor.HandlePrompt},
        {cfg.ResponseTopic, cfg.Subscription, processor.HandleResponse},
        {cfg.CompletionTopic, cfg.Subscription + "-metrics", processor.HandleCompletion},
        {cfg.DBOpsTopic, cfg.Subscription + "-ops", processor.HandleDBOp},
    }

    for _, c := range consumers {
        consumer, err := client.NewSharedConsumer(c.topic, c.subscription)
        if err != nil {
            return fmt.Errorf("failed to create consumer for topic %s: %w", c.topic, err)
        }
        go consumeLoop(ctx, consumer, dlqHandler, c.handler)
    }
    return nil
}
```

In `main()`, change the call site to:

```go
if err := setupConsumers(ctx, client, cfg, dlqHandler, processor); err != nil {
    log.Fatalf("consumer setup failed: %v", err)
}
```

**Why this matters**: A service that starts without its Pulsar consumers appears healthy (liveness passes) but drops messages silently. `log.Fatalf` at startup is the correct response — fail fast and let Kubernetes restart the pod rather than running in a degraded state.

---

### 1.3 Add DLQ Metrics to the Common DLQ Handler

**Problem**: The DLQ handler routes messages but emits no metrics. There is no observable signal when messages are being dead-lettered.

**File to change**: `rag-stack/services/common/dlq/dlq.go`

**What to do**:

Add three counters to the handler struct:

```go
type Handler struct {
    // existing fields ...
    dlqRouted    metric.Int64Counter
    dlqRetried   metric.Int64Counter
    dlqSucceeded metric.Int64Counter
}
```

In `NewHandler()`, initialize them using `telemetry.Meter("dlq")`:

```go
meter := telemetry.Meter("dlq")
h.dlqRouted, _ = meter.Int64Counter("dlq_routed_total",
    metric.WithDescription("Messages routed to DLQ (permanent failure)"))
h.dlqRetried, _ = meter.Int64Counter("dlq_retried_total",
    metric.WithDescription("Messages NACK'd for retry (transient failure)"))
h.dlqSucceeded, _ = meter.Int64Counter("dlq_succeeded_total",
    metric.WithDescription("Messages processed successfully"))
```

In `HandleMessage()`, increment the appropriate counter after each result. Add a `service` attribute so Mimir can break this down per service:

```go
attrs := metric.WithAttributes(attribute.String("service", h.serviceName))
switch result {
case ProcessResult(Success):
    h.dlqSucceeded.Add(ctx, 1, attrs)
case ProcessResult(TransientFailure):
    h.dlqRetried.Add(ctx, 1, attrs)
case ProcessResult(PermanentFailure):
    h.dlqRouted.Add(ctx, 1, attrs)
}
```

**This change benefits all 8 services that use `dlq.Handler` with zero per-service edits.**

---

### 1.4 Add an API Key to rag-admin-api

**Problem**: `rag-admin-api` has no authentication. Any network-reachable client can read sessions, write memory, modify behavioral rules, delete S3 objects, and query the database.

**File to change**: `rag-stack/services/rag-admin-api/cmd/admin-api/main.go`

**What to do**:

Add a middleware function that checks for a static API key in the `Authorization` header. The key is read from an environment variable and injected as a Kubernetes secret.

Add after the `corsHandler` definition in `main.go`:

```go
apiKey := os.Getenv("ADMIN_API_KEY")
authMiddleware := func(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // Health and metrics endpoints bypass auth
        if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" || r.URL.Path == "/health" {
            next.ServeHTTP(w, r)
            return
        }
        if apiKey != "" {
            token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
            if token != apiKey {
                http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
                return
            }
        }
        next.ServeHTTP(w, r)
    })
}
```

Change the handler chain from:

```go
otelHandler := otelhttp.NewHandler(corsHandler(mux), "rag-admin-api")
```

to:

```go
otelHandler := otelhttp.NewHandler(corsHandler(authMiddleware(mux)), "rag-admin-api")
```

Add `"strings"` to imports if not already present.

**Update `rag-admin-api/k8s/deployment.yaml`**: Add an env var reference:

```yaml
env:
  - name: ADMIN_API_KEY
    valueFrom:
      secretKeyRef:
        name: rag-admin-api-auth
        key: api-key
        optional: true   # optional=true means service starts without auth if secret absent
```

Create the secret on the cluster:

```bash
kubectl create secret generic rag-admin-api-auth \
  --from-literal=api-key="$(openssl rand -hex 32)" \
  -n rag-system
```

**Update the Flutter UI** (`app_config_provider.dart`): Add the API key to `AppConfig` and inject it as a Dio header in the interceptor. Store the key in shared_preferences or environment config — never in the source tree.

**Restrict CORS**: Change `Access-Control-Allow-Origin: *` to `Access-Control-Allow-Origin: https://rag-admin-api.rag.hierocracy.home` now that auth exists. Open CORS with open auth is a double vulnerability.

---

### 1.5 Fix WebSocket CORS Origin Check

**Problem**: `llm-gateway`'s WebSocket upgrader sets `CheckOrigin: func(r *http.Request) bool { return true }`, accepting connections from any origin.

**File to change**: `rag-stack/services/llm-gateway/` — locate the WebSocket upgrader.

**What to do**:

Change `CheckOrigin` to validate against an allowlist read from an environment variable:

```go
allowedOrigins := strings.Split(os.Getenv("ALLOWED_ORIGINS"), ",")
upgrader := websocket.Upgrader{
    CheckOrigin: func(r *http.Request) bool {
        origin := r.Header.Get("Origin")
        for _, allowed := range allowedOrigins {
            if strings.TrimSpace(allowed) == origin {
                return true
            }
        }
        return false
    },
}
```

Set `ALLOWED_ORIGINS=https://rag-admin-api.rag.hierocracy.home,https://rag-explorer.rag.hierocracy.home` in the deployment manifest.

---

### 1.6 Add Structured Logging with Trace ID to Common

**Problem**: Logs in Loki and traces in Tempo cannot be correlated because log lines do not include the OTLP trace ID. The `[SID:%d]` pattern exists but trace correlation is missing.

**New file to create**: `rag-stack/services/common/logging/logger.go`

**What to do**:

Create a thin logger wrapper that extracts the trace ID from context and injects it into each log line:

```go
package logging

import (
    "context"
    "fmt"
    "log"
    "go.opentelemetry.io/otel/trace"
)

// Infof logs with trace_id and span_id extracted from context.
func Infof(ctx context.Context, format string, args ...interface{}) {
    log.Printf("[INFO] [%s] %s", traceInfo(ctx), fmt.Sprintf(format, args...))
}

func Errorf(ctx context.Context, format string, args ...interface{}) {
    log.Printf("[ERROR] [%s] %s", traceInfo(ctx), fmt.Sprintf(format, args...))
}

func Warnf(ctx context.Context, format string, args ...interface{}) {
    log.Printf("[WARN] [%s] %s", traceInfo(ctx), fmt.Sprintf(format, args...))
}

func traceInfo(ctx context.Context) string {
    span := trace.SpanFromContext(ctx)
    sc := span.SpanContext()
    if sc.IsValid() {
        return fmt.Sprintf("trace=%s span=%s", sc.TraceID(), sc.SpanID())
    }
    return "trace=none"
}
```

Services then replace critical `log.Printf` calls with `logging.Infof(ctx, ...)` at the points where context is available (message handlers, HTTP handlers). Loki will now contain `trace=<id>` in the log lines, enabling direct jump from Grafana Tempo to the corresponding Loki logs.

This is a progressive change — do not refactor all logging at once. Target the message handler entry points in each service first, as those carry the most diagnostic value.

---

## 2. Flutter UI Refactoring

`chat_page.dart` is 1035 lines of mixed concerns. The decomposition below is ordered so each step is independently mergeable — do not attempt all at once.

---

### 2.1 Fix Hardcoded Service Endpoints First

**Problem**: `lib/config/service_endpoints.dart` contains hardcoded production URLs. If the admin API base URL changes, the app breaks silently because some paths are derived from config while others are baked in.

**File to change**: `lib/config/service_endpoints.dart`
**Supporting file**: `lib/config/app_config.dart`

**What to do**:

Delete `service_endpoints.dart`. It is no longer needed.

In `app_config.dart`, add computed getters for every derived URL based on `ragAdminApiUrl`:

```dart
@freezed
class AppConfig with _$AppConfig {
  const AppConfig._(); // enables custom getters

  const factory AppConfig({
    @Default('https://rag-admin-api.rag.hierocracy.home') String ragAdminApiUrl,
    // ... other fields
  }) = _AppConfig;

  String get chatUrl        => '$ragAdminApiUrl/api/chat';
  String get ingestUrl      => '$ragAdminApiUrl/api/ingest';
  String get s3Url          => '$ragAdminApiUrl/api/s3';
  String get dbUrl          => '$ragAdminApiUrl/api/db';
  String get qdrantUrl      => '$ragAdminApiUrl/api/qdrant';
  String get memoryUrl      => '$ragAdminApiUrl/api/memory';
  String get behaviorUrl    => '$ragAdminApiUrl/api/behavior';
  String get grafanaUrl     => '$ragAdminApiUrl/api/grafana';
}
```

Run `flutter pub run build_runner build --delete-conflicting-outputs` to regenerate Freezed code.

Search the codebase for any remaining references to `ServiceEndpoints.` and replace with the appropriate `config.xxxUrl` getter from the watched provider. Any file using `ServiceEndpoints` needs to be updated at this step.

---

### 2.2 Extract ChatPageNotifier (State Management)

**Problem**: `_ChatPageState` manages 15+ state variables and all business logic using `setState()`. This makes testing impossible and causes excessive widget rebuilds.

**New file to create**: `lib/features/chat/chat_notifier.dart`

**What to do**:

Define a state class and a `ChatNotifier` that extends `AutoDisposeAsyncNotifier`:

```dart
// chat_notifier.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
// ... model imports

part 'chat_notifier.g.dart';

class ChatState {
  final List<Session> sessions;
  final List<Tag> availableTags;
  final List<Tag> selectedTags;
  final Session? currentSession;
  final List<ResponseMessage> messages;
  final bool isStreaming;
  final bool inConversation;
  final int? selectedMessageIndex;
  final String selectedPlanner;
  final String selectedExecutor;

  const ChatState({...});

  ChatState copyWith({...});
}

@riverpod
class ChatNotifier extends _$ChatNotifier {
  @override
  Future<ChatState> build() async {
    // Load initial sessions and tags
    final service = ref.watch(chatServiceProvider);
    final sessions = await service.getSessions();
    final tags = await service.getTags();
    return ChatState(
      sessions: sessions,
      availableTags: tags,
      // ... defaults
    );
  }

  Future<void> loadSessions() async { ... }
  Future<void> createSession(String name) async { ... }
  Future<void> deleteSession(int id) async { ... }
  Future<void> selectSession(Session session) async { ... }
  void addTag(Tag t) { ... }
  void removeTag(Tag t) { ... }
  void selectMessage(int index) { ... }

  // Streaming is separate — returns a Stream the widget listens to
  Stream<ResponseMessage> sendMessage(String prompt) { ... }
}
```

Once this notifier exists, `_ChatPageState` can remove all its local state variables and replace them with `ref.watch(chatNotifierProvider)`. The `build()` method becomes small.

---

### 2.3 Extract Widget: SessionDrawer

**New file**: `lib/features/chat/widgets/session_drawer.dart`

Move out the left-side session list panel (currently inside `_ChatPageState.build()`). The drawer receives:
- `sessions: List<Session>`
- `currentSessionId: int?`
- `selectedIds: Set<int>`
- `onSelectSession: Function(Session)`
- `onDeleteSession: Function(int)`
- `onDeleteSelected: VoidCallback`
- `onNewSession: VoidCallback`

It is a `StatelessWidget` — all state lives in `ChatNotifier`. The drawer widget only renders what it is given and calls back.

---

### 2.4 Extract Widget: MessageList

**New file**: `lib/features/chat/widgets/message_list.dart`

Move out the scrollable chat message area:
- `messages: List<ResponseMessage>`
- `isStreaming: bool`
- `selectedMessageIndex: int?`
- `onSelectMessage: Function(int)`
- `scrollController: ScrollController`

The `_buildMessageBubble()` and `_buildMarkdownStyle()` methods belong here as private methods of this widget. The `SelectionArea` wrapper goes here too.

---

### 2.5 Extract Widget: MetadataPanel

**New file**: `lib/features/chat/widgets/metadata_panel.dart`

Move out the right-side metadata panel:
- `message: ResponseMessage?`
- `width: double`
- `onWidthChanged: Function(double)`

The panel currently uses `GestureDetector` for resize — keep that here. The `contexts`, `metrics`, `memory_trace` display logic is all internal to this widget.

---

### 2.6 Extract Widget: ChatInputBar

**New file**: `lib/features/chat/widgets/chat_input_bar.dart`

Move out the bottom input area:
- `enabled: bool`
- `isStreaming: bool`
- `controller: TextEditingController`
- `onSend: VoidCallback`
- `onStop: VoidCallback`
- `planner: String`
- `executor: String`
- `availableTags: List<Tag>`
- `selectedTags: List<Tag>`
- `onPlannerChanged: Function(String)`
- `onExecutorChanged: Function(String)`
- `onTagAdded: Function(Tag)`
- `onTagRemoved: Function(Tag)`

---

### 2.7 Reassemble ChatPage

After the four widget extractions, `chat_page.dart` becomes:

```dart
class ChatPage extends ConsumerWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatNotifierProvider);
    final notifier = ref.read(chatNotifierProvider.notifier);

    return state.when(
      loading: () => const CircularProgressIndicator(),
      error: (e, _) => ErrorView(error: e),
      data: (s) => Row(
        children: [
          SessionDrawer(sessions: s.sessions, ...),
          Expanded(child: Column(
            children: [
              Expanded(child: MessageList(messages: s.messages, ...)),
              ChatInputBar(...),
            ],
          )),
          if (s.showMetadata)
            MetadataPanel(message: s.selectedMessage, ...),
        ],
      ),
    );
  }
}
```

Target: under 80 lines. All state in `ChatNotifier`.

---

### 2.8 Implement Memory Page

**File**: `lib/features/memory/memory_page.dart`

The backend endpoints already exist. The Protobuf contracts define `MemoryWriteRequest`, `MemoryRetrieveRequest`, `MemoryItem`, `MemoryPack`.

The memory page needs:
1. A list of memory items for the current session (`GET /api/memory/items?session_id=X`)
2. A form to write a new memory item (`POST /api/memory/items`)
3. A retrieve panel showing what the `rag-worker` would receive for a given session (`POST /api/memory/retrieve`)

Create `lib/core/services/memory_service.dart` alongside `chat_service.dart` following the same pattern. Create a `MemoryNotifier` using the same Riverpod annotation approach established in step 2.2.

---

### 2.9 Implement Behavioral Rules UI

**File**: `lib/features/memory/behavioral_rules_page.dart` (new, or add a tab to memory_page)

Backend endpoints: `GET /api/behavior/rules`, `POST /api/behavior/learn`, `GET /api/behavior/identifiers`

The UI needs:
1. A list of active rules with status (ACTIVE / PENDING)
2. An "Accept" button for PENDING rules (maps to a status update endpoint)
3. A form to directly create a rule using the REMEMBER syntax
4. The action taxonomy table from `/api/behavior/identifiers`

This is the most visible Iteration 9 gap — the learning loop exists in the backend but is invisible to the user.

---

### 2.10 Implement Tag Merge

**File**: `lib/features/timescale/timescale_page.dart`

The dialog shell already exists. Wire it to `POST /api/db/maintenance/tags/merge`.

The request body is `{ "source_tag_ids": [int], "target_tag_id": int }`. The response is a job status. Show a progress dialog while the merge runs (poll `/api/db/maintenance/tags/merge/status` if that endpoint exists, otherwise show a spinner and close on success).

---

## 3. Eliminate Sync-Over-Async Patterns

These are architectural changes. Each requires coordinated changes to two services.

---

### 3.1 Replace Qdrant Pulsar Correlation with Direct HTTP

**Problem**: `rag-worker` sends a `QdrantOp` message to Pulsar, and `qdrant-adapter` publishes the result back. `rag-worker` then blocks on an in-memory channel waiting for the correlation ID. This adds ~20-100ms of unnecessary latency per search and creates a hidden synchronous dependency inside an async transport.

**Services affected**: `rag-worker`, `qdrant-adapter`

**Step 1 — Add an HTTP search endpoint to qdrant-adapter**:

In `qdrant-adapter/cmd/adapter/main.go`, register an HTTP handler:

```go
mux.HandleFunc("/search", h.HandleSearch)
mux.HandleFunc("/upsert", h.HandleUpsert)
mux.HandleFunc("/delete", h.HandleDelete)
```

`HandleSearch` deserializes a `QdrantOp` from the request body, calls the existing `qdrant.Client` search logic, and writes the `QdrantResponse` as JSON. This reuses 100% of the existing client code — only the transport changes.

**Step 2 — Add a Qdrant HTTP client to common**:

Create `common/clients/qdrant_client.go`:

```go
package clients

type QdrantHTTPClient struct {
    baseURL    string
    httpClient *http.Client
}

func NewQdrantHTTPClient(baseURL string) *QdrantHTTPClient { ... }

func (c *QdrantHTTPClient) Search(ctx context.Context, op *contracts.QdrantOp) (*contracts.QdrantResponse, error) {
    // POST /search with protojson body, return deserialized response
}
```

**Step 3 — Update rag-worker to use the HTTP client**:

In `rag-worker`, replace the Pulsar-based search call (the one that creates a correlation ID and blocks on a channel) with:

```go
resp, err := c.qdrantClient.Search(ctx, op)
```

Remove the results topic consumer from `rag-worker`. Remove the pending-channel map from `qdrant-adapter`.

**Step 4 — Keep the Pulsar consumer in qdrant-adapter for upsert/delete**:

Upsert and delete operations are fire-and-forget from the pipeline's perspective — they do not need a synchronous response. Keep those on Pulsar. Only the search path (which blocks) needs to move to HTTP.

**Step 5 — Update qdrant-adapter's config**:

Add `HTTP_ADDR` (default `:8082`) to expose the new HTTP API. Update the Kubernetes service to expose this port. Update the rag-worker deployment to set `QDRANT_ADAPTER_URL=http://qdrant-adapter.rag-system.svc:8082`.

---

### 3.2 Fix prompt-aggregator Polling

**Problem**: `prompt-aggregator` uses a 100ms sleep loop to poll for streaming chunks. This is CPU-wasteful and adds up to 100ms of unnecessary latency per chunk when the system is busy.

**File to change**: `rag-stack/services/prompt-aggregator/`

**What to do**:

Replace the polling reader with a proper Pulsar shared subscription on the session topic. The session topic already exists (`persistent://rag-pipeline/sessions/<correlation_id>`). Instead of manually seeking and reading:

```go
// Current (polling)
for {
    msg, err := reader.Next(ctx)
    if err != nil { time.Sleep(100 * time.Millisecond); continue }
    // process
}
```

Create a consumer subscription directly:

```go
consumer, err := client.Subscribe(pulsar.ConsumerOptions{
    Topic:            sessionTopic,
    SubscriptionName: "aggregator-" + correlationID,
    Type:             pulsar.Exclusive,
    SubscriptionInitialPosition: pulsar.SubscriptionPositionEarliest,
})
// No sleep. Receive() blocks until a message arrives.
for {
    msg, err := consumer.Receive(ctx)
    // process immediately
    consumer.Ack(msg)
}
```

The consumer unsubscribes and closes when `is_last=true` is received or context is cancelled. This removes all polling and reduces aggregation latency to message delivery latency.

**Note on cleanup**: Because subscriptions on session topics persist in ZooKeeper, ensure the consumer calls `consumer.Unsubscribe()` before closing. Otherwise, orphaned subscriptions accumulate.

---

### 3.3 Decouple rag-worker Pipeline Stages (Medium-Term)

**Problem**: All four pipeline stages (ingress, plan, search, exec) live in a single `rag-worker` binary. They cannot be scaled independently.

**This is a phased refactor, not a single PR.**

**Phase A — Establish the stage interface (do this now)**:

In `common/`, define a `PipelineStage` interface:

```go
type PipelineStage interface {
    Name() string
    InputTopic() string
    OutputTopic() string
    Process(ctx context.Context, msg *contracts.InternalRequest) (*contracts.InternalRequest, error)
}
```

Refactor the existing handlers in `rag-worker/pkg/pipeline/` to implement this interface. The `rag-worker` binary itself becomes a runner that hosts whatever stages it is configured to run via environment variables (`ENABLED_STAGES=ingress,plan,search,exec`).

**Phase B — Extract exec stage (do this next)**:

The `exec` stage is the most expensive and most worth scaling independently. Create a `rag-exec` service that:
- Subscribes to the `stage/exec` topic
- Implements only `handleExec`
- Publishes to completion and session topics

The `rag-worker` binary still handles ingress, plan, search. `rag-exec` handles execution. Both can be scaled independently via HPA.

**Phase C — Extract plan stage (later)**:

The plan stage calls the planner LLM and is latency-sensitive. Extract it to `rag-planner` after Phase B is proven stable.

Do not attempt Phases B or C until Phase A is complete and the stage interface is clean and tested.

---

## 4. Monitoring Gap Remediation

Work through these in order. Step 4.1 is the highest-impact change (fixes broken dashboards immediately).

---

### 4.1 Fix Dashboard Metric Name Mismatches

**Problem**: `rag-overview.yaml` (the `GrafanaDashboard` CR) references metrics that do not exist. Panels are empty in production.

**Files to change**: All dashboard JSON/YAML files in `infrastructure/APM/grafana/`

**What to do**:

Open `rag-overview.yaml` and find every `expr:` field. Replace non-existent metric names with the actual exported names:

| Dashboard query (current) | Replace with |
|---|---|
| `rag_stage_latency_ms` | `worker_task_duration_ms` |
| `rag_stage_errors_total` | `worker_errors_total` |
| `rag_active_sessions` | Remove until metric is added (Step 4.2) |
| `rag_recursions_total` | Remove until metric is added (Step 4.2) |
| `rag_messages_total` | `db_queries_total` as a proxy, or remove |

Do the same audit for `rag-performance.json` and `rag-operations.json`. Open each file, search for every `expr:` field, and verify the metric name is in the list of actually-exported metrics confirmed in the monitoring analysis. Any query referencing a metric not in that list must be either fixed or commented out with a placeholder panel.

After this step, all dashboards should display real data. No empty panels.

---

### 4.2 Add Missing Business Metrics to Services

**Principle**: Add shared metric helpers to `common/telemetry/` so each service only calls a function rather than duplicating instrument setup code.

**New file**: `common/telemetry/business_metrics.go`

```go
package telemetry

import (
    "context"
    "go.opentelemetry.io/otel/metric"
    "go.opentelemetry.io/otel/attribute"
)

var (
    activeSessions  metric.Int64UpDownCounter
    recursionsTotal metric.Int64Counter
    messagesTotal   metric.Int64Counter
    dlqDepth        metric.Int64UpDownCounter
)

func init() {
    m := Meter("rag-business")
    activeSessions, _ = m.Int64UpDownCounter("rag_active_sessions",
        metric.WithDescription("Number of sessions currently streaming"))
    recursionsTotal, _ = m.Int64Counter("rag_recursions_total",
        metric.WithDescription("Total pipeline re-plan cycles triggered"))
    messagesTotal, _ = m.Int64Counter("rag_messages_total",
        metric.WithDescription("Total messages processed by the pipeline"))
    dlqDepth, _ = m.Int64UpDownCounter("rag_dlq_depth",
        metric.WithDescription("Estimated depth of the dead letter queue"))
}

func RecordSessionStart(ctx context.Context) {
    activeSessions.Add(ctx, 1)
}

func RecordSessionEnd(ctx context.Context) {
    activeSessions.Add(ctx, -1)
}

func RecordRecursion(ctx context.Context, service string) {
    recursionsTotal.Add(ctx, 1, metric.WithAttributes(attribute.String("service", service)))
}

func RecordMessage(ctx context.Context, service string) {
    messagesTotal.Add(ctx, 1, metric.WithAttributes(attribute.String("service", service)))
}
```

**Per-service wiring** (one line each):

- `llm-gateway`: Call `telemetry.RecordSessionStart(ctx)` when a WebSocket connection opens, `RecordSessionEnd(ctx)` in the deferred close.
- `rag-worker`: Call `telemetry.RecordRecursion(ctx, "rag-worker")` at the top of every re-plan loop iteration. Call `telemetry.RecordMessage(ctx, "rag-worker")` on each message consumed.
- `db-adapter`: Call `telemetry.RecordMessage(ctx, "db-adapter")` in `HandlePrompt` and `HandleResponse`.

Now re-enable the previously-removed dashboard panels for `rag_active_sessions`, `rag_recursions_total`, `rag_messages_total`.

---

### 4.3 Add ServiceMonitor Resources for RAG Services

**Problem**: Alloy scrapes infrastructure (Pulsar, DCGM, system) but does not discover RAG service pods. Services push metrics via OTLP, but there is no pull-based scrape of any `/metrics` endpoint.

**Note**: Go services using the OpenTelemetry SDK push via gRPC to the OTel collector. They do not expose a Prometheus `/metrics` endpoint by default. Two options:

**Option A (Recommended)**: Add the Prometheus exporter to `common/telemetry/otel.go` as an additional reader alongside the existing gRPC reader:

```go
import "go.opentelemetry.io/otel/exporters/prometheus"

promExporter, err := prometheus.New()
// Add to MeterProvider alongside the existing PeriodicReader:
mp := sdkmetric.NewMeterProvider(
    sdkmetric.WithResource(res),
    sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExp)),  // existing OTLP push
    sdkmetric.WithReader(promExporter),                            // add: Prometheus pull
)
```

Register the Prometheus HTTP handler on the existing health server:

```go
// In health.go, add:
mux.Handle("/metrics", promhttp.Handler())
```

This single change in `common/` adds `/metrics` to every service simultaneously.

**Option B**: Continue relying on OTLP push only, but create `ServiceMonitor` resources that configure Prometheus to scrape the OTel collector's `/metrics` endpoint rather than individual services. This is less granular but requires no code changes.

**After Option A**, create a single batched `ServiceMonitor` manifest:

```yaml
# infrastructure/APM/prometheus/rag-service-monitors.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rag-services
  namespace: rag-system
  labels:
    prometheus: otlp
    role: alert-rules
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: rag-stack  # add this label to all service Services
  endpoints:
    - port: health          # name the health port in each Service manifest
      path: /metrics
      interval: 30s
```

Apply the label `app.kubernetes.io/part-of: rag-stack` to all service Kubernetes `Service` objects in their respective `service.yaml` manifests.

---

### 4.4 Add DLQ Depth Gauge

After completing Step 1.3 (DLQ metrics in common), the `rag_dlq_depth` metric from Step 4.2 remains an estimate based on routing events. For a true depth measurement, poll the Pulsar admin API:

Add a background goroutine to `common/dlq/dlq.go` `Handler` that polls the Pulsar admin API every 30 seconds:

```go
// POST to http://pulsar-broker:8080/admin/v2/persistent/rag-pipeline/dlq/<service>/stats
// Extract msgBacklog from the JSON response.
// Record as dlqDepth gauge.
```

This requires the Pulsar admin URL to be passed into `dlq.NewHandler()`. Add it as an optional config field — if empty, skip the polling goroutine. Services set it via `PULSAR_ADMIN_URL` env var.

---

### 4.5 Increase Trace Sampling to 100%

**File**: `infrastructure/APM/otel-collector/otel-collector.yaml`

Find the `processors:` section. Change:

```yaml
probabilistic_sampler:
  sampling_percentage: 15
```

to:

```yaml
probabilistic_sampler:
  sampling_percentage: 100
```

At current traffic volumes (personal project, low concurrency), 100% sampling provides full observability with negligible storage cost. Revisit when sustained RPS exceeds 50.

---

### 4.6 Increase Tempo Trace Retention

**File**: `infrastructure/APM/tempo/values.yaml.template`

Find the retention configuration. Change from 24h to 168h (7 days):

```yaml
storage:
  trace:
    backend: s3
    block:
      retention: 168h
```

7 days covers weekend incidents discovered on Monday and is well within practical S3 storage limits for a personal project with low traffic.

---

### 4.7 Enable Log-Trace Correlation in Alloy

**File**: `infrastructure/APM/alloy/values.yaml`

In the Kubernetes pod log scraping section, add a `stage.json` or `stage.regex` pipeline stage to extract `trace=` and `span=` values from structured log lines and promote them to Loki labels:

```yaml
stage.regex {
  expression = ".*trace=(?P<trace_id>[a-f0-9]{32}).*span=(?P<span_id>[a-f0-9]{16}).*"
}
stage.labels {
  values = {
    trace_id = "trace_id",
    span_id  = "span_id",
  }
}
```

This only works after Step 1.6 (structured logging with trace ID) has been deployed. The regex matches the `trace=<id> span=<id>` format defined in the common logger. Once labels are indexed in Loki, Grafana Tempo can automatically link from a trace span to the corresponding Loki log lines using the `Derived Field` datasource configuration.

Configure the derived field in Grafana:
- Datasource: Loki
- Field name: `trace_id`
- Regex: `trace=(\w+)`
- URL: `${__value.raw}` with the Tempo datasource

---

## 5. Priority Backlog

Ordered by impact-to-effort ratio. Do not begin a line item if the services it touches are in the middle of a refactor from Sections 1–4.

---

### P1 — Pagination for All List Endpoints

**Services**: `db-adapter`, `qdrant-adapter`, `memory-controller`
**Flutter**: `chat_page`, `s3_page`, `timescale_page`

Every list endpoint (`/sessions`, `/tags`, `/items`, `/files`) currently returns all records. Add `?limit=50&offset=0` query parameters to all endpoints. Return a `{ "data": [...], "total": N, "offset": N, "limit": N }` envelope. Update Flutter pages to use infinite scroll or page controls. This is blocking for production use with any meaningful data volume.

---

### P2 — Input Validation Middleware

**Service**: All HTTP-serving services
**Common file to create**: `common/middleware/validate.go`

Create a request size limiter applied at the HTTP level:

```go
func MaxBodySize(limit int64) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            r.Body = http.MaxBytesReader(w, r.Body, limit)
            next.ServeHTTP(w, r)
        })
    }
}
```

Apply `MaxBodySize(1 << 20)` (1MB) to all write endpoints. Add explicit JSON validation for fields with known types (session name max 255 chars, tag name max 100 chars, prompt max 32KB). Do this in `common/` once, wire with one line per service.

---

### P3 — Circuit Breakers for Downstream Dependencies

**Services**: `rag-worker`, `llm-gateway`, `db-adapter`
**Common file to create**: `common/circuit/breaker.go`

Add a simple state-machine circuit breaker for Ollama calls (the most likely slow dependency). When Ollama returns 5 consecutive errors or timeouts, open the circuit for 30 seconds and return a fast failure to the pipeline rather than accumulating blocked goroutines. Use the `go-breaker` or `gobreaker` library, or implement a minimal state machine in `common/circuit/`.

Apply to: Ollama HTTP calls in `rag-worker`, TimescaleDB connection pool in `db-adapter`.

---

### P4 — Rollback Support in build.sh

**File**: `rag-stack/build.sh`

The build journal already tracks versions. Add a `--rollback <service> <version>` mode that:
1. Skips the build phase
2. Looks up the deployment manifest for `<service>`
3. Substitutes `__VERSION__` with the specified rollback version
4. Applies the manifest with `kubectl apply`

This requires the old image to still exist in the registry (it does — pruning is manual). Document the registry prune policy to keep at least the last 3 versions of each service.

---

### P5 — setup-all.sh Version Default Fix

**File**: `rag-stack/setup-all.sh`

Find and fix the hardcoded `VERSION=2.4.11` default. Change it to read from `CURRENT_VERSION`:

```bash
DEFAULT_VERSION=$(python3 -c "
import json
with open('$(pwd)/CURRENT_VERSION') as f:
    data = json.load(f)
versions = [v['version'] for v in data.values()]
print(max(versions, key=lambda v: tuple(int(x) for x in v.split('.'))))
")
VERSION=${VERSION:-$DEFAULT_VERSION}
```

This derives the default from the highest version currently tracked in `CURRENT_VERSION`, so it stays correct without manual updates.

---

### P6 — Pre-flight Validation in setup-all.sh

**File**: `rag-stack/setup-all.sh`

Add a `preflight_check()` function at the top that validates before any installation begins:

```bash
preflight_check() {
    echo "Running pre-flight checks..."

    # cert-manager CRD exists
    kubectl get crd certificates.cert-manager.io &>/dev/null || \
        { echo "ERROR: cert-manager not installed"; exit 1; }

    # Storage class exists
    kubectl get storageclass rook-ceph-block &>/dev/null || \
        { echo "ERROR: rook-ceph-block storage class not found"; exit 1; }

    # Registry reachable
    curl -sk "https://${REGISTRY}/v2/" &>/dev/null || \
        { echo "ERROR: Registry ${REGISTRY} not reachable"; exit 1; }

    # Required node labels exist
    kubectl get nodes -l role=storage-node --no-headers | grep -q . || \
        { echo "ERROR: No nodes with label role=storage-node"; exit 1; }

    echo "Pre-flight checks passed."
}
```

Call `preflight_check` as the first thing in `main()`. Exit 1 on any failure.

---

### P7 — Fix object-store-mgr Path Handling

**File**: `rag-stack/services/object-store-mgr/`

Replace the naive URL path split with proper URL parsing:

```go
u, err := url.ParseRequestURI(r.URL.Path)
if err != nil {
    http.Error(w, "invalid path", 400)
    return
}
// Validate: path must start with /api/s3/ and contain no ".." segments
parts := strings.Split(strings.TrimPrefix(u.Path, "/api/s3/"), "/")
for _, p := range parts {
    if p == ".." || p == "." {
        http.Error(w, "invalid path", 400)
        return
    }
}
```

This prevents path traversal in the S3 proxy.

---

### P8 — Generate and Publish OpenAPI Spec for rag-admin-api

**Tool**: `swaggo/swag` or `go-swagger`

Add swagger annotations to all handler functions in `rag-admin-api/internal/handlers/`. Generate the spec as part of the build process. Serve the spec at `/api/docs/swagger.json` and a Swagger UI at `/api/docs/`. This is the single highest-leverage documentation change — it benefits every consumer of the API (Flutter UI, test scripts, external tools).

---

### P9 — Move build-orchestrator Embedded HTML to Static File

**File**: `rag-stack/services/build-orchestrator/cmd/orchestrator/main.go`

Extract the HTML string (lines ~879–987) into `build-orchestrator/internal/static/dashboard.html`. Serve it with `http.FileServer`:

```go
//go:embed ../../internal/static
var staticFiles embed.FS
mux.Handle("/", http.FileServer(http.FS(staticFiles)))
```

Use `//go:embed` so it remains a single binary with no runtime file dependency. The `main.go` file loses ~100 lines of embedded HTML.

---

### P10 — Add Exponential Backoff to DLQ Retries

**File**: `common/dlq/dlq.go`

Currently, transient failures NACK immediately, which causes a rapid retry storm when a dependency is down. Add configurable delay between retries using exponential backoff:

```go
// Before NACK, check retry count from message properties
retryCount := getRetryCount(msg)
delay := time.Duration(math.Pow(2, float64(retryCount))) * time.Second
if delay > 60*time.Second { delay = 60*time.Second }
// Use NegativeAcknowledgement with a delay
consumer.ReconsumeLater(msg, delay)
```

Pulsar supports `ReconsumeLater` natively. This replaces the immediate NACK and prevents thundering-herd retries when a database or external service is temporarily unavailable.

---

### P11 — Add Loki Log Streaming to Observability Page

**Flutter file**: `lib/features/observability/observability_page.dart`
**Backend file**: `rag-stack/services/rag-admin-api/` — add proxy route for Loki query

Add a Loki LogQL query endpoint to `rag-admin-api`:

```
GET /api/logs/session/{trace_id}
```

This proxies to Loki: `GET /loki/api/v1/query_range?query={trace_id="<id>"}&start=...&end=...`

In the Flutter observability page, add a log viewer panel that queries this endpoint when a trace ID is selected. This closes the "what happened during this session" workflow.

---

### P12 — HA Configuration for Qdrant

**File**: `rag-stack/infrastructure/qdrant/qdrant-deploy.yaml`

Change replicas from 1 to 3 and switch from `Recreate` to `RollingUpdate` strategy. This requires Qdrant's distributed mode, which needs:
- A headless service for peer discovery
- `QDRANT__CLUSTER__ENABLED=true` env var
- Storage per-replica (StatefulSet instead of Deployment)

Convert the Qdrant Deployment to a StatefulSet with a `volumeClaimTemplate`. Each replica gets its own PVC. The headless service handles peer-to-peer cluster communication.

This is the most operationally impactful resilience change — Qdrant deployment downtime currently causes complete pipeline failure.

---

### P13 — TimescaleDB Backup Automation

**File**: `rag-stack/infrastructure/timescaledb/`

CloudNativePG supports automated backups via the `Backup` and `ScheduledBackup` CRDs. Create:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: timescaledb-daily
  namespace: timescaledb
spec:
  schedule: "0 2 * * *"    # 2am daily
  backupOwnerReference: self
  cluster:
    name: timescaledb
```

Configure the backup destination to the existing Rook-Ceph S3 store. Retain 7 daily backups. Document the restore procedure in `OPERATIONS.md`.

---

### P14 — Secrets Rotation Documentation and Tooling

Create `scripts/rotate-secrets.sh`:

```bash
# Rotates TimescaleDB app user password
# 1. Generate new password
# 2. Update CNPG secret
# 3. Rolling restart db-adapter, rag-worker, memory-controller
# 4. Verify connectivity
```

Document in `OPERATIONS.md §4.x` with the exact steps. The rotation itself is a manual procedure at this scale, but the script and documentation prevent a panic during an incident.

---

## 6. Alerting Rules

**Prerequisite**: All of Sections 1–4 must be complete before defining alerts. Writing alert rules against metrics that do not yet exist or are named incorrectly just creates false-negative silence.

**File to create**: `infrastructure/APM/prometheus/rag-alert-rules.yaml`

Define a `PrometheusRule` resource. Apply the label `prometheus: otlp` and `role: alert-rules` to match the existing `RuleSelector`.

Define the following alert groups in this order:

**Group 1 — Service Availability** (highest priority):
- Alert when any service pod has been in `CrashLoopBackOff` or `OOMKilled` for more than 2 minutes
- Alert when `/readyz` returns non-200 for more than 60 seconds

**Group 2 — Pipeline Health**:
- Alert when `dlq_routed_total` rate exceeds 5/minute for any service (sustained DLQ routing indicates a systematic failure)
- Alert when `worker_errors_total` rate exceeds 10/minute

**Group 3 — Latency SLOs**:
- Alert when P95 of `worker_task_duration_ms` exceeds 30,000ms (30 seconds) over a 5-minute window
- Alert when P95 of `gateway_request_duration_ms` exceeds 5,000ms over a 5-minute window

**Group 4 — Infrastructure**:
- Alert when GPU memory utilization (`DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_FREE`) exceeds 95% for more than 5 minutes
- Alert when Pulsar consumer lag exceeds 10,000 messages for any subscription
- Alert when TimescaleDB connection count approaches the configured `max_connections`

**Group 5 — DLQ Depth**:
- Alert when `rag_dlq_depth` for any service exceeds 100 messages

**Alertmanager routing**: Replace the placeholder `http://example.com/` webhook with a real destination. Options: a Slack webhook URL (add `SLACK_WEBHOOK_URL` to a Kubernetes secret and reference it in the AlertmanagerConfig), a PagerDuty integration, or a simple email receiver. Configure in `infrastructure/APM/prometheus/alertmanagerconfig.values.yaml`.

Only define severity `warning` alerts to start. Add `critical` severity and paging only after the warning alerts have been running for one week and confirmed to be signal rather than noise.

---

## Summary: Change Execution Sequence

```
Week 1: Section 1 (all 6 steps — common changes first, one service sweep)
Week 1: Section 2.1–2.7 (Flutter refactor, parallel with backend work)
Week 2: Section 3.1 (Qdrant HTTP), Section 4.1 (dashboard fixes)
Week 2: Section 2.8–2.10 (Flutter feature completions)
Week 3: Section 3.2 (aggregator polling), Section 4.2–4.4 (metrics)
Week 3: P1–P5 from backlog
Week 4: Section 3.3 Phase A (stage interface), Section 4.5–4.7 (observability)
Week 4: P6–P10 from backlog
Month 2: Section 3.3 Phase B (exec split), P11–P14
Month 2+: Section 6 (alerting, after metrics are stable)
```

Each week's work should be merged to main before the next week begins. Version bump the build on every functional change.
