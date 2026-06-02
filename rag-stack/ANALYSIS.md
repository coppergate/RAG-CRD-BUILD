# RAG Stack Architecture and Code Quality Analysis

**Date:** 2026-06-01
**Branch:** work-2026-05-30
**Iteration:** 9 (complete)

---

## Executive Summary

The RAG stack is a mature, multi-service pipeline running on Kubernetes. The core flow is: HTTP request -> llm-gateway -> Pulsar -> rag-worker (ingress -> plan -> search -> exec) -> Pulsar -> db-adapter/prompt-aggregator -> HTTP response. A Python service (rag-ingestion) handles document ingest from S3/Ceph into Qdrant. Supporting services provide vector search (qdrant-adapter), memory (memory-controller), admin/reporting (rag-admin-api), and object store management (object-store-mgr).

The codebase is reasonably well-structured with good use of interfaces and DLQ-based retry logic. The Iteration 9 "behavioral memory" and "learning loop" features are implemented but add significant complexity to the plan stage. The main areas of concern are: **metadata proliferation** (the `req.Metadata` bag carries ever-growing state through all pipeline stages), **missing circuit breakers and retry caps**, **duplicate utility logic across services**, **test coverage gaps in negative paths**, **hardcoded domain/model strings**, and **resource leak patterns** in the Pulsar consumer and prompt-aggregator.

---

## Per-Service Findings

### 1. rag-worker (`services/rag-worker/`)

**What it does:** Consumes Pulsar messages for each pipeline stage (ingress, plan, search, exec). Implements the full LLM reasoning loop including memory retrieval, embedding, Qdrant search, context chunking, plan decomposition, and LLM execution with streaming and recursion.

#### Structural Issues

**`pkg/pipeline/pipeline.go`**

- **Line 130 — Hardcoded HTTP timeout:** `httpClient: &http.Client{Timeout: 30 * time.Second}`. The ingestion hydration call (line 818) and the context file fetch (line 637-656) use this same 30s timeout. During hydration, `rag-ingestion` may spend minutes re-embedding large files. If the context times out the hydration POST returns an error and the worker falls back to empty context silently. The timeout should be configurable separately for the hydration path.

- **Lines 700-712 — Blocking `time.Sleep` in retry loop:** `searchWithEmbeddingModel` sleeps `(attempt+1)` seconds between up to 4 retry attempts after collection hydration. This blocks the Pulsar message consumer goroutine for up to 10 seconds. If many messages arrive during collection creation this will saturate the consumer pool. Should use exponential backoff with context-aware sleep or use a background check with a channel.

- **Line 217-218 — Ignored error from `GetActionIdentifiers`:**
  ```go
  actionMap, _ := h.memoryClient.GetActionIdentifiers(ctx)
  ```
  The error is silently discarded. If the memory-controller is unavailable this returns a nil map and `DetectActionType` falls back to UNKNOWN — which is acceptable — but the failure is invisible to monitoring. Should at minimum log a warning with metric increment.

- **Lines 1848-1852 / 1864-1869 — Silent recursion/pagination failures:** When re-sending to the plan or exec Pulsar topic fails during recursion, the error is silently ignored (the marshal/send errors are not propagated — only checked with `if err == nil`). This means a failed re-plan looks like a successful pipeline completion but produces no answer. Should emit `SendError` before returning.

- **Line 822 — Response body not read before close in hydration loop:** `resp.Body.Close()` is called immediately without reading the body. For HTTP/1.1 keepalives this prevents connection reuse. Should drain the body: `io.Copy(io.Discard, resp.Body)`.

- **Line 1172 — `logging.Printf("ERROR: ...")` pattern:** Using `Printf` with an "ERROR:" prefix is inconsistent with the structured logging approach. Should use a dedicated error-level log if the logging package supports it.

- **Lines 491-492 — Metadata carries raw_results (full vector payloads) through Pulsar:** `metadataMap["raw_results"] = allRawResults` serializes all retrieved Qdrant payloads (content text, vectors, metadata) into the Protobuf Struct and sends them in the Pulsar message. For large retrieval sets this can create multi-MB Pulsar messages, approach the broker's `maxMessageSize` limit, and degrade throughput. Raw results should not be forwarded beyond the search stage unless absolutely necessary.

- **Line 517 — Second full planner call in search stage:** `planner.Plan` is called a second time with the retrieved chunk context to "refine" the plan. This doubles LLM calls per request during the search stage. If the planner is slow or unavailable this silently degrades (line 519 logs but swallows the error). The refinement plan is stored in metadata but there is no circuit-breaker if the same planner repeatedly fails.

**`internal/models/base.go`**

- **Lines 379-418 — `ParsePlannerTaskPlan` fallback is too permissive:** The fallback always returns a non-nil plan with `search_queries: [prompt]`. This means a completely malformed planner response (including empty string, error messages, or JSON garbage) is silently treated as a valid plan. There is no way for the caller to distinguish "planner returned a valid plan" from "planner output was unparseable". The `ParserMode` field tracks this but is not checked at the call site to adjust behavior.

- **Line 427 — `extractJSONSnippet` extracts first `{` to last `}`:** If the planner wraps the JSON in a markdown fence AND includes other braces in prose text, this will incorrectly extract from the first brace in prose to the last brace in the code fence. The code fence stripping (lines 427-436) only handles the outermost fence but not nested prose. This is a known-fragile heuristic.

**`internal/models/granite31/model.go`**

- **Lines 16-24 — `InsufficientContextPhrases` contains a duplicate:**
  `"i can't provide"` appears at index 15 and 18. Dead entry, no functional impact but suggests this list was hand-maintained without deduplication.

- **The planner and executor share the same `Config`:** The `PlanningPromptTemplate` is only used by `Plan()` and the `ExecutionHeader/Footer/Suffix` are only used by `Execute()`. If a future model needs different system instructions for planning vs execution the current architecture requires duplicating the entire `ModelConfig` struct. The planner and executor should have separate configs.

**`pkg/pipeline/pipeline_test.go`**

- Test coverage exists for: chunk dedup, search fallback on unsupported embeddings, plan stage happy path, learning loop, missing planner model, reset behavior, exec recursion trigger, exec with raw_results fallback, literal answer extraction, and step context prompt preservation.
- **Missing tests:** handleIngress (no test at all), handleSearch with zero results (no context path), handleExec with streaming mode, handleExec when both recursion budget AND chunk pagination are exhausted simultaneously, hydrateContextFiles error paths, fetchContextFiles non-200 response.

---

### 2. db-adapter (`services/db-adapter/`)

**What it does:** Consumes Pulsar messages for prompt events, response stream chunks, and completion events. Persists data to TimescaleDB via the Ent ORM. Handles out-of-order delivery via "ghost prompt" records.

#### Structural Issues

**`internal/service/pulsar_processor.go`**

- **Lines 96-102 / 443-448 — Transaction `Rollback` in `defer` with panic-only guard:** The pattern:
  ```go
  defer func() {
      if r := recover(); r != nil {
          tx.Rollback()
          panic(r)
      }
  }()
  ```
  does NOT rollback the transaction on normal error return. If `tx.Session.Delete` fails (line 133) the code calls `tx.Rollback()` explicitly, which is correct. But in `HandleResponse`, if any of the non-transaction operations after `tx.Commit()` fail (e.g., the retrieval log inserts at lines 549-579), there is no rollback needed — but the defer pattern gives a false impression of safety. The `delete_session` handler (lines 104-113) also swallows errors from deleting metrics and retrieval logs (logged as Warning) but then continues to delete the session — this can leave orphaned records if the session delete also fails.

- **Lines 399-400 — Double not-found check:**
  ```go
  isNotFound := ent.IsNotFound(err)
  if !isNotFound && err != nil && strings.Contains(err.Error(), "not found") {
      isNotFound = true
  }
  ```
  This defensive double-check implies `ent.IsNotFound` is not trusted. Either fix the Ent schema to return proper sentinel errors or use only the string check. The inconsistency indicates an unresolved bug from a previous iteration.

- **Lines 534-534 — Unreachable error check:**
  ```go
  if err != nil {
      return dlq.TransientFailure, fmt.Errorf("transactional upsert response for prompt %s: %w", payload.Id, err)
  }
  ```
  This check at line 534 occurs after both the `if ent.IsNotFound(err)` and `else` branches have either returned or committed. The variable `err` at this point is the `tx.Commit()` error from the else branch (line 529), which was already checked. This dead code should be removed.

- **Lines 549-579 — Retrieval log inserts ignore errors:** The `_, _ = p.client.RetrievalLog.Create()...` pattern silently discards insert errors. These are observable data for the admin API and silent failures will cause gaps in reporting. Should at minimum log failures.

- **Lines 605-606 — `uuid.Parse` ignores parse error for completion:**
  ```go
  respID, _ := uuid.Parse(payload.Id)
  ```
  If `payload.Id` is not a valid UUID, `respID` will be the zero UUID. The subsequent query (line 608) will attempt to find a response with UUID `00000000-0000-0000-0000-000000000000`, which may match unrelated records or silently fail. Should return `PermanentFailure` on parse error, consistent with `HandlePrompt` and `HandleResponse`.

- **Lines 116-117 — `sanitizeString` removes only null bytes:** The function only strips `\x00`. It does not protect against other control characters that can corrupt PostgreSQL `text` columns when combined with certain client encodings. Consider also stripping U+FFFE/U+FFFF or using `strings.Map`.

#### Missing Observability

- No metric is emitted when a ghost prompt is created (line 413). Ghost prompt creation indicates out-of-order delivery — tracking this frequency is useful for diagnosing Pulsar consumer lag.
- No metric for retrieval log insert failures.

---

### 3. llm-gateway (`services/llm-gateway/`)

**What it does:** HTTP entrypoint. Accepts OpenAI-compatible and generic chat requests, manages sessions in the DB, publishes to Pulsar, and either polls a result channel (non-streaming) or fans out to a per-request Pulsar topic (streaming via WebSocket).

#### Structural Issues

**`internal/handlers/openai.go`**

- **Line 509-513 — Hardcoded default model:**
  ```go
  if req.Planner == "" {
      req.Planner = "llama3.1:latest"
  }
  if req.Executor == "" {
      req.Executor = "llama3.1:latest"
  }
  ```
  This is in `HandleGenericChat` only, not in `HandleChatCompletions`. The default model is baked into handler code rather than loaded from config. Should be a config value.

- **Line 421 — `time.After(60 * time.Second)` — hardcoded WebSocket stream timeout:** The streaming handler uses a 60-second per-chunk timeout. If the LLM takes longer than 60 seconds to produce a single token (documented concern in `project_go_e2e_driver.md`), the gateway silently closes the WebSocket without sending an error to the client. Should be configurable and should send a timeout error frame before closing.

- **Line 301 — `w.Header().Set("Content-Type", "application/json")` is set twice** in `HandleChatCompletions` (lines 281 and 301). The second call is a no-op after `w.WriteHeader` is implicitly called, but indicates copy-paste error.

- **Lines 182-193 — Input size not limited:** `json.NewDecoder(r.Body).Decode(&req)` reads an unbounded request body. A malicious or misbehaving client can send an arbitrarily large payload. Should wrap `r.Body` with `http.MaxBytesReader`.

- **`internal/pulsar/client.go` lines 82-87 — `consumeResults` fan-out discards chunks for unknown IDs:**
  ```go
  if ch, ok := pc.pending.Load(resp.Id); ok {
      ch.(chan response) <- resp
  }
  ```
  If the gateway restarts while a request is in-flight, the `pending` map is empty and all arriving chunks are silently discarded. The client also acknowledges the message regardless (line 86), so the data is lost permanently. This is expected for the non-streaming path (no replay), but should be documented as a known limitation.

- **Lines 104-129 — `SendRequest` timeout can leave dangling goroutines:** If `time.After` fires first, `SendRequest` returns a timeout error and the deferred `pending.Delete(id)` fires. However, the consumer goroutine at line 83 may still attempt to send to the now-deleted (and gc'd) channel. The channel is buffered (size 10) so the goroutine won't block, but the next `pc.pending.Store` for a different request with the same ID string could theoretically pick up stale responses if UUIDs collide (astronomically unlikely but worth noting).

- **WebSocket origin check (lines 26-40) — Internal domain hardcoded:**
  ```go
  if strings.HasSuffix(origin, ".hierocracy.home") {
  ```
  The internal domain `.hierocracy.home` is hardcoded. If the deployment domain changes this must be updated in code. Should be an environment variable.

#### Missing Observability

- No metric for WebSocket stream timeout events.
- No metric for pending channel capacity (to detect back-pressure).

---

### 4. rag-ingestion (`services/rag-ingestion/service.py`)

**What it does:** Python FastAPI service. Accepts ingest requests, downloads files from S3, chunks them with LangChain splitter, embeds with Ollama, publishes points to Qdrant via Pulsar, and mirrors metadata to PostgreSQL.

#### Structural Issues

- **Lines 335-336 / 613 — Pulsar client created and closed per ingest job:** A new `pulsar.Client` is created at the start of every `run_ingestion` call and closed in `finally`. For frequent ingest requests this creates and destroys TLS connections repeatedly. The client should be a module-level singleton (similar to `_db_pool`).

- **Lines 504-513 — PostgreSQL commit occurs inside the per-chunk loop body without error handling:** The `code_embedding` insert is inside the S3 file loop but the connection is committed via `conn.commit()` only at batch boundaries (line 562) or at the end. However, the `with conn.cursor() as cur: cur.execute(...)` at line 504 does NOT commit. If the ingestion job crashes after embedding but before the next `conn.commit()`, the embeddings are in Qdrant but not in PostgreSQL — creating a divergence. The PostgreSQL write should either commit per chunk or be wrapped in a transaction that is only committed when the corresponding Pulsar batch is confirmed sent.

- **Lines 537-561 — Qdrant upsert via Pulsar is fire-and-forget:** The `q_prod.send(...)` call at line 551 does not await confirmation. If the Pulsar broker or qdrant-adapter is down, the points are silently lost while PostgreSQL records are committed. There is no reconciliation mechanism.

- **Lines 430-431 — `content = response['Body'].read().decode('utf-8')` — no encoding fallback:** If a file has non-UTF-8 content (e.g., a `.c` file with Latin-1 comments), this raises `UnicodeDecodeError`. The outer `except Exception` at line 565 catches it but the entire file is then skipped without retry or alerting. Should use `errors='replace'` or detect encoding.

- **Lines 196-217 — Embedding retry uses `time.sleep` (blocking):** In an async FastAPI worker (`async def trigger_ingest` -> `background_tasks.add_task`), `time.sleep` blocks the background task thread. While `run_ingestion` is synchronous (standard `def`), the task runs in FastAPI's thread pool executor so this is not an async violation, but the retry logic uses a simple `for` loop sleep — if the Ollama server is down for 30s, all batch threads will be sleeping simultaneously consuming thread pool slots.

- **Lines 620-621 — `ingestion_id` defaults to 0 on DB failure:** If the DB insert to create a new ingestion record fails, `ingestion_id` remains 0 and the background task runs with `ingestion_id=0`. All `code_embedding` records will be inserted with `ingestion_id=0`, corrupting the FK relationship.

- **Lines 693-721 — `/readyz` creates a new Pulsar client on every probe:** The readiness probe at line 698-700 calls `_create_pulsar_client()` and immediately closes it. Kubernetes probes can fire every few seconds; each probe creates and destroys a TLS connection to Pulsar. Should maintain a persistent client for health checks.

- **Line 113 — `verify=False` in integration_test.py:** The `_ollama_embeddings` function in `integration_test.py` uses `verify=False` (SSL verification disabled). This is a security concern in a production cluster and inconsistent with the service's own TLS handling. Should use `SSL_CERT_FILE` if available.

#### Missing Observability

- No structured metrics (Prometheus/OTel) for ingestion throughput, embedding latency, or chunk failure rate. Only stdout logging.
- `failed_chunks` list is logged at end but never sent to any monitoring system.

---

### 5. qdrant-adapter (`services/qdrant-adapter/`)

**What it does:** REST service wrapping the Qdrant HTTP API. Provides search, upsert, delete, collection management, and tag merge endpoints consumed by other services.

#### Structural Issues

**`internal/qdrant/client.go`**

- **Lines 596-597 / 612-613 — `fmt.Printf("DEBUG:")` and `fmt.Printf("ERROR:")` calls:** Debug/error output goes directly to stdout via `fmt.Printf`, bypassing the common `logging` package used elsewhere. These must be converted to `logging.Printf` for consistent log aggregation.

- **Lines 191-192 / 267-268 — `json.Marshal` and `http.NewRequest` errors ignored:**
  ```go
  body, _ := json.Marshal(query)
  req, _ := http.NewRequest("POST", url, bytes.NewBuffer(body))
  ```
  Both errors are silently discarded in `RetrieveByFilter` and `RetrieveByPaths`. If marshal fails (impossible for this specific payload) or request creation fails (possible for malformed URLs), the subsequent `q.httpClient.Do(req)` will panic with a nil pointer. Should check errors and return them.

- **Lines 61-87 — `resolveCollection` makes a network call on every search:** When `vectorSize <= 0`, `resolveCollection` calls `q.listCollectionNames()` which makes an HTTP GET to Qdrant on every invocation. If the vector size is always provided (which it should be for all production paths), this is never hit, but if it is hit under load it creates N Qdrant collection-list calls per search. There is no caching.

- **Lines 620-684 — `MergeTags` has an unimplemented semantics problem:** The function comment (lines 635-660) acknowledges that the current implementation overwrites the entire `tags` array with `[targetTag]` rather than appending `targetTag` to the existing array. Any point that had `[sourceTag, otherTag]` will end up with only `[targetTag]`, losing `otherTag`. This is a data-loss bug if tags have been multi-assigned. The comment says "for this iteration" but the bug exists in production code.

- **Lines 343-345 — `DeleteByFilter` returns nil when both tags and paths are empty:** If called with empty slices for both `tags` and `paths`, the function returns `nil` without performing any deletion. This is correct behavior but the caller has no way to distinguish "deleted successfully" from "nothing to delete". Not a bug but worth documenting.

- **No request-level timeouts on individual HTTP calls:** The `httpClient` is created with a single 10s timeout for the entire client. A slow Qdrant response on a large collection will block for 10s. Collection operations during high-write load may take longer; the timeout should be per-operation and configurable.

---

### 6. prompt-aggregator (`services/prompt-aggregator/`)

**What it does:** Consumes `ResponseCompletion` events from Pulsar. For each completion, reads all chunks from a per-request session topic, assembles them in sequence-number order, and publishes the final aggregated result to the db-adapter results topic.

#### Structural Issues

**`cmd/aggregator/main.go`**

- **Lines 172-173 — 30-second timeout for `aggregateChunks`:** The aggregation timeout is hardcoded to 30 seconds. If the rag-worker produces the final `IsLast=true` chunk at 31 seconds (LLM slow path), the aggregator times out, returns a partial result if chunks exist, or returns empty. The 30s constant is not aligned with the gateway's 60s stream timeout. Should be configurable and at least match the documented LLM timeout.

- **Lines 160-207 — `aggregateChunks` consumes an exclusive reader on a per-request session topic, creating one Pulsar reader per completion event.** Under high concurrency (e.g., 100 simultaneous requests), this creates 100 simultaneous Pulsar readers. Pulsar readers are stateful TCP connections; there is no pool or limit. This can exhaust file descriptors or broker connection limits. The session-topic fan-out pattern works for low concurrency but does not scale horizontally.

- **Lines 176-183 — Partial result handling is ambiguous:** When the context times out with partial chunks, the function returns the partial result assembled from what arrived, with `nil` error. The caller at line 137 checks `fullResult == ""` and skips sending — but a partial result with data will be sent as if it were complete. The `db-adapter` will overwrite the existing streamed response with this partial aggregation. Should distinguish timeout-with-partial-data from timeout-with-no-data.

- **Lines 120-122 — `comp.Status == "FAILED"` skips aggregation but still acks:** When the completion status is FAILED, the aggregator acks the message and skips. However, the db-adapter may still have partial streaming data for this request. The final db state will be whatever partial data the db-adapter received via streaming, without a "FAILED" marker on the response row. There is no mechanism to mark the response row as failed in the DB.

- **Line 104 — `consumer.Receive(ctx)` with background context:** The consumer runs in a goroutine with `context.Background()` passed to `Receive`. If the aggregator receives a SIGTERM, `cancel()` is called on the main ctx but the `consumer.Receive` call blocks until the next message or consumer close. The goroutine will only exit when the consumer is closed by the deferred `defer consumer.Close()` on the main goroutine. This is a 1-2 second graceful drain window which is acceptable, but there is no explicit draining timeout.

---

### 7. memory-controller (`services/memory-controller/`)

**What it does:** Manages behavioral rules, episodic history, task context, and governance scopes for sessions. Provides HTTP API for memory retrieval, writing, auditing, and behavioral reset.

#### Structural Issues

**`internal/logic/manager.go`**

- **Transaction rollback pattern is inconsistent:** `WriteItems` calls `tx.Rollback()` explicitly on error, but the `defer` does not call rollback on normal return (only on panic). If `tx.Commit()` is never called (e.g., an early return before commit), the transaction will eventually time out at the DB level rather than being explicitly rolled back. The standard Go Ent pattern should be: `defer tx.Rollback()` unconditionally (it is a no-op after commit), then `tx.Commit()` at the end.

- No test for the `Retrieve` function which has complex multi-path logic (behavioral rules, episodic history, task context, governance overrides). The `manager_test.go` coverage is focused on behavioral rule CRUD, not on the retrieval scoring/ranking path.

---

### 8. object-store-mgr (`services/object-store-mgr/`)

**What it does:** Thin Go HTTP service wrapping the AWS S3 SDK v2. Provides bucket and object CRUD endpoints.

#### Structural Issues

**`cmd/manager/main.go`**

- **Lines 34-36 — HTTP scheme defaulting to `http://` not `https://`:**
  ```go
  if endpoint != "" && !strings.HasPrefix(endpoint, "http") {
      endpoint = "http://" + endpoint
  }
  ```
  All other services (rag-ingestion, llm-gateway) default to `https://` for S3. The object-store-mgr defaults to `http://`. This inconsistency means the object-store-mgr cannot connect to the Ceph HTTPS endpoint without explicit `https://` prefix in the env var.

- **No request size limiting on upload endpoints.** The service exposes file upload without `http.MaxBytesReader`, allowing arbitrarily large uploads that consume memory.

- **No test files exist for this service.** Zero unit or integration test coverage.

---

### 9. rag-admin-api (`services/rag-admin-api/`)

**What it does:** Reverse proxy and aggregating API gateway. Routes `/api/db/*` to db-adapter, `/api/chat/*` to llm-gateway, and aggregates health status from all services.

#### Structural Issues

**`internal/handlers/admin.go`**

- **Lines 65-77 — Response body is buffered and logged:** The admin handler captures every proxied response into a `bytes.Buffer` and logs the first 200 bytes. For responses that include sensitive user data (chat results, session content), this logs PII to the log aggregator on every request. Should be removed or gated behind a debug flag.

- **Line 22 — `url.Parse` error is silently discarded:**
  ```go
  target, _ := url.Parse(targetURL)
  ```
  If `targetURL` is malformed, `target` will be nil and `httputil.NewSingleHostReverseProxy(nil)` will panic on first request. Should return an error from `ProxyTo` or fatal during startup.

- **Test coverage (`admin_test.go`):** Only tests `ProxyTo` (basic path strip) and health aggregation status codes. No test for the chat proxy path, session replay endpoint, or WebSocket upgrade passthrough.

---

## Cross-Cutting Issues

### CC-1: Metadata Bag Anti-Pattern (P0)

`contracts.InternalRequest.Metadata` is a `*structpb.Struct` (arbitrary JSON map). Over the pipeline stages, this map accumulates: `sub_queries`, `action_type`, `planner_task`, `planner_trace`, `evaluation_metrics`, `history`, `chunks`, `chunk_groups`, `contexts`, `raw_results`, `embedding_models`, `retrieval_provenance`, `plan_step_contexts`, `recursion_budget`, `recursion_count`, `total_chunks_processed`, `chunk_offset`. By the exec stage, a single message can exceed 1MB of metadata (especially with `raw_results`). Protobuf Struct serialization adds overhead on every stage. This pattern makes it extremely difficult to add type safety, validate schema, or unit test individual field interactions. The metadata should be structured as typed Protobuf fields on `InternalRequest`, with `raw_results` removed from inter-stage propagation.

### CC-2: Duplicate Pulsar Client Setup (P1)

Every service that uses Pulsar independently instantiates `pulsarCommon.NewClient`. The TLS configuration, retry behavior, and connection parameters are each set in service-specific config files with no shared validation. There is a `common/pulsar` package but it does not enforce a standard connection health check or reconnect policy. Changes to Pulsar topology (e.g., switching brokers, updating TLS certificates) require coordinated updates across all services.

### CC-3: Duplicate `_normalize_model_name` Implementation (P1)

The model name normalization logic (lowercase, replace non-alphanumeric with `-`, strip leading/trailing dashes) is implemented independently in:
- `rag-ingestion/service.py` (lines 178-181)
- `tests/integration_test.py` (lines 77-87)
- `tests/manual_ingestion_retrieval_test.py` (lines 81-91)
- `common/contracts` package (Go, `NormalizeEmbeddingModelName`)

The Python and Go implementations use different regex patterns. If a model name normalizes differently between Python (ingest) and Go (search), vectors will be stored in one collection name but searched in another, causing silent zero-result retrievals. This has been a source of bugs and must be unified.

### CC-4: Missing Circuit Breakers for Ollama (P1)

All LLM calls go through `ollama.Client.Chat` / `GetEmbeddings` with no circuit breaker. If Ollama is overloaded or restarting:
1. The rag-worker will queue up messages in Pulsar topic backlog.
2. All consumer goroutines will be blocked on HTTP calls with no timeout enforcement at the Ollama client level (only at the `httpClient` level in `NewHandler`).
3. DLQ re-delivery will compound the load.

A circuit breaker (half-open state with probe requests) or at minimum a configurable concurrency semaphore per model should be implemented.

### CC-5: No Backpressure on Pulsar Consumers (P1)

The rag-worker starts N consumer goroutines per stage topic (one per `DLQConsumer`). Each goroutine processes messages serially. There is no global concurrency limit across all stages. During a traffic spike, all goroutines will be simultaneously blocked on LLM calls, Qdrant, or the db-adapter. The Pulsar backlog will grow unboundedly. A worker pool with a configurable `maxConcurrentRequests` semaphore should be added.

### CC-6: Inconsistent Error Return on Pulsar Send Failures During Recursion (P0)

In `handleExec` (pipeline.go lines 1848-1869), when re-sending to the plan or exec topic for recursion/pagination:
```go
if err == nil {
    if _, err := h.msg.Producers.Exec.Send(...); err == nil {
        return dlq.Success, nil
    }
}
```
If the marshal or send fails, the function falls through to the normal completion path and calls `SendCompletion` and `SendResult` with an empty or partial result. The user receives an empty response with no error indication. This is the most critical correctness issue in the codebase.

### CC-7: `fmt.Printf` / `fmt.Println` Usage in Service Code (P2)

`qdrant-adapter/internal/qdrant/client.go` uses `fmt.Printf` for debug/error output (lines 597, 603, 616). `prompt-aggregator/cmd/aggregator/main.go` uses `fmt.Printf` (line 40 in Go file via logging, acceptable). All service code should use the `common/logging` package exclusively.

### CC-8: TLS Configuration Inconsistency (P1)

- `object-store-mgr` defaults to `http://` for S3.
- `rag-ingestion` defaults to `http://` for Ollama (`_ollama_default` line 96) but `https://` for S3.
- `llm-gateway` hardcodes `.hierocracy.home` as the allowed WebSocket origin domain.
- `rag-admin-api` logs proxied response bodies (potential PII exposure).
- `tests/integration_test.py` uses `verify=False` for Ollama HTTP calls.

There is no shared TLS policy document. Each service makes independent TLS decisions.

### CC-9: Context Propagation Gaps (P2)

- `db-adapter/pulsar_processor.go` `HandleCompletion` uses `ctx` (the original `context.Background()`) rather than `msgCtx` (which has the trace propagated from the message properties) for the DB queries on lines 611, 623, 633, 643. The span created at line 589 will not have child spans from these DB calls.
- `prompt-aggregator/main.go` `aggregateChunks` creates a `context.WithTimeout` but the spans inside are not attached to the parent trace. The 30s timeout creates spans in a new root context.

---

## Test Coverage Gaps

### Unit Test Gaps

| Location | Missing Coverage |
|---|---|
| `rag-worker/pkg/pipeline/pipeline.go` | `handleIngress`, streaming exec path, `hydrateContextFiles` errors, `fetchContextFiles` non-200, `searchEmbeddingModelOnce` with tag-only path |
| `rag-worker/pkg/pipeline/pipeline.go` | Recursion/pagination silent failure on re-send error (CC-6 above) |
| `rag-worker/internal/models/base.go` | `ParsePlannerTaskPlan` with empty string, with non-JSON prose, with nested braces in markdown |
| `db-adapter/pulsar_processor.go` | Ghost prompt creation race, `HandleCompletion` with invalid UUID, retrieval log insert failure |
| `memory-controller/internal/logic/manager.go` | `Retrieve` function with all memory type combinations |
| `qdrant-adapter/internal/qdrant/client.go` | `resolveCollection` with zero vectorSize, `MergeTags` multi-tag loss bug |
| `object-store-mgr` | No tests at all |
| `prompt-aggregator` | Timeout with partial data, FAILED status handling, context cancellation drain |

### Integration Test Gaps

1. **No test for ingestion failure mode:** `rag-ingestion` embedding failure (`failed_chunks`) path is exercised only in the nominal case. No test uploads a binary file that fails UTF-8 decode.

2. **Test assertions are LLM-output-dependent:** `integration_test.py` asserts `"Zeltron-9" not in result` (line 333) and `"Refined sub-queries for " not in planning_response` (line 380). These strings are produced by the LLM and can change if the model is updated or the system prompt is tweaked. Should use structural assertions (non-empty, JSON-parseable) rather than content strings where possible, or externalize expected strings.

3. **No negative path E2E tests:** `sad_path_test.py` exists but was not thoroughly reviewed. The integration suite has no test for: request with invalid session ID, request with non-existent tag, Qdrant collection not found (hydration path), memory-controller unavailable, Ollama timeout.

4. **No streaming path E2E test:** The integration tests use the HTTP `/v1/rag/chat` endpoint exclusively. The WebSocket streaming path (`/v1/rag/stream`) has no integration test. The streaming path in `handleExec` (the `req.Stream == true` branch) has no unit test.

5. **`manual_ingestion_retrieval_test.py` duplicates chunking/collection logic:** The test reimplements `_split_text` and `_collection_name` in Python rather than calling the ingestion service. Divergence between the test's reimplementation and the production service's LangChain splitter can mask bugs. The test passing does not guarantee the service's code path is correct.

6. **Model matrix tests (`model_matrix.py`) are LLM-dependent:** Tests run against live Ollama models. They cannot be run in CI without a live cluster. There is no mock or stub path for offline testing.

---

## Prioritized Recommendations

### P0 — Critical: Fix Before Next Iteration

**P0-1: Fix silent failure on recursion/pagination re-send (CC-6)**
- File: `services/rag-worker/pkg/pipeline/pipeline.go` lines 1848-1869
- Add `h.msg.SendError(ctx, req.Id, "Internal pipeline routing error", ...)` and return `dlq.TransientFailure` when Pulsar send fails during recursion or pagination.

**P0-2: Remove `raw_results` from inter-stage Pulsar messages (CC-1)**
- File: `services/rag-worker/pkg/pipeline/pipeline.go` line 504
- Do not store `allRawResults` in metadata. The exec stage already has `chunks`, `contexts`, and `plan_step_contexts` which are derived from raw results. Removing raw results eliminates multi-MB messages.

**P0-3: Fix `MergeTags` tag-loss bug in qdrant-adapter**
- File: `services/qdrant-adapter/internal/qdrant/client.go` lines 620-684
- The `payload["tags"] = []int64{targetTag}` overwrites all existing tags. Replace with a fetch-then-update loop or Qdrant's payload patch API to append rather than overwrite.

### P1 — High: Address in Next Iteration

**P1-1: Unify model name normalization (CC-3)**
- Create a canonical normalization function in the Python common library (or in `rag-ingestion/service.py`) and ensure it produces identical output to `contracts.NormalizeEmbeddingModelName` in Go. Add a round-trip test.

**P1-2: Make hydration HTTP timeout configurable**
- File: `services/rag-worker/pkg/pipeline/pipeline.go` line 130
- Add `HydrationTimeout` to config; use a separate `http.Client` for hydration calls with a longer timeout (e.g., 5 minutes).

**P1-3: Fix `HandleCompletion` UUID parse error handling**
- File: `services/db-adapter/internal/service/pulsar_processor.go` line 605
- Return `dlq.PermanentFailure` on UUID parse error, consistent with `HandlePrompt` and `HandleResponse`.

**P1-4: Add WebSocket stream timeout to config and send timeout error**
- File: `services/llm-gateway/internal/handlers/openai.go` line 421
- Replace `60 * time.Second` with `cfg.StreamTimeout`. On timeout, write a structured error JSON to the WebSocket before closing.

**P1-5: Fix rag-ingestion Pulsar client lifecycle**
- File: `services/rag-ingestion/service.py` lines 335-336
- Create the Pulsar client as a module-level singleton (thread-safe). Do not create and close one per ingest job.

**P1-6: Fix rag-ingestion DB/Qdrant atomicity gap**
- File: `services/rag-ingestion/service.py` lines 504-562
- Write PostgreSQL records only after receiving Pulsar send confirmation, or use a two-phase approach: write to DB with status `pending`, update to `completed` after Pulsar send succeeds.

**P1-7: Fix object-store-mgr HTTP scheme default**
- File: `services/object-store-mgr/cmd/manager/main.go` line 35
- Default to `https://` consistent with other services, or make the scheme configurable via env var.

**P1-8: Remove response body logging in rag-admin-api proxy**
- File: `services/rag-admin-api/internal/handlers/admin.go` lines 65-77
- Remove the `statusResponseWriter` buffer and the body logging. The proxy should be transparent.

**P1-9: Add circuit breaker or semaphore for Ollama calls (CC-4)**
- File: `services/rag-worker/internal/ollama/client.go`
- Add a `golang.org/x/sync/semaphore`-based concurrency limiter per model, configurable via env/config.

### P2 — Medium: Plan for Future Iterations

**P2-1: Replace `fmt.Printf` with `logging` in qdrant-adapter**
- File: `services/qdrant-adapter/internal/qdrant/client.go` lines 597, 603, 616
- Convert to `logging.Printf`.

**P2-2: Add unit tests for `handleIngress`, streaming exec path, and hydration error paths**
- File: `services/rag-worker/pkg/pipeline/pipeline_test.go`

**P2-3: Make WebSocket origin domain configurable**
- File: `services/llm-gateway/internal/handlers/openai.go` line 32
- Replace `.hierocracy.home` with env var.

**P2-4: Add request size limits to HTTP endpoints**
- Files: `services/llm-gateway/internal/handlers/openai.go` (line 182), `services/object-store-mgr/cmd/manager/main.go`
- Wrap `r.Body` with `http.MaxBytesReader`.

**P2-5: Add tests for object-store-mgr**
- File: `services/object-store-mgr/cmd/manager/main.go`
- No test files exist for this service.

**P2-6: Deduplicate `InsufficientContextPhrases` in granite31 config**
- File: `services/rag-worker/internal/models/granite31/model.go` lines 15-24
- Remove the duplicate `"i can't provide"` entry.

**P2-7: Add streaming E2E test for WebSocket path**
- File: `rag-stack/tests/`
- No E2E test exercises the WebSocket streaming endpoint.

**P2-8: Fix `aggregateChunks` timeout alignment with gateway**
- File: `services/prompt-aggregator/cmd/aggregator/main.go` line 172
- Make the 30s aggregation timeout configurable and align it with the gateway's stream timeout.

**P2-9: Fix context propagation in `HandleCompletion` and `aggregateChunks`**
- Files: `db-adapter/internal/service/pulsar_processor.go` lines 611-655, `prompt-aggregator/cmd/aggregator/main.go`
- Use `msgCtx` consistently in `HandleCompletion`. Pass the parent trace context into `aggregateChunks`.

**P2-10: Structured Protobuf fields for critical pipeline state (long-term)**
- Replace the most-used metadata keys (`sub_queries`, `action_type`, `planner_task`, `recursion_budget`, `recursion_count`, `chunk_offset`) with typed fields on `contracts.InternalRequest`. This eliminates `contracts.FromStruct`/`contracts.ToStruct` round-trips, enables schema validation, and makes the pipeline state auditable.

---

*Analysis produced from direct code reading of all service source files, test files, and integration tests as of commit 503e7e2 (2026-05-31).*

