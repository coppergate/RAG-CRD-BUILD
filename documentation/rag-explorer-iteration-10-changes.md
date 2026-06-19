# RAG Explorer — Changes Required for Iteration 10 / Embedding Scale-Out

**Date:** 2026-06-19
**Author:** Analysis session — work-2026-06-19
**Status:** Design document — not yet implemented

---

## 1. Overview

The pipeline has undergone two significant changes since the rag-explorer was last updated:

1. **Iteration 10a reliability pass** — rag-worker now has distinct Planner, Executor, and
   Embedding roles, each with its own Ollama endpoint and model identity. The cluster default
   models changed from `llama3.1:latest` to `granite3.1-dense:8b` (planner) and `qwen2.5:32b`
   (executor). An alt-planner CPU model (`llama3.2:3b`) is now available as a lightweight fallback.

2. **Embedding Scale-Out (embed-gateway / Pulsar fan-out)** — A new `embed-gateway` service
   distributes embedding calls across worker-node Ollama pods via a Pulsar fan-out pattern.
   Two embedding models are now available: `all-minilm:l6-v2` (384 dims) and
   `nomic-embed-text` (768 dims). Qdrant collections are named per model and vector size
   (e.g., `vectors-all-minilm-l6-v2-384`). Both the chat and ingestion APIs accept an
   optional `embedding_model` override.

The rag-explorer currently sends neither `embedding_model` nor `vector_size` in any request
and has hard-coded model defaults that no longer match what the cluster is running. This document
describes all changes required to bring the UI into alignment.

---

## 2. Current State vs. Required State

### 2.1 Chat WebSocket Request

**Current payload sent by `chat_service.dart`:**
```json
{
  "prompt":        "...",
  "session_id":    123,
  "session_name":  "my session",
  "planner":       "llama3.1:latest",
  "executor":      "llama3.1:latest",
  "tags":          [1, 2]
}
```

**Required payload:**
```json
{
  "prompt":           "...",
  "session_id":       123,
  "session_name":     "my session",
  "planner":          "granite3.1-dense:8b",
  "executor":         "qwen2.5:32b",
  "embedding_model":  "all-minilm:l6-v2",
  "tags":             [1, 2]
}
```

Changes:
- `planner` default must change from `llama3.1:latest` → `granite3.1-dense:8b`
- `executor` default must change from `llama3.1:latest` → `qwen2.5:32b`
- `embedding_model` field must be added to every chat request
- `vector_size` is resolved server-side from the model name — no need to send it

### 2.2 Ingestion Trigger Request

**Current payload sent by `ingestion_service.dart` → `triggerIngest()`:**
```json
{
  "bucket_name":    "my-bucket",
  "prefix":         "",
  "tag_ids":        [1],
  "force_reingest": false
}
```

**Required payload:**
```json
{
  "bucket_name":     "my-bucket",
  "prefix":          "",
  "tag_ids":         [1],
  "force_reingest":  false,
  "embedding_model": "all-minilm:l6-v2"
}
```

Changes:
- `embedding_model` field must be added so ingested vectors land in the collection that matches
  the embedding model in use for chat. If omitted the backend uses its configured default, but
  explicit selection prevents collection mismatches when the UI and backend defaults drift.

---

## 3. Required Changes — Detailed

### 3.1 Model Defaults in `chat_notifier.dart`

**File:** `lib/features/chat/chat_notifier.dart`

**Current `ChatState` defaults (lines 24–25):**
```dart
@Default('llama3.1:latest') String selectedPlanner,
@Default('llama3.1:latest') String selectedExecutor,
```

**Required:**
```dart
@Default('granite3.1-dense:8b') String selectedPlanner,
@Default('qwen2.5:32b')         String selectedExecutor,
@Default('all-minilm:l6-v2')    String selectedEmbeddingModel,
```

`selectedEmbeddingModel` is a new state field. It must be added to `ChatState`, wired through
`ChatNotifier`, and passed to `ChatInputBar` alongside planner and executor.

### 3.2 Embedding Model Field in `ChatState`

Add `selectedEmbeddingModel` to the `@freezed` class:

```dart
@Default('all-minilm:l6-v2') String selectedEmbeddingModel,
```

Add the corresponding setter in `ChatNotifier`:

```dart
void setEmbeddingModel(String model) {
  state = AsyncData(state.value!.copyWith(selectedEmbeddingModel: model));
}
```

### 3.3 `sendMessage()` — Include Embedding Model in Stream Request

**File:** `lib/features/chat/chat_notifier.dart`, `sendMessage()` method

**Current call to `chatService.streamChat()`:**
```dart
final stream = chatService.streamChat(
  prompt:      prompt,
  sessionId:   currentState.currentSessionId!,
  sessionName: currentState.currentSessionName,
  planner:     currentState.selectedPlanner,
  executor:    currentState.selectedExecutor,
  tags:        currentState.selectedTags.map((t) => t.id).toList(),
);
```

**Required:**
```dart
final stream = chatService.streamChat(
  prompt:          prompt,
  sessionId:       currentState.currentSessionId!,
  sessionName:     currentState.currentSessionName,
  planner:         currentState.selectedPlanner,
  executor:        currentState.selectedExecutor,
  embeddingModel:  currentState.selectedEmbeddingModel,
  tags:            currentState.selectedTags.map((t) => t.id).toList(),
);
```

Also record the embedding model in the assistant message initial metadata so it is
visible in the metadata panel before the response arrives:

```dart
final assistantMessage = ResponseMessage(
  content: '',
  role: 'assistant',
  timestamp: DateTime.now(),
  metadata: {
    'selected_tags':     currentState.selectedTags.map((t) => t.name).toList(),
    'selected_tag_ids':  currentState.selectedTags.map((t) => t.id).toList(),
    'planner_model':     currentState.selectedPlanner,
    'executor_model':    currentState.selectedExecutor,
    'embedding_model':   currentState.selectedEmbeddingModel,
    'source':            'chat-ui',
    'message_segments':  <Map<String, dynamic>>[],
  },
);
```

### 3.4 `streamChat()` Signature in `chat_service.dart`

**File:** `lib/core/services/chat_service.dart`

Add `embeddingModel` to the method signature and include it in the JSON payload:

```dart
Stream<ResponseMessage> streamChat({
  required String prompt,
  required int sessionId,
  String? sessionName,
  required String planner,
  required String executor,
  required String embeddingModel,       // NEW
  required List<int> tags,
}) {
  // ...
  final request = {
    'prompt':           prompt,
    'session_id':       sessionId,
    'session_name':     sessionName,
    'planner':          planner,
    'executor':         executor,
    'embedding_model':  embeddingModel, // NEW
    'tags':             tags,
  };
  // ...
}
```

### 3.5 Embedding Model Selector in `ChatInputBar`

**File:** `lib/features/chat/widgets/chat_input_bar.dart`

The `_buildConfigRow()` method currently renders three dropdowns: Planner, Executor, Memory.
Add a fourth: **Embedding Model**.

Add to the widget's constructor parameters:
```dart
final String embeddingModel;
final List<String> availableEmbeddingModels;
final Function(String) onEmbeddingModelChanged;
```

Add to `_buildConfigRow()`:
```dart
Widget _buildConfigRow(BuildContext context) {
  return Wrap(
    spacing: 16,
    runSpacing: 12,
    children: [
      _buildDropdown('Planner',   planner,        (val) => onPlannerChanged(val!),        items: availableModels),
      _buildDropdown('Executor',  executor,        (val) => onExecutorChanged(val!),       items: availableModels),
      _buildDropdown('Embedding', embeddingModel,  (val) => onEmbeddingModelChanged(val!), items: availableEmbeddingModels),
      _buildDropdown('Memory',    memoryMode,      (val) => onMemoryModeChanged(val!),     items: ['off', 'session', 'full']),
    ],
  );
}
```

The `availableEmbeddingModels` list should be a static constant (no dynamic discovery API
exists yet):
```dart
// lib/features/chat/chat_notifier.dart or a shared constants file
const kAvailableEmbeddingModels = ['all-minilm:l6-v2', 'nomic-embed-text'];
const kAvailableModels = [
  'granite3.1-dense:8b',
  'qwen2.5:32b',
  'llama3.2:3b',
  'llama3.1',
];
```

### 3.6 Wire Embedding Model Through `chat_page.dart`

**File:** `lib/features/chat/chat_page.dart`

Wherever `ChatInputBar` is instantiated, pass the new params:

```dart
ChatInputBar(
  // ... existing params ...
  embeddingModel:           chatState.selectedEmbeddingModel,
  availableEmbeddingModels: kAvailableEmbeddingModels,
  onEmbeddingModelChanged:  (val) => notifier.setEmbeddingModel(val),
)
```

### 3.7 Ingestion Page — Add Embedding Model to Trigger

**File:** `lib/features/ingestion/ingestion_page.dart` and
`lib/core/services/ingestion_service.dart`

Add an embedding model selector to the ingestion page (a simple dropdown before the
"Trigger Ingest" button). Wire it into the `triggerIngest()` call:

In `ingestion_service.dart`, update `triggerIngest()`:
```dart
Future<Map<String, dynamic>> triggerIngest({
  required String bucketName,
  required List<int> tagIds,
  String prefix = '',
  bool forceReingest = false,
  String embeddingModel = 'all-minilm:l6-v2',  // NEW
}) async {
  final response = await _dio.post(
    '${_config.ragAdminApiUrl}/api/ingest/ingest',
    data: {
      'bucket_name':    bucketName,
      'prefix':         prefix,
      'tag_ids':        tagIds,
      'force_reingest': forceReingest,
      'embedding_model': embeddingModel,        // NEW
    },
  );
  // ...
}
```

In the ingestion page UI, add an embedding model dropdown using `kAvailableEmbeddingModels`
(same constant as chat page). Persist the selection in the page's local state.

### 3.8 Metadata Panel — Display Embedding Model and Vector Info

**File:** `lib/features/chat/widgets/metadata_panel.dart`

The backend returns `embedding_model` and `vector_size` in the chunk metadata once the
search phase completes (Seq 0 metadata chunk). The metadata panel should surface these
explicitly rather than burying them in a raw JSON dump.

Add a "Pipeline Models" section to the panel that extracts and displays:

| Field | Source in metadata | Display label |
|---|---|---|
| `planner_model` | `metadata['planner_model']` | Planner |
| `executor_model` | `metadata['executor_model']` | Executor |
| `embedding_model` | `metadata['embedding_model']` | Embedding |
| `vector_size` | `metadata['vector_size']` | Vector dims |
| `gateway_id` | `metadata['gateway_id']` | Embed gateway |

These should be shown as a compact key-value grid above the existing metadata dump, so
they are immediately visible without scrolling.

Example extraction:
```dart
Widget _buildPipelineModelsSection(Map<String, dynamic>? metadata) {
  if (metadata == null) return const SizedBox.shrink();
  final fields = {
    'Planner':       metadata['planner_model'],
    'Executor':      metadata['executor_model'],
    'Embedding':     metadata['embedding_model'],
    'Vector dims':   metadata['vector_size']?.toString(),
    'Embed gateway': metadata['gateway_id'],
  }.entries.where((e) => e.value != null && e.value.toString().isNotEmpty);

  if (fields.isEmpty) return const SizedBox.shrink();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Pipeline Models', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      const SizedBox(height: 4),
      ...fields.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          SizedBox(width: 90, child: Text(e.key, style: const TextStyle(fontSize: 11, color: Colors.grey))),
          Expanded(child: Text(e.value.toString(), style: const TextStyle(fontSize: 11))),
        ]),
      )),
      const Divider(height: 16),
    ],
  );
}
```

---

## 4. Changes NOT Required

The following were considered but do not require rag-explorer changes:

- **Embed fanout (`EMBED_FANOUT_ENABLED`)** — This is a backend feature flag. The UI has no
  visibility or control over it. The gateway_id field in metadata (see §3.8) is sufficient
  for observability.
- **Alt planner model (`llama3.2:3b`)** — This is already handled by adding it to the
  `kAvailableModels` list (§3.5). No special treatment needed.
- **`vector_size` in chat request** — The backend resolves this from the model name. No need
  to send it explicitly.
- **Model shape ConfigMaps** — These are Kubernetes ConfigMaps consumed by the rag-worker.
  The UI is not involved.
- **Pulsar topic changes** — Internal infrastructure; not visible to the UI.

---

## 5. File Change Summary

| File | Type of Change |
|---|---|
| `lib/features/chat/chat_notifier.dart` | Add `selectedEmbeddingModel` to `ChatState`; fix model defaults; add `setEmbeddingModel()`; pass embedding model in `sendMessage()` |
| `lib/features/chat/chat_notifier.freezed.dart` | Regenerated — run `build_runner` |
| `lib/features/chat/chat_notifier.g.dart` | Regenerated — run `build_runner` |
| `lib/core/services/chat_service.dart` | Add `embeddingModel` param to `streamChat()` |
| `lib/features/chat/widgets/chat_input_bar.dart` | Add embedding model dropdown to config row |
| `lib/features/chat/chat_page.dart` | Wire embedding model params into `ChatInputBar` |
| `lib/core/services/ingestion_service.dart` | Add `embeddingModel` param to `triggerIngest()` |
| `lib/features/ingestion/ingestion_page.dart` | Add embedding model dropdown before trigger button |
| `lib/features/chat/widgets/metadata_panel.dart` | Add pipeline models section (planner, executor, embedding, vector dims, gateway) |
| New shared constants file (or inline in notifier) | `kAvailableModels`, `kAvailableEmbeddingModels` |

---

## 6. Implementation Order

Implement in this order to avoid breaking the UI in an intermediate state:

1. **Fix model defaults** (`chat_notifier.dart` ChatState defaults) — immediate correctness fix,
   no other dependencies. Run `build_runner` after to regenerate `.freezed.dart` / `.g.dart`.

2. **Add `selectedEmbeddingModel` to state** — add field, setter, and constants. Run `build_runner`.

3. **Update `streamChat()` signature** (`chat_service.dart`) — adds the new parameter with a
   default value so callers don't break before step 4.

4. **Wire embedding model through `sendMessage()` and `ChatInputBar`** — connects state to UI
   and to the WebSocket payload.

5. **Update ingestion trigger** — add embedding model to `triggerIngest()` and the ingestion
   page UI.

6. **Enhance metadata panel** — display pipeline model info from chunk metadata. This step is
   independent of the others and can be done last.

---

## 7. Regenerating Freezed/Riverpod Code

After any changes to `@freezed` classes or `@riverpod` notifiers, regenerate the code:

```bash
cd rag-stack/services/rag-explorer
flutter pub run build_runner build --delete-conflicting-outputs
```

Run this after steps 1 and 2 above before proceeding to wiring steps.

---

## 8. Testing Checklist

- [ ] Chat request WebSocket payload includes `embedding_model` (verify via browser DevTools WS inspector or rag-worker logs)
- [ ] Default planner shown in UI is `granite3.1-dense:8b`
- [ ] Default executor shown in UI is `qwen2.5:32b`
- [ ] Default embedding model shown in UI is `all-minilm:l6-v2`
- [ ] Switching embedding model to `nomic-embed-text` and sending a chat → rag-worker logs confirm `embedding_model=nomic-embed-text`
- [ ] Ingestion trigger with `nomic-embed-text` selected → ingestion service logs confirm correct model
- [ ] Metadata panel shows Planner / Executor / Embedding / Vector dims after a successful response
- [ ] `flutter analyze` passes with no new warnings
- [ ] `flutter pub run build_runner build` completes cleanly
