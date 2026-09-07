# Replace the Ollama-native LLM client with a single OpenAI-protocol client

## Context

`inference-0` is being rebuilt as a dual-V100 32GB node serving a 27B model
under 1Cat-vLLM (`kubernetes-setup/new-setup-external-gpu/VLLM-DUAL-V100-PLAN.md`).
**vLLM does not speak the Ollama API.** Phase 7 of that plan is the client-side
gap, and it is called out there as the largest non-GPU risk.

`rag-worker` currently talks Ollama-native routes only —
`internal/ollama/client.go` uses `/api/chat` (l.120, l.174), `/api/embeddings`
(l.271) and `/api/tags` (l.305). None of those exist in vLLM.

**The key enabling fact:** Ollama also serves an OpenAI-compatible `/v1` surface,
and the mirrored image is `ollama/ollama:0.15.6` — far past the versions that
added `/v1/chat/completions`, `/v1/embeddings` and `/v1/models`. So one
OpenAI-protocol client can drive *both* the existing Ollama pods and the future
vLLM deployment.

That makes a clean replacement possible rather than a second parallel client:

- Only **one** protocol in the codebase, no `EXECUTOR_BACKEND` switch to reason about.
- The refactor is **provable today against the running Ollama pods**, before vLLM
  exists at all. It de-risks Phase 7 without waiting on Phases 0–6.
- Cutting the executor over to vLLM later becomes a **pure deployment change** —
  set `EXECUTOR_URL` and `EXECUTOR_MODEL`, no code, no rebuild.

Scope is the executor role's *protocol*. Planner (`granite3.1-dense:8b`) and
embeddings (`ollama-embed-*` CPU pods) stay on Ollama **servers**; they just get
talked to over `/v1` instead of `/api`. `rag-ingestion` and the Python tests are
untouched — they only call embedding-side routes.

## The seam already exists

`internal/models/registry.go:12` already declares
`Backend string // "ollama", "openai", etc.` with a `RegisterBackend` factory
map (l.52), and `cmd/worker/main.go:127` registers exactly one backend today.
`internal/models/interfaces.go:9` defines the narrow `ChatClient` contract —
`Chat`, `ChatStream`, `GetEmbeddings`. Nothing above the client passes sampling
options, so the new client has the same surface. **No interface changes needed.**

`pkg/pipeline/metrics.go:151` extracts metrics via a *structural* type assertion
(`interface{ GetMetrics() *contracts.ExecutionMetrics }`), so any response type
implementing that method works with no change.

## Work

### 1. New `services/rag-worker/internal/openai/client.go`

Package `openai` (matches the vocabulary already in `registry.go:12`). Mirrors
the existing client's shape: `semaphore.Weighted` for concurrency,
`tlsutil.NewHTTPClient` (`services/common/tlsutil`) selected on the `https://`
URL prefix, `logging.Printf` one-line call summaries.

| Method | Route | Notes |
|---|---|---|
| `Chat` | `POST /v1/chat/completions` | `stream:false` → `choices[0].message.content` |
| `ChatStream` | `POST /v1/chat/completions` | `stream:true` + `stream_options:{include_usage:true}`; SSE |
| `GetEmbeddings` | `POST /v1/embeddings` | `input` (not `prompt`) → `data[0].embedding` |
| `Ping` | `GET /v1/models` | |

SSE parsing is new — there is no client-side SSE reader in the repo to reuse.
Strip the `data: ` prefix, ignore comment/blank lines, terminate on
`data: [DONE]`, and emit `choices[0].delta.content`. Use `bufio.Scanner` with an
enlarged buffer rather than the 64 KiB default.

Drop `keep_alive: -1` — not expressible in the OpenAI protocol, and **already
redundant**: `OLLAMA_KEEP_ALIVE="-1"` is set server-side in all four values files
(`infrastructure/ollama/values.yaml`, `values-qwen32b.yaml`, `values-embed.yaml`,
`values-planner-cpu.yaml`). No behaviour change.

### 2. Error classification

`pkg/pipeline` classifies failures in 5 places via `ollama.IsMissingModelError`
(`search.go:236`, `pipeline.go:250,672,725,745`) and
`ollama.IsUnsupportedEmbeddingModelError` (`search.go:239`). Port
`APIStatusError` and both classifiers into the new package unchanged in spirit,
with one addition: OpenAI errors arrive as
`{"error":{"message":...,"type":...}}` (Ollama) or `{"object":"error","message":...}`
(vLLM), so unwrap the envelope and classify on the inner message before the
existing substring match. 404 → missing model holds on both backends.

### 3. Metrics mapping — **a real, deliberate loss**

OpenAI responses carry a `usage` block but **none of Ollama's nanosecond timing
fields**. `contracts.ExecutionMetrics` mapping becomes:

| Field | Source |
|---|---|
| `PromptTokens`, `CompletionTokens` | `usage` |
| `TotalDurationUsec` | client wall-clock |
| `PromptEvalDurationUsec` | time-to-first-token (streaming); `0` non-streaming |
| `EvalDurationUsec` | first→last token (streaming); total (non-streaming) |
| `TokensPerSecond` | `completion_tokens` / eval seconds |
| **`LoadDurationUsec`** | **`0` — no OpenAI equivalent** |

`LoadDurationUsec` is unrecoverable over this protocol and feeds the
`model_execution_metrics` hypertable (OPERATIONS.md §8.1). Any Grafana panel on
model load duration will flatline for all models, not just the executor. Calling
this out rather than hiding it; it is the one genuine cost of the replacement.
If usage is absent (older streaming servers ignoring `include_usage`), leave
token counts at `0` rather than fabricating estimates.

Also extend `mapMetrics` (`pkg/pipeline/metrics.go:157-163`) with a `qwen` case
— it currently only attributes `llama` and `granite`, so the new executor would
land with an empty `ModelFamily`.

### 4. Health checks — a latent bug to fix while here

`cmd/worker/main.go:79,90` assert the concrete type
`client.(*ollama.OllamaClient)` and **return `nil` (pass) for anything else**. A
non-Ollama client would silently report healthy. Replace with a
`interface{ Ping() error }` assertion. Keep the existing check keys
(`ollama-planner`, `ollama-executor`) unless nothing consumes the strings —
`rag-admin-api /api/health/all` aggregates them and dashboards may key on them;
verify before renaming.

### 5. Delete `internal/ollama/`

Per guidelines, copy the originals to
`/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/ai-changes/original/` first
(one file per path, latest only).

### 6. Mechanical follow-ons

- `cmd/worker/main.go`: `RegisterBackend("openai", …)`; the four `ModelSpec`
  literals (l.145-178) become `Backend: "openai"`; swap the import.
- `pkg/pipeline/{search.go,pipeline.go}`: import + 6 classifier call sites.
- `pkg/pipeline/{pipeline_test.go,chunking_test.go}`: 3 `ollama.APIStatusError`
  literals (`chunking_test.go:147`, `pipeline_test.go:298,535`).
- `internal/config/config.go`: `OllamaMaxConcurrency` → `LLMMaxConcurrency`,
  reading `LLM_MAX_CONCURRENCY` with `OLLAMA_MAX_CONCURRENCY` retained as
  fallback. Endpoint/model defaults stay pointed at Ollama.
- `internal/openai/client_test.go`: port the 4 existing classifier tests, add
  `httptest` coverage for non-streaming chat, SSE streaming incl. `[DONE]` and
  usage-bearing final chunk, embeddings, the error envelope, and metrics mapping.
- `services/rag-worker/k8s/deployment.yaml`: no functional change; add a
  commented vLLM cutover block (`EXECUTOR_URL`, `EXECUTOR_MODEL`) next to the
  existing executor env so Phase 8 step 4 is self-documenting.

### 7. Docs

Add an OPERATIONS.md section recording that rag-worker speaks OpenAI protocol to
both Ollama and vLLM, the `/v1` route map, the `LoadDurationUsec` loss, and that
executor cutover is env-only. Guidelines require documenting any procedure that
needed project scanning to determine.

## Verification

Ordered so each step is provable before the next.

1. **Static** — mandatory per OPERATIONS.md §3.1:
   ```bash
   cd rag-stack/services/rag-worker && go vet ./...
   cd /mnt/hegemon-share/share/code/complete-build && ./vet-all.sh
   ```
2. **Unit** — the new SSE/metrics tests plus the existing pipeline suites that
   assert on classifier behaviour:
   ```bash
   cd rag-stack/services/rag-worker && go test ./...
   ```
3. **Confirm Ollama's `/v1` surface live**, before trusting anything else. This
   is the step that proves the whole approach without vLLM:
   ```bash
   ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
     "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
      /home/k8s/kube/kubectl run v1probe --rm -i --restart=Never \
        --image=registry.container-registry.svc.cluster.local:5000/curlimages/curl \
        --overrides='{\"spec\":{\"nodeSelector\":{\"role\":\"storage-node\"}}}' -- \
        sh -c 'curl -s http://ollama-embed.llms-ollama.svc.cluster.local:11434/v1/models; \
               curl -s http://ollama-embed.llms-ollama.svc.cluster.local:11434/v1/embeddings \
                 -H \"Content-Type: application/json\" \
                 -d \"{\\\"model\\\":\\\"all-minilm:l6-v2\\\",\\\"input\\\":\\\"ping\\\"}\" | head -c 200'"
   ```
   If `/v1/embeddings` is missing on 0.15.6, the embedding path stays on `/api`
   and only chat moves — I'll report that and adjust rather than push through.
4. **Cluster build**, then confirm pods are on the new version and healthy per
   OPERATIONS.md §7.0.1 before testing:
   ```bash
   ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
     "cd /mnt/hegemon-share/share/code/complete-build && \
      bash ./rag-stack/build.sh --service rag-worker --wait"
   ```
5. **Full suite** — unit then E2E, both must pass (§7.0):
   ```bash
   ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
     "bash /mnt/hegemon-share/share/code/complete-build/rag-stack/tests/run-tests.sh"
   ```
   E2E is the real proof: it checks timestamped "secret codes" round-trip
   through retrieval + inference, so a broken stream or embedding path fails loudly.
6. **Log scan** (§7.3, mandatory — "Complete" is not sufficient): check
   `/tmp/rag-logs/` for `[ERROR]`, `Failed to export`, `stale timestamp`.
7. **Metrics regression check** — confirm `model_execution_metrics` still
   receives rows with sane `prompt_tokens` / `completion_tokens` /
   `tokens_per_second`, and that `load_duration_usec` is `0` as predicted rather
   than breaking the insert.

Rollback is `git revert` plus a rebuild; no cluster state changes.

## Session hygiene

Today is 2026-09-07 and the branch is `work-2026-08-22`, so per guidelines:
create `work-2026-09-07`, commit with timestamp messages and the
`Accomplished with a little help from my AI buddies` trailer, leave the modified
`CURRENT_VERSION` uncommitted, and add a changelog entry at session end.

## Out of scope

- `rag-ingestion/service.py` and `rag-stack/tests/*.py` — embedding-side only
  (`/api/embeddings`, `/api/show`, `/api/tags`) against CPU Ollama pods that are
  not moving.
- Planner migration to vLLM (open question #6 in the plan doc, unresolved).
- Phases 0–6 and 8: hardware verification, GPU-operator label cleanup, image
  build, model seeding, the `llms-vllm` Deployment, cutover.
