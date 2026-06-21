# RAG Explorer — Changes Required for Iteration 10 / Embedding Scale-Out

**Date:** 2026-06-19
**Author:** Analysis session — work-2026-06-19
**Status:** Design document — not yet implemented

---

## 1. Overview

The pipeline has undergone two significant changes since the rag-explorer was last updated:

1. **Iteration 10a reliability pass** — rag-worker now has distinct Planner, Executor, and
   Embedding roles, each with its own Ollama endpoint and model identity. The cluster default
   models changed from `llama3.1:latest` to `granite3.1-dense:8b` (planner) and `qwen3:32b`
   (executor). An alt-planner CPU model (`llama3.2:3b`) is now available as a lightweight fallback.

2. **Embedding Scale-Out (embed-gateway / Pulsar fan-out)** — A new `embed-gateway` service
   distributes embedding calls across worker-node Ollama pods via a Pulsar fan-out pattern.
   Three embedding models are now available: `all-minilm:l6-v2` (384 dims),
   `mxbai-embed-large` (1024 dims native; 512 via MRL truncation), and `nomic-embed-text`
   (768 dims). Qdrant collections are named per model and vector size
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
  "executor":         "qwen3:32b",
  "embedding_model":  "all-minilm:l6-v2",
  "tags":             [1, 2]
}
```

Changes:
- `planner` default must change from `llama3.1:latest` → `granite3.1-dense:8b`
- `executor` default must change from `llama3.1:latest` → `qwen3:32b`
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
@Default('qwen3:32b')           String selectedExecutor,
```

The `selectedEmbeddingModel` field does **not** belong in `ChatState` — see §3.2 for the
cross-page shared provider approach.

### 3.2 Shared Embedding Model Provider

The embedding model selection **must be shared** between the chat page and the ingestion page.
If a user ingests with `nomic-embed-text` (768-dim) but chats with `all-minilm` (384-dim),
the retrieval phase searches the wrong Qdrant collection and returns zero results.

**Do NOT** add `selectedEmbeddingModel` to `ChatState`. Create a top-level `StateProvider`
so both pages read and write the same value:

**New file:** `lib/core/providers/embedding_model_provider.dart`
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_config_provider.dart';

final embeddingModelProvider = StateProvider<String>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.availableEmbeddingModels.first;
});
```

The provider initializes from `AppConfig.availableEmbeddingModels.first` so the default
tracks configuration rather than being hardcoded. No setter is needed on `ChatNotifier` —
any widget that changes the selection writes directly to
`ref.read(embeddingModelProvider.notifier).state`.

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
final embeddingModel = ref.read(embeddingModelProvider);
final stream = chatService.streamChat(
  prompt:          prompt,
  sessionId:       currentState.currentSessionId!,
  sessionName:     currentState.currentSessionName,
  planner:         currentState.selectedPlanner,
  executor:        currentState.selectedExecutor,
  embeddingModel:  embeddingModel,
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
    'embedding_model':   embeddingModel,
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

`AppConfig` already drives the inference models list — `chat_page.dart` passes
`config.availableModels` to `ChatInputBar`. Embedding models follow the same pattern.

Add `availableEmbeddingModels` to `AppConfig` in `lib/config/app_config.dart`:
```dart
@Default(['all-minilm:l6-v2', 'mxbai-embed-large', 'nomic-embed-text']) List<String> availableEmbeddingModels,
```

Do **not** create `kAvailableEmbeddingModels` or `kAvailableModels` compile-time constants.
Both lists are configuration-driven to allow overriding without a rebuild.

### 3.6 Wire Embedding Model Through `chat_page.dart`

**File:** `lib/features/chat/chat_page.dart`

Wherever `ChatInputBar` is instantiated, pass the new params:

```dart
ChatInputBar(
  // ... existing params ...
  embeddingModel:           ref.watch(embeddingModelProvider),
  availableEmbeddingModels: config.availableEmbeddingModels,
  onEmbeddingModelChanged:  (val) => ref.read(embeddingModelProvider.notifier).state = val,
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

In the ingestion page UI, add an embedding model dropdown that reads from the shared
`embeddingModelProvider` — **not** local page state. This ensures the model selected in chat
is already applied when the user switches to ingestion, preventing collection mismatch.

```dart
// In _IngestionPageState.build() — convert to ConsumerWidget or use ref.watch:
final selectedEmbeddingModel = ref.watch(embeddingModelProvider);
final availableEmbeddingModels = ref.watch(appConfigProvider).availableEmbeddingModels;

// Dropdown widget:
DropdownButton<String>(
  value: selectedEmbeddingModel,
  onChanged: (val) => ref.read(embeddingModelProvider.notifier).state = val!,
  items: availableEmbeddingModels
      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
      .toList(),
)
```

In `_triggerIngestion()`, read the current value from the provider:
```dart
final embeddingModel = ref.read(embeddingModelProvider);
final result = await service.triggerIngest(
  bucketName:     _selectedBucket!,
  tagIds:         _selectedTags.map((t) => t.id).toList(),
  prefix:         _prefix,
  forceReingest:  _forceReingest,
  embeddingModel: embeddingModel,
);
```

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

### 3.9 Fix MetadataPanel Close Button

**File:** `lib/features/chat/chat_page.dart`

The `onClose` callback on `MetadataPanel` currently calls `selectMessage(null)`, which
deselects the highlighted message but leaves the panel open. The user sees "Select a message
to view its metadata." with no way to close it from within the panel.

**Current:**
```dart
onClose: () => ref.read(chatProvider.notifier).selectMessage(null),
```

**Required:**
```dart
onClose: () => ref.read(chatProvider.notifier).toggleMetadata(),
```

`toggleMetadata()` hides the panel. Deselecting the message is not needed — once hidden,
any previously selected index is irrelevant.

---

### 3.10 Batch Session Delete

**File:** `lib/features/chat/chat_notifier.dart` and `lib/features/chat/chat_page.dart`

`_deleteSelected()` in `chat_page.dart` loops serially, awaiting each individual
`deleteSession()` call. Each `deleteSession()` call internally triggers `loadSessions()`.
Selecting 10 sessions causes 10 sequential deletes and 10 session list reloads.

Add a `deleteSessions(Set<int> ids)` method to `ChatNotifier` that parallelizes the
API calls and reloads the session list exactly once:

```dart
// lib/features/chat/chat_notifier.dart
Future<void> deleteSessions(Set<int> ids) async {
  if (ids.isEmpty) return;
  final chatService = ref.read(chatServiceProvider);
  await Future.wait(ids.map((id) => chatService.deleteSession(id)));
  final currentState = state.value!;
  var newState = currentState.copyWith(
    selectedSessionIds: currentState.selectedSessionIds.difference(ids),
  );
  if (ids.contains(currentState.currentSessionId)) {
    newState = newState.copyWith(
      currentSessionId:   null,
      currentSessionName: null,
      messages:           [],
    );
  }
  state = AsyncData(newState);
  await loadSessions();
}
```

Replace `_deleteSelected()` in `chat_page.dart`:

```dart
// BEFORE
void _deleteSelected(Set<int> ids) async {
  for (final id in ids) {
    await ref.read(chatProvider.notifier).deleteSession(id);
  }
}

// AFTER
void _deleteSelected(Set<int> ids) {
  ref.read(chatProvider.notifier).deleteSessions(ids);
}
```

The existing "Delete Selected (N)" confirmation dialog requires no changes.

---

## 3.11 Required: embed-gateway Prompt Template Support

**Validated findings (2026-06-21):**

Ollama does **not** apply task prefixes automatically for any embedding model. The caller
must prepend them. All three models in this stack have been verified:

### Model Prefix Requirements

| Model | Dims | Document prefix | Query prefix | Prefix required? |
|---|---|---|---|---|
| `all-minilm:l6-v2` | 384 | *(none)* | *(none)* | No — symmetric model |
| `mxbai-embed-large` | 1024 | *(none)* | `"Represent this sentence for searching relevant passages: "` | **Yes** — per model card |
| `nomic-embed-text` | 768 | `"search_document: "` | `"search_query: "` | **Mandatory** — model card states prefixes *"must"* be included |

**nomic-embed-text note:** The nomic model card explicitly states: *"the text prompt must
include a task instruction prefix, instructing the model which task is being performed."*
Without prefixes the model produces degraded, off-task embeddings. If the current cluster
nomic vectors were ingested without `search_document:` prefixes, those collections should
be considered suboptimal and scheduled for re-ingestion once the embed-gateway fix is
deployed.

**nomic additional prefixes** (for future use — not needed for RAG):
- `"clustering: "` — for grouping/deduplication tasks
- `"classification: "` — for classification feature vectors

**mxbai-embed-large note:** Native output is **1024 dims** (confirmed). The cluster Qdrant
collection will be `vectors-mxbai-embed-large-1024`. A historical Ollama BOS token bug
([ollama/ollama#4207](https://github.com/ollama/ollama/issues/4207)) that caused
inconsistent mxbai embeddings is resolved in current Ollama versions — verify the cluster
is up to date before using this model.

### Required embed-gateway Changes

1. Add a `mode` field (`"document"` | `"query"`) to the Pulsar embedding request contract.
   rag-ingestion always sends `mode: "document"`; rag-worker always sends `mode: "query"`.

2. Add a `prompt_templates` section to the embed-gateway ConfigMap:

```yaml
prompt_templates:
  all-minilm:l6-v2:
    document: ""
    query:    ""
  mxbai-embed-large:
    document: ""
    query:    "Represent this sentence for searching relevant passages: "
  nomic-embed-text:
    document: "search_document: "
    query:    "search_query: "
```

3. In the embed-gateway handler, look up the template for the requested model and prepend
   the appropriate prefix before calling Ollama's `/api/embed` endpoint.

### Gates

- Do not use `mxbai-embed-large` until embed-gateway changes are deployed.
- Do not rely on existing `nomic-embed-text` Qdrant collections for production retrieval
  quality until re-ingested with the `search_document:` prefix applied.
- `all-minilm:l6-v2` is unaffected — no changes required for this model.

---

## 4. Changes NOT Required

The following were considered but do not require rag-explorer changes:

- **Embed fanout (`EMBED_FANOUT_ENABLED`)** — This is a backend feature flag. The UI has no
  visibility or control over it. The gateway_id field in metadata (see §3.8) is sufficient
  for observability.
- **Alt planner model (`llama3.2:3b`)** — Already present in `AppConfig.availableModels`
  (§3.5). No special treatment needed.
- **`vector_size` in chat request** — The backend resolves this from the model name. No need
  to send it explicitly.
- **Model shape ConfigMaps** — These are Kubernetes ConfigMaps consumed by the rag-worker.
  The UI is not involved.
- **Pulsar topic changes** — Internal infrastructure; not visible to the UI.

---

## 5. File Change Summary

| File | Type of Change |
|---|---|
| `lib/config/app_config.dart` | Add `availableEmbeddingModels` list |
| `lib/config/app_config.freezed.dart` | Regenerated — run `build_runner` |
| `lib/config/app_config.g.dart` | Regenerated — run `build_runner` |
| `lib/core/providers/embedding_model_provider.dart` | **New file** — shared `StateProvider<String>` for cross-page embedding model selection |
| `lib/features/chat/chat_notifier.dart` | Fix model defaults; add `deleteSessions()`; read embedding model from shared provider in `sendMessage()` |
| `lib/features/chat/chat_notifier.freezed.dart` | Regenerated — run `build_runner` |
| `lib/features/chat/chat_notifier.g.dart` | Regenerated — run `build_runner` |
| `lib/core/services/chat_service.dart` | Add `embeddingModel` param to `streamChat()` |
| `lib/features/chat/widgets/chat_input_bar.dart` | Add embedding model dropdown to config row |
| `lib/features/chat/chat_page.dart` | Wire embedding model params into `ChatInputBar`; fix `onClose` → `toggleMetadata()`; replace serial `_deleteSelected()` with batch call |
| `lib/core/services/ingestion_service.dart` | Add `embeddingModel` param to `triggerIngest()` |
| `lib/features/ingestion/ingestion_page.dart` | Add embedding model dropdown driven by shared provider |
| `lib/features/chat/widgets/metadata_panel.dart` | Add pipeline models section (planner, executor, embedding, vector dims, gateway) |

---

## 6. Implementation Order

Implement in this order to avoid breaking the UI in an intermediate state:

1. **Add `availableEmbeddingModels` to `AppConfig`** — foundation for all embedding model
   lists. Run `build_runner` to regenerate `app_config.freezed.dart` / `.g.dart`.

2. **Create `embeddingModelProvider`** (`lib/core/providers/embedding_model_provider.dart`) —
   shared state before any page wires to it.

3. **Fix model defaults** (`chat_notifier.dart` ChatState) — immediate correctness fix,
   no other dependencies. Run `build_runner` after.

4. **Update `streamChat()` signature** (`chat_service.dart`) — adds the new parameter with a
   default value so callers don't break before step 5.

5. **Wire embedding model through `sendMessage()` and `ChatInputBar`** — connects the shared
   provider to the UI and the WebSocket payload.

6. **Fix MetadataPanel close button** (`chat_page.dart`) — single-line change, independent.

7. **Replace serial `_deleteSelected()` with batch `deleteSessions()`** — add method to
   `ChatNotifier`, update `chat_page.dart`. Run `build_runner`.

8. **Update ingestion trigger** — add embedding model to `triggerIngest()` and the ingestion
   page UI; wire to shared provider.

9. **Enhance metadata panel** — display pipeline model info from chunk metadata. Independent
   of the others and can be done last.

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

**Model defaults**
- [ ] Default planner shown in UI is `granite3.1-dense:8b`
- [ ] Default executor shown in UI is `qwen3:32b`
- [ ] Default embedding model shown in UI is `all-minilm:l6-v2` (driven by `AppConfig.availableEmbeddingModels.first`)

**Embedding model wiring**
- [ ] Chat WebSocket payload includes `embedding_model` (verify via browser DevTools WS inspector or rag-worker logs)
- [ ] Switching embedding model to `nomic-embed-text` and sending a chat → rag-worker logs confirm `embedding_model=nomic-embed-text`
- [ ] Ingestion trigger with `nomic-embed-text` selected → ingestion service logs confirm correct model

**Cross-page consistency**
- [ ] Changing embedding model in chat page → ingestion page dropdown reflects the same value immediately
- [ ] Changing embedding model in ingestion page → chat page config row reflects the same value immediately

**Metadata panel**
- [ ] Metadata panel shows Planner / Executor / Embedding / Vector dims after a successful response
- [ ] Metadata panel close button (×) hides the panel entirely

**Batch delete**
- [ ] Selecting 3+ sessions and deleting them triggers a single session list reload (verify via network tab — one GET /sessions after the deletes)

**Code quality**
- [ ] `flutter analyze` passes with no new warnings
- [ ] `flutter pub run build_runner build` completes cleanly
