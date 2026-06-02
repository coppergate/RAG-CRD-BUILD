# RAG Retrieval Debug Handoff

## Goal
Isolate why the ingestion/retrieval path works in direct Qdrant probes but still fails at final answer generation in the service path.

## What Was Built

### 1. Bypass-style visibility in tests
The test suite was extended to probe Qdrant directly before the gateway call.

Relevant files:
- `rag-stack/tests/retrieval_path_test.py`
- `rag-stack/tests/integration_test.py`

What the bypass probe does:
- normalizes the embedding model into the collection name
- performs a direct Qdrant scroll with tag filtering
- performs a direct Qdrant search using an Ollama embedding for the query
- prints the returned points before the gateway path runs

### 2. Isolated ingestion/retrieval test
`rag-stack/tests/retrieval_path_test.py` now drives one document through:
- upload to S3
- ingestion request
- tag association
- direct Qdrant probe
- retrieval request
- replay/audit verification

The test question was changed from the earlier guarded wording to a flower-context question:
- question: `What is the best way to tend a flower? Return the exact answer from the document.`
- expected answer is embedded in the test document content

### 3. Model-specific prompt shaping in the worker
`rag-worker` was updated so execution prompt shaping varies by model family.

Relevant files:
- `rag-stack/services/rag-worker/internal/models/base.go`
- `rag-stack/services/rag-worker/internal/models/llama3/model.go`
- `rag-stack/services/rag-worker/internal/models/granite31/model.go`

The intent was:
- `llama3` uses tagged context blocks
- `granite31` uses numbered context sections

### 4. Extra logging in ingestion and Qdrant adapter
More verbose logging was added around:
- ingestion collection creation
- chunk embedding
- Qdrant request parameters
- filter-only retrieval
- search responses

Relevant files:
- `rag-stack/services/rag-ingestion/service.py`
- `rag-stack/services/qdrant-adapter/cmd/adapter/main.go`
- `rag-stack/services/qdrant-adapter/internal/qdrant/client.go`

## Deployments Completed
The modified services were rebuilt and deployed on `hierophant`:

- `rag-worker` -> `2.4.30`
- `rag-ingestion-service` -> `2.4.18`
- `qdrant-adapter` -> `2.4.18`

The rollout completed successfully for all three.

## What Actually Happened in Testing

### Isolated retrieval test
The isolated retrieval test was run successfully as a Kubernetes job, but it did **not** pass.

Observed behavior:
- ingestion completed
- the file reached `SYNCED`
- direct Qdrant probe returned the expected tagged row
- worker logs showed one file was reassembled for the query
- the final response still returned a generic flower guide, duplicated, instead of the exact document answer

Important distinction:
- the retrieval layer succeeded
- the final answer generation step still failed

### End-to-end test
The full end-to-end suite was **not run** after the isolated retrieval test failed.

## Evidence From Logs

### Worker-side evidence
The worker logs show:
- tag resolution succeeded
- tag-only Qdrant retrieval returned one item
- semantic search returned one item
- one file was reassembled for the model
- execution summary completed with nonzero context

### Qdrant-adapter evidence
The adapter logs show:
- create_collection used collection `vectors-llama3-1-latest-4096`
- search requests carried the expected tag and vector dimensions
- filter-only retrieval on `vectors-llama3-1-latest-4096` returned one result

### Test-side evidence
The isolated test logs show:
- direct Qdrant probe failed to use `get_collection()` cleanly because the installed `qdrant-client` schema disagrees with the server response shape
- that probe still confirmed the expected rows via scroll/search behavior

## Current Interpretation
The data path is intact:
- upload works
- ingestion works
- tagging works
- Qdrant stores and returns the expected item
- the worker retrieves one relevant file

The unresolved problem is later:
- the model still does not answer from the supplied context
- the final response looks like generic model behavior, not document-grounded behavior

## Versioning Notes
There was no build-system versioning regression.
The rebuild correctly bumped image versions based on changed source hashes.

Observed version changes:
- `rag-worker`: `2.4.29 -> 2.4.30`
- `rag-ingestion`: `2.4.17 -> 2.4.18`
- `qdrant-adapter`: `2.4.17 -> 2.4.18`

The only version-related hiccup encountered in the local workspace was file permission access to `CURRENT_VERSION`, which did not block the cluster build.

## Likely Next Investigations

1. Inspect the exact executor prompt emitted by `rag-worker` for the failing session.
2. Compare the isolated prompt shape with the service prompt shape at the point context is inserted.
3. Verify whether the answer-generation prompt is losing the retrieved context, truncating it, or wrapping it in a format the model is ignoring.
4. Consider whether `llama3.1:latest` and `granite3.1-dense:8b` need different prompt envelopes beyond the current shaping hook.
5. Fix or bypass the direct Qdrant `get_collection()` probe if its schema mismatch is obscuring test output.

## Useful Files
- `rag-stack/services/rag-worker/pkg/pipeline/pipeline.go`
- `rag-stack/services/rag-worker/internal/models/base.go`
- `rag-stack/services/rag-worker/internal/models/llama3/model.go`
- `rag-stack/services/rag-worker/internal/models/granite31/model.go`
- `rag-stack/services/rag-ingestion/service.py`
- `rag-stack/services/qdrant-adapter/internal/qdrant/client.go`
- `rag-stack/tests/retrieval_path_test.py`
- `rag-stack/tests/integration_test.py`

