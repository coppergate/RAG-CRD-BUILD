## Iteration 10a: Service Reliability Fixes and Test Coverage Hardening

### Objective

Address the remaining P1 code bugs identified in ANALYSIS.md, fill the object-store-mgr test gap, and investigate the llama3.1 E2E timeout failures before starting the larger Iteration 10 model-aware embedding work.

### Why This Iteration Exists

The ANALYSIS.md code review found several P1 bugs that create real failure modes in production — a wrong HTTP scheme default, a Pulsar resource leak, an atomicity gap in ingestion, and a sensitive data leak in the admin proxy. These should be resolved before layering the more complex Iteration 10 retrieval changes on top of them. Iteration 10a is a reliability pass with no new user-facing features.

---

### Work Items (Priority Order)

#### 1. Branch and session setup

Verify the new `work-YYYY-MM-DD` branch from main exists. Add a changelog initialization entry.

---

#### 2. P1-7 — Fix object-store-mgr HTTP scheme default (one-line bug)

**File:** `rag-stack/services/object-store-mgr/cmd/manager/main.go` line ~35

**Problem:** `object-store-mgr` defaults to `http://` for its S3 endpoint. Every other service (`rag-ingestion`, `llm-gateway`) defaults to `https://`. In production the Ceph endpoint requires HTTPS, so the object-store-mgr will fail to connect unless the operator explicitly sets the full `https://` URL in the env var.

**Fix:** Change the default scheme to `https://` or derive it from the `OBJECT_STORE_ENDPOINT` env var if it already contains a scheme.

**Test:** Verify the existing `go vet` and any new unit test passes. No deploy required for a scheme default fix alone.

---

#### 3. P1-8 — Remove response body logging in rag-admin-api proxy

**File:** `rag-stack/services/rag-admin-api/internal/handlers/admin.go`

**Problem:** The proxy handler logs the full response body for proxied requests. This leaks potentially sensitive content (LLM responses, file contents, session data) into structured logs that flow to Loki.

**Fix:** Remove or redact the response body from proxy log lines. Keep status code and latency logging.

**Test:** `go vet` + existing handler tests.

---

#### 4. P1-5 — Fix rag-ingestion Pulsar client lifecycle

**File:** `rag-stack/services/rag-ingestion/service.py`

**Problem:** The Pulsar client and producer are not closed on exit/error paths. Under repeated restarts or error conditions this leaks connections and may cause the broker to reject new connections from the same client ID.

**Fix:** Wrap producer and client usage in try/finally blocks (or a context manager) to ensure `producer.close()` and `client.close()` are always called.

**Test:** Code review to confirm all exit paths are covered.

---

#### 5. P1-6 — Fix rag-ingestion DB/Qdrant atomicity gap

**File:** `rag-stack/services/rag-ingestion/service.py`

**Problem:** Ingestion writes a record to TimescaleDB first, then upserts into Qdrant. If the Qdrant upsert fails, the DB record exists but no vector is stored. Subsequent re-ingestion may skip the file because the DB record shows it as ingested.

**Fix:** Either reverse the order (write Qdrant first, then DB) or add a status field that only transitions to `complete` after both writes succeed. On failure, delete the DB record or leave it in a `pending` state that re-ingestion will retry.

**Test:** Review the retry logic to confirm re-ingestion correctly handles partial state.

---

#### 6. P2-5 — Make object-store-mgr testable and add unit tests

**File:** `rag-stack/services/object-store-mgr/cmd/manager/main.go`

**Problem:** All HTTP handlers are anonymous closures registered directly in `main()`. There is no way to instantiate them in a test without running the full binary. This service has zero test coverage.

**Fix:**
1. Extract handlers into a `buildMux(client S3Client, bucket string, maxBytes int64) *http.ServeMux` factory function.
2. Define a `S3Client` interface covering the methods the handlers call.
3. Write unit tests using `httptest.NewRecorder` and a mock `S3Client`:
   - upload success path
   - upload exceeds size limit → 413
   - upload with missing bucket → 400/500
   - list objects success
   - delete object success

**Test:** `go test ./cmd/manager/...` passes.

---

#### 7. Investigate llama3.1 E2E timeout failures

**Observed in E2E run (2026-06-02):**
- `llama3.1:latest__llama3.1:latest` — pipeline progressed through all stages but final response was not received within the 600s gateway read timeout.
- `llama3.1:latest__granite3.1-dense:8b` — pipeline stalled after PLANNING_TASK; RETRIEVING_CONTEXT and EXECUTING_TASK were never observed.

**Granite combinations passed fully.**

**Investigate:**
1. Check `rag-worker` logs for the llama3.1 planner requests that stalled — are they timing out in Ollama, or is the search stage blocking?
2. Check whether the WebSocket stream timeout (P1-4, hardcoded in llm-gateway) is being hit before the 600s gateway timeout.
3. Determine if this is a model speed issue (llama3.1 simply slower than granite on this hardware) or a regression.

**Fix if a bug:**
- If WebSocket timeout is the root cause, address P1-4: make `REQUEST_TIMEOUT` in llm-gateway configurable and increase it for llama3.1.
- If Ollama is hanging indefinitely, add a circuit breaker or per-call timeout (P1-9 partial).

---

### Exit Criteria

Iteration 10a is complete when:

- P1-7 (HTTP scheme) is fixed and deployed.
- P1-8 (response body logging) is removed.
- P1-5 and P1-6 (rag-ingestion reliability) are addressed.
- object-store-mgr has unit test coverage with an extracted handler factory.
- The llama3.1 E2E timeout root cause is identified and either fixed or documented as a known hardware limitation.
- All unit tests pass (`run-tests.sh --unit-only`).
- A full E2E run (`run-tests.sh`) is clean or any remaining failures are documented and understood.
- Changes are committed, PR'd, and merged to main.

### Non-Goals

- No new user-facing features.
- No changes to embedding model selection, vector store naming, or retrieval logic — that is Iteration 10.
- No changes to the model shape ConfigMap system introduced in the current iteration.
