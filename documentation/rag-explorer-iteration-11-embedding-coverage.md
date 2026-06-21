# RAG Stack — Iteration 11: Embedding Coverage Tracking

**Date:** 2026-06-21
**Author:** Analysis session — work-2026-06-21
**Status:** Design document — not yet implemented
**Depends on:** Iteration 10 (embedding model UI, `tag_embedding_coverage` flow assumes
`embeddingModelProvider` and the `embedding_model` field in chat/ingest requests are in place)

---

## 1. Overview

When a user switches to a higher-dimensional embedding model (e.g. `nomic-embed-text`)
and sends a chat, the rag-worker currently has no way to know whether that model's Qdrant
collection contains vectors for the selected tags. If it does not, the retrieval phase
returns zero results silently.

Three embedding models are available: `all-minilm:l6-v2` (384 dims),
`mxbai-embed-large` (1024 dims native; 512 via MRL truncation — see §3.11 of
`rag-explorer-iteration-10-changes.md`), and `nomic-embed-text` (768 dims). Each model
writes to its own Qdrant collection named by model and dimension
(e.g., `vectors-mxbai-embed-large-1024`). The default is `all-minilm:l6-v2`; the others
are selectable on demand.

> **Pre-requisite investigation:** `mxbai-embed-large` and `nomic-embed-text` use
> asymmetric prompting (different prefixes for document embedding vs query embedding).
> Before enabling `mxbai-embed-large` for production use, the embed-gateway must be
> verified to apply the correct prefix per mode. See §3.11 of
> `rag-explorer-iteration-10-changes.md` for the full investigation spec and required
> ConfigMap changes. The coverage tracking in this document is model-agnostic and is
> not blocked by this investigation.

This iteration adds a **coverage tracking layer** so the pipeline can:

1. Know at query time which tags have been embedded with which model.
2. Trigger on-demand ingestion for missing or stale coverage without blocking the response.
3. Surface a clear advisory message in the chat UI indicating which tags are incomplete and
   why the response may be degraded.
4. Let the user navigate directly to the ingestion page with the missing model and tags
   pre-populated.

---

## 2. New Concepts

### 2.1 Coverage Status Values

| Status | Meaning | User-visible message |
|---|---|---|
| `pending` | Tag exists but has never been embedded with this model | "No embeddings available — results for this tag will be missing until ingestion completes." |
| `building` | Ingestion job is currently running for this tag + model | "Embeddings are being generated. Results for this tag may be incomplete." |
| `complete` | All known S3 files for this tag have been embedded | *(no advisory shown)* |
| `stale` | New files have been added to S3 for this tag since the last embedding run; existing vectors are usable but incomplete | "Results may be missing recently added files. Re-ingestion recommended." |

`stale` differs from `pending`: the model has usable vectors and the rag-worker will get
*some* context. `pending` means the collection has nothing at all for this tag.

### 2.2 Coverage Check Flow

```
User: tags=[k8s-docs, go-services], model=nomic-embed-text → Send

rag-worker:
  1. POST /api/db/embeddings/coverage
        {tag_ids: [1, 2], embedding_model: "nomic-embed-text"}
     ← [{tag_id:1, tag:"k8s-docs",    status:"complete"},
        {tag_id:2, tag:"go-services",  status:"pending"}]

  2. Search Qdrant vectors-nomic-embed-text-768 for k8s-docs only

  3. For go-services (pending):
     POST /api/ingest/ingest (via rag-admin-api, async / fire-and-forget)
       {bucket_name: ..., tag_ids: [2],
        embedding_model: "nomic-embed-text", force_reingest: false}
     → rag-ingestion sets coverage status → building

  4. Generate response using available context (k8s-docs only)

  5. Return response metadata:
       missing_embeddings: [
         {tag_id: 2, tag: "go-services", model: "nomic-embed-text", status: "pending"}
       ]
```

```
UI:
  Renders advisory banner in chat:
  "⚠ go-services has no nomic-embed-text embeddings yet.
   Ingestion has been triggered — results for this tag will improve once complete.
   [Go to Ingestion →]"

  "⚠ k8s-docs embeddings are stale (new files added since last run).
   Results may be missing recent content.   [Go to Ingestion →]"

  Deep-link carries: /ingestion?model=nomic-embed-text&tags=go-services
  (tag names or IDs; ingestion page reads query params on load)
```

---

## 3. Data Layer

### 3.1 New Table: `tag_embedding_coverage`

**Migration file:** `rag-stack/infrastructure/timescaledb/iteration-11-embedding-coverage.sql`

```sql
CREATE TABLE IF NOT EXISTS tag_embedding_coverage (
    id               BIGSERIAL    PRIMARY KEY,
    tag_id           INT          NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    embedding_model  VARCHAR(100) NOT NULL,
    vector_dims      INT          NOT NULL,
    vector_count     BIGINT       NOT NULL DEFAULT 0,
    file_count       INT          NOT NULL DEFAULT 0,
    status           VARCHAR(20)  NOT NULL DEFAULT 'pending',
    last_embedded_at TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tag_id, embedding_model)
);

CREATE INDEX IF NOT EXISTS idx_tec_tag_model
    ON tag_embedding_coverage (tag_id, embedding_model);

CREATE INDEX IF NOT EXISTS idx_tec_status
    ON tag_embedding_coverage (status);
```

`status` is constrained by application logic, not a DB CHECK, to allow zero-downtime
additions of new status values.

### 3.2 Ent ORM Schema

**File:** `rag-stack/services/common/ent/schema/tag_embedding_coverage.go`

```go
package schema

import (
    "entgo.io/ent"
    "entgo.io/ent/schema/edge"
    "entgo.io/ent/schema/field"
    "entgo.io/ent/schema/index"
)

type TagEmbeddingCoverage struct {
    ent.Schema
}

func (TagEmbeddingCoverage) Fields() []ent.Field {
    return []ent.Field{
        field.Int("tag_id"),
        field.String("embedding_model").MaxLen(100),
        field.Int("vector_dims"),
        field.Int64("vector_count").Default(0),
        field.Int("file_count").Default(0),
        field.String("status").Default("pending"),
        // pending | building | complete | stale
        field.Time("last_embedded_at").Optional().Nillable(),
    }
}

func (TagEmbeddingCoverage) Edges() []ent.Edge {
    return []ent.Edge{
        edge.From("tag", Tag.Type).
            Ref("embedding_coverages").
            Field("tag_id").
            Unique().
            Required(),
    }
}

func (TagEmbeddingCoverage) Indexes() []ent.Index {
    return []ent.Index{
        index.Fields("tag_id", "embedding_model").Unique(),
        index.Fields("status"),
    }
}
```

Add the reverse edge to the `Tag` schema:
```go
edge.To("embedding_coverages", TagEmbeddingCoverage.Type),
```

Regenerate after schema changes:
```bash
cd rag-stack/services/common
go run -mod=mod entgo.io/ent/cmd/ent generate --feature sql/upsert ./ent/schema
```

### 3.3 Stale Transition

When rag-ingestion completes an ingest for `(tag_id, embedding_model)`, it must mark any
**other** `complete` coverage rows for that `tag_id` as `stale`. This captures the case
where new files have been embedded for one model but not others (e.g. all-minilm updated
with new files → nomic-embed-text now incomplete):

```sql
UPDATE tag_embedding_coverage
   SET status = 'stale', updated_at = NOW()
 WHERE tag_id = $1
   AND embedding_model != $2   -- do NOT mark the model that just completed as stale
   AND status = 'complete';
```

This fires at job **completion** (not at the start), after the `complete` upsert for
`(tag_id, model)`. It is an upsert-adjacent operation in the rag-ingestion ingest
handler, not a separate job.

> **NOTE — Bootstrap (future reference):** If a production deployment already has ingested
> vectors and needs to seed `tag_embedding_coverage` from existing data, use:
> ```sql
> INSERT INTO tag_embedding_coverage
>        (tag_id, embedding_model, vector_dims, vector_count, file_count, status,
>         last_embedded_at, created_at, updated_at)
> SELECT DISTINCT
>        ct.tag_id,
>        ce.embedding_model,
>        ce.vector_size,
>        COUNT(ce.id)                         AS vector_count,
>        COUNT(DISTINCT ci.s3_bucket_id)      AS file_count,
>        'complete'                           AS status,
>        MAX(ce.created_at)                   AS last_embedded_at,
>        NOW(), NOW()
>   FROM code_embedding_tag ct
>   JOIN code_embedding ce ON ce.id = ct.code_embedding_id
>   LEFT JOIN code_ingestion ci ON ci.ingestion_id = ce.ingestion_id
>  GROUP BY ct.tag_id, ce.embedding_model, ce.vector_size
>     ON CONFLICT (tag_id, embedding_model) DO NOTHING;
> ```
> Not needed for a fresh install — only if migrating an existing populated database.

---

## 4. Backend Changes

### 4.1 db-adapter — New Coverage Endpoint

**File:** `rag-stack/services/db-adapter/cmd/adapter/handlers.go`

New handler: `POST /api/db/embeddings/coverage`

**Request:**
```json
{
  "tag_ids":        [1, 2, 3],
  "embedding_model": "nomic-embed-text"
}
```

**Response:**
```json
[
  {"tag_id": 1, "tag": "k8s-docs",   "status": "complete",
   "vector_count": 14820, "file_count": 43,  "last_embedded_at": "2026-06-20T..."},
  {"tag_id": 2, "tag": "go-services","status": "pending",
   "vector_count": 0,     "file_count": 0,   "last_embedded_at": null},
  {"tag_id": 3, "tag": "general",    "status": "stale",
   "vector_count": 8100,  "file_count": 29,  "last_embedded_at": "2026-06-18T..."}
]
```

Tags not present in `tag_embedding_coverage` for the given model are returned with
`status: "pending"` and zero counts (synthesized in the handler, not an error).

### 4.2 rag-admin-api — Proxy Route

**File:** `rag-stack/services/rag-admin-api/...`

Add proxy route:
```
POST /api/db/embeddings/coverage  →  db-adapter POST /api/db/embeddings/coverage
```

This is the path used by both rag-worker (coverage check) and the UI (future coverage
display on the ingestion/qdrant pages).

### 4.3 rag-ingestion — Write Coverage Rows

**File:** `rag-stack/services/rag-ingestion/...`

At the **start** of an embedding job for a given tag + model, upsert the coverage row to
`building`:
```sql
INSERT INTO tag_embedding_coverage
       (tag_id, embedding_model, vector_dims, status, updated_at)
VALUES ($1, $2, $3, 'building', NOW())
ON CONFLICT (tag_id, embedding_model)
   DO UPDATE SET status = 'building', updated_at = NOW();
```

At **completion**, update to `complete` with final counts:
```sql
UPDATE tag_embedding_coverage
   SET status = 'complete',
       vector_count     = $3,
       file_count       = $4,
       last_embedded_at = NOW(),
       updated_at       = NOW()
 WHERE tag_id = $1 AND embedding_model = $2;
```

On **failure**, revert to previous status (either `pending` or `stale`):
```sql
UPDATE tag_embedding_coverage
   SET status = CASE WHEN vector_count > 0 THEN 'stale' ELSE 'pending' END,
       updated_at = NOW()
 WHERE tag_id = $1 AND embedding_model = $2;
```

When writing new `code_ingestion` records, mark affected coverage rows stale (see §3.3).

### 4.4 rag-worker — Coverage Check Before Search

**File:** `rag-stack/services/rag-worker/...`

Before searching Qdrant, call the coverage endpoint via rag-admin-api:

```go
// CoverageResult from db-adapter
type CoverageResult struct {
    TagID           int        `json:"tag_id"`
    Tag             string     `json:"tag"`
    Status          string     `json:"status"`
    VectorCount     int64      `json:"vector_count"`
    FileCount       int        `json:"file_count"`
    LastEmbeddedAt  *time.Time `json:"last_embedded_at"`
}

func (w *Worker) checkEmbeddingCoverage(
    ctx context.Context,
    tagIDs []int,
    embeddingModel string,
) ([]CoverageResult, error) {
    // POST /api/db/embeddings/coverage
}
```

Logic after the check:

1. Tags with `status: "complete"` — proceed normally.
2. Tags with `status: "stale"` — search Qdrant (vectors exist), add to advisory list.
3. Tags with `status: "pending"` or `status: "building"`:
   - If `pending`: fire async ingest via `POST /api/ingest/ingest` (fire-and-forget, do
     not await); set no Qdrant search for this tag.
   - If `building`: skip Qdrant search; already in progress.
   - Add to advisory list either way.

Attach the advisory to the Seq 0 metadata chunk:
```json
"missing_embeddings": [
  {"tag_id": 2, "tag": "go-services",  "model": "nomic-embed-text", "status": "pending"},
  {"tag_id": 3, "tag": "general",      "model": "nomic-embed-text", "status": "stale"}
]
```

**Bucket name:** The async ingest trigger omits `bucket_name` — the rag-ingestion service
will default to its `BUCKET_NAME` environment variable. This covers the common case. Tags
that span multiple non-default buckets will ingest only from the default bucket; the
advisory will still surface and the user can trigger a full ingest manually from the UI.

---

## 5. UI Changes

### 5.1 Advisory Banner in Chat

**File:** `lib/features/chat/widgets/message_list.dart` (or inline in `chat_page.dart`)

Parse `missing_embeddings` from the assistant message metadata after receiving a response.
Render an advisory row beneath the message — not inside it — so it doesn't clutter the
chat history on reload.

```dart
Widget _buildEmbeddingAdvisory(List<dynamic> missing) {
  if (missing.isEmpty) return const SizedBox.shrink();

  return Container(
    margin: const EdgeInsets.only(top: 4, bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.amber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.amber.shade600, width: 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: missing.map<Widget>((entry) {
        final tag    = entry['tag']    as String;
        final status = entry['status'] as String;
        final model  = entry['model']  as String;
        final isPending = status == 'pending' || status == 'building';

        final message = isPending
            ? '⚠ "$tag" has no $model embeddings yet. '
              'Ingestion has been triggered — results will improve once complete.'
            : '⚠ "$tag" embeddings are stale (new files added since last run). '
              'Results may be missing recent content.';

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(message,
                  style: const TextStyle(fontSize: 12, color: Colors.amber)),
            ),
            TextButton(
              onPressed: () => _navigateToIngestion(
                  model: model,
                  tagId: entry['tag_id'] as int,
                  tagName: tag),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Go to Ingestion →',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        );
      }).toList(),
    ),
  );
}
```

### 5.2 Deep-Link to Ingestion Page

**File:** `lib/features/chat/chat_page.dart`

```dart
void _navigateToIngestion({
  required String model,
  required int tagId,
  required String tagName,
}) {
  context.go('/ingestion', extra: {
    'model':    model,
    'tag_id':   tagId,
    'tag_name': tagName,
  });
}
```

GoRouter `extra` is used rather than query params so Tag objects can be passed directly
without URL encoding.

### 5.3 Ingestion Page — Accept Pre-Population

**File:** `lib/features/ingestion/ingestion_page.dart`

On `initState`, check for `GoRouterState.extra`:

```dart
@override
void initState() {
  super.initState();
  final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
  if (extra != null) {
    final preselectedModel = extra['model'] as String?;
    final preselectedTagId = extra['tag_id'] as int?;
    final preselectedTagName = extra['tag_name'] as String?;

    if (preselectedModel != null) {
      // Write to shared embeddingModelProvider
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(embeddingModelProvider.notifier).state = preselectedModel;
        // Pre-select the tag if provided
        if (preselectedTagId != null) {
          // Will be resolved against loaded _tags in _loadInitialData
          _preselectedTagId = preselectedTagId;
        }
      });
    }
  }
  _loadInitialData();
}
```

In `_loadInitialData()`, after tags are loaded, auto-select any tag matching
`_preselectedTagId`:

```dart
if (_preselectedTagId != null) {
  final match = _tags.where((t) => t.id == _preselectedTagId).toList();
  if (match.isNotEmpty) {
    _selectedTags.addAll(match);
  }
}
```

---

## 6. File Change Summary

| Layer | File | Change |
|---|---|---|
| DB | `rag-stack/infrastructure/timescaledb/iteration-11-embedding-coverage.sql` | **New** — `tag_embedding_coverage` table + indexes |
| ORM | `rag-stack/services/common/ent/schema/tag_embedding_coverage.go` | **New** — Ent schema |
| ORM | `rag-stack/services/common/ent/schema/tag.go` | Add `embedding_coverages` edge |
| ORM | `rag-stack/services/common/ent/` (generated) | Regenerate after schema changes |
| db-adapter | `cmd/adapter/handlers.go` | Add `POST /api/db/embeddings/coverage` handler |
| rag-admin-api | proxy routes | Add proxy for `/api/db/embeddings/coverage` |
| rag-ingestion | ingest handler | Write coverage rows on start/complete/fail; mark stale on new file ingest |
| rag-worker | search/plan handler | Coverage check; async ingest trigger for pending tags; `missing_embeddings` in Seq 0 metadata |
| UI | `lib/features/chat/widgets/message_list.dart` | Render advisory banner from `missing_embeddings` |
| UI | `lib/features/chat/chat_page.dart` | `_navigateToIngestion()` deep-link helper |
| UI | `lib/features/ingestion/ingestion_page.dart` | Accept `extra` params; pre-populate model + tag |

---

## 7. Implementation Order

1. **DB migration** — apply `iteration-11-embedding-coverage.sql` on hierophant. Prerequisite
   for all backend work.

2. **Ent schema + codegen** — add schema, regenerate, verify `go vet` passes on common module.

3. **db-adapter coverage endpoint** — implement and unit-test with SQLite in-memory.

4. **rag-admin-api proxy route** — add route, verify passthrough.

5. **rag-ingestion coverage writes** — start/complete/fail writes and stale transition.
   Build and deploy. Verify a fresh ingest creates `building` → `complete` rows.

6. **rag-worker coverage check + async trigger** — implement check; fire-and-forget ingest
   for pending tags; attach `missing_embeddings` to Seq 0 metadata.

7. **UI advisory banner** — render `missing_embeddings` from response metadata.

8. **UI deep-link + ingestion pre-population** — navigation helper and `extra` param handling.

9. **End-to-end test** — ingest with `all-minilm` only, chat with `nomic-embed-text` selected,
   verify advisory appears, click deep-link, verify ingestion page pre-populated, trigger
   ingest, verify coverage row transitions to `complete`.

---

## 8. Testing Checklist

**Coverage tracking**
- [ ] Fresh ingest with `all-minilm` creates `complete` coverage row in TimescaleDB
- [ ] Coverage row starts at `building` during ingest and transitions to `complete` on finish
- [ ] Adding a new file to S3 for an already-`complete` tag marks its coverage as `stale`
- [ ] `POST /api/db/embeddings/coverage` returns synthesized `pending` for tags with no row

**rag-worker advisory**
- [ ] Chat with `nomic-embed-text` on tags only embedded with `all-minilm` → `missing_embeddings` present in Seq 0 metadata
- [ ] `pending` tag fires async ingest via admin-api (confirm via rag-ingestion logs)
- [ ] `building` tag does NOT fire a duplicate ingest trigger
- [ ] `stale` tag is searched in Qdrant (vectors exist) AND appears in advisory

**UI**
- [ ] Advisory banner renders for `pending` tags with correct message
- [ ] Advisory banner renders for `stale` tags with distinct message
- [ ] "Go to Ingestion →" navigates to `/ingestion` with model pre-selected
- [ ] Ingestion page pre-selects the correct tag from deep-link
- [ ] No advisory banner shown when all selected tags are `complete`

**Build quality**
- [ ] `go vet ./...` passes on db-adapter, rag-ingestion, rag-worker after changes
- [ ] `flutter analyze` passes with no new warnings
