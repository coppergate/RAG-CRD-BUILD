# Model Recommendations — NVIDIA V100 32GB Upgrade

**Date:** 2026-06-19
**Context:** inference-0 GPU upgraded from NVIDIA P4 (8GB) to NVIDIA V100 (32GB HBM2)
**Status:** Recommendations — not yet implemented

---

## 1. Current Topology (Pre-Upgrade Baseline)

```
inference-0 (role=inference-node, now V100 32GB)
  ollama-llama3      GPU → ollama svc     → PLANNER_URL  (granite3.1-dense:8b, llama3.1)
  ollama-qwen32b     GPU → ollama-code svc → EXECUTOR_URL (qwen2.5:32b)
  ollama-embed-0     CPU → ollama-embed svc (all-minilm:l6-v2, nomic-embed-text)
  ollama-planner-cpu-0 CPU → ollama-planner-cpu svc (llama3.2:3b)

worker-0..3 (CPU pods per horizontal scale-out)
  ollama-embed-2..9       (all-minilm:l6-v2, nomic-embed-text)
  ollama-planner-cpu-2..5 (llama3.2:3b)
```

Both GPU pods (`ollama-llama3` and `ollama-qwen32b`) share the single V100 on inference-0.
`OLLAMA_MAX_LOADED_MODELS=2` and `OLLAMA_GPU_OVERHEAD=2GB` are already set in `values.yaml`.

**VRAM budget with qwen3:32b + granite3.1-dense:8b (recommended baseline):**

| Resident model | Approx VRAM (Q4_K_M) |
|---|---|
| qwen3:32b (executor) | ~19 GB |
| granite3.1-dense:8b (planner) | ~5 GB |
| 2× GPU overhead (2 GB each) | ~4 GB |
| KV cache (default ctx 4096, f16) | ~2 GB |
| **Total** | **~30 GB** ✅ comfortable |

---

## 2. What Changed — Why This Matters

On the P4 8GB, `qwen2.5:32b` (18–20 GB at Q4_K_M) physically could not fit in GPU VRAM.
Ollama was silently falling back to CPU+GPU offload, running the bulk of the model weights
in host RAM and paging layers to the GPU. This makes inference 4–8× slower than full-GPU
and was the primary cause of the 600s timeout failures observed with large executor calls.

The V100 32GB eliminates that constraint. Every model in the recommended stack below fits
fully in GPU memory. **Executor throughput will improve dramatically even with no model change.**

---

## 3. Executor Recommendation — `qwen3:32b` (replace `qwen2.5:32b`)

### Why Qwen3:32b

| Attribute | qwen2.5:32b (current) | qwen3:32b (recommended) |
|---|---|---|
| VRAM at Q4_K_M | ~19 GB | ~19 GB |
| Native context | 32K | 32K (128K with YaRN) |
| Instruction following (IFEval) | ~78 | ~88 |
| RAG hallucination rate | higher | 0.0117 (base), 0.006 w/ GraphRAG |
| Thinking/no-thinking mode | no | yes (`/no_think` prefix) |
| Ollama tag | `qwen2.5:32b` | `qwen3:32b` |

The quantization footprint is identical — this is a pure quality upgrade with no infrastructure
changes. Qwen3 is the successor to Qwen2.5 from Alibaba and is specifically tuned for:

- Instruction-constrained RAG (follows injected context without hallucinating)
- Structured output / tool calling (important for the planner pipeline)
- Dual-mode operation: add `/no_think` to system prompt to skip chain-of-thought for faster,
  simpler responses; omit it to enable reasoning steps for complex multi-chunk execution

**No-think mode is recommended for rag-worker's executor stage** where speed matters and the
planning has already been done. Enable thinking mode only if adding a critic/verifier phase.

### Ollama Config Change

No values.yaml changes needed. The model is seeded via `seed-models.sh` and
`push-models-to-cluster.sh`. Update the model names in those scripts and the rag-worker
deployment env var:

```yaml
# rag-worker k8s/deployment.yaml
- name: EXECUTOR_MODEL
  value: "qwen3:32b"       # was: qwen2.5:32b
```

For the no-think default, the executor prompt template in `values-qwen32b.yaml` (or the
`Modelfile` used during seeding) should include `/no_think` in the system prompt prefix to
get fast responses by default. Individual requests can override by including `/think` in the
user message.

---

## 4. Planner Recommendation — Keep `granite3.1-dense:8b` (with option to upgrade)

### Option A: Keep granite3.1-dense:8b (recommended for now)

**Reasoning:** Granite 3.1 8B is specifically tuned for instruction following and tool use
in agentic pipelines. It consistently performs well as a planner that emits structured
search plans. With the executor upgrade to qwen3:32b, the planner is not the bottleneck.
VRAM headroom improves significantly (5 GB vs. a larger planner).

### Option B: Upgrade to `qwen3:14b` (future iteration)

If longer, more complex planning chains are needed (deeper recursion, multi-step reasoning
before search), `qwen3:14b` (~8–9 GB Q4_K_M) is a viable upgrade with strong reasoning.

**Combined VRAM (Option B):**

| Model | VRAM |
|---|---|
| qwen3:32b (executor) | ~19 GB |
| qwen3:14b (planner) | ~8 GB |
| 2× overhead + KV cache | ~5 GB |
| **Total** | **~32 GB** ⚠️ at capacity |

This is technically feasible but leaves almost no headroom. Stick with granite3.1-dense:8b
until the executor upgrade has been validated under load.

---

## 5. Embedding Recommendations — CPU Additions

The CPU embedding pattern is solid and should continue. Current models:

| Model | Dims | Size | MTEB | Notes |
|---|---|---|---|---|
| all-minilm:l6-v2 | 384 | 46 MB | ~56 | Fast, small, low accuracy floor |
| nomic-embed-text | 768 | 274 MB | ~62 | Good general purpose |

### 5.1 Add `mxbai-embed-large` — Higher-Quality English Technical Embeddings

**Recommended addition for code and technical documentation RAG.**

| Attribute | Value |
|---|---|
| Parameters | 335M (BERT-large backbone) |
| Dimensions | 1024 |
| Disk size | ~670 MB |
| MTEB (English) | ~64.7 |
| Context length | 512 tokens |
| Language | English only |
| CPU perf (i9-13900K) | ~2,180 tok/s at batch=16 |

This model produces 1024-dim vectors, which are richer than nomic-embed-text (768-dim) for
code and technical prose retrieval. It will create a new Qdrant collection:
`vectors-mxbai-embed-large-1024`.

**Tradeoff:** 512 token context limit. For chunked code ingestion this is fine. For
long-document prose chunks, nomic-embed-text's longer context may be preferable.

### 5.2 Add `snowflake-arctic-embed2` — Premium Quality, Long Context

**Recommended if multilingual support or longer chunks are needed.**

| Attribute | Value |
|---|---|
| Parameters | 567M (multilingual BERT) |
| Dimensions | 1024 |
| Disk size | ~1.2 GB |
| MTEB | Beats text-embedding-3-large on MTEB |
| Context length | 8192 tokens |
| Language | Multilingual |
| MRL compression | Yes (can reduce dims at query time) |

This is the strongest open-source English embedding model available in Ollama as of mid-2026.
The 8192-token context makes it suitable for large document chunks without splitting.
Qdrant collection: `vectors-snowflake-arctic-embed2-1024`.

**Tradeoff:** 1.2 GB RAM per embed pod. With 10 embed pods (each holding 2 models already
at 320 MB), adding snowflake-arctic-embed2 pushes each pod's resident model size to ~1.5 GB.
Worker nodes have 3.5 GB available per embed pod — this fits.

### 5.3 Skip `BGE-M3` for Now

BGE-M3 supports hybrid dense+sparse retrieval (useful for keyword + semantic search), but
Qdrant's sparse vector support in the current pipeline is not wired up. BGE-M3 would add
1.2 GB per embed pod without leveraging its key differentiator. Defer until hybrid search
is in scope.

### Embedding Model Summary

| Priority | Model | Dims | Rationale |
|---|---|---|---|
| Keep | all-minilm:l6-v2 | 384 | Fast fallback; backward compat for existing collections |
| Keep | nomic-embed-text | 768 | Good general default; current production default |
| **Add** | **mxbai-embed-large** | **1024** | **Better technical/code retrieval; English focused** |
| Add later | snowflake-arctic-embed2 | 1024 | Best quality; add when long-chunk or multilingual needed |

---

## 6. V100-Specific Config Tuning

### 6.1 Increase `OLLAMA_NUM_CTX`

The current default is `4096` tokens (`OLLAMA_NUM_CTX=4096` in `values.yaml`). The V100 32GB
can comfortably support a larger context window without VRAM pressure:

- **Recommended:** `OLLAMA_NUM_CTX=8192` for both executor and planner GPU pods
- This allows the executor to process more RAG context chunks per call before hitting truncation
- KV cache at f16 for 8192 ctx: ~3–4 GB additional VRAM (still fits in budget)

If `snowflake-arctic-embed2` is added (8192-token chunk capacity), the executor must also
have at least 8192 ctx to process the injected context without truncation.

Update in `values.yaml` and `values-qwen32b.yaml`:
```yaml
extraEnv:
  - name: OLLAMA_NUM_CTX
    value: "8192"   # was: 4096
```

### 6.2 Flash Attention — V100 Compatibility

`OLLAMA_FLASH_ATTENTION=true` is set. The V100 (Volta GV100) supports Flash Attention v1
but NOT Flash Attention 2 (requires Ampere). Ollama's current implementation uses FA1 on
Volta hardware and falls back safely. This setting is safe to keep.

### 6.3 KV Cache Type — Keep `f16`

`OLLAMA_KV_CACHE_TYPE=f16` is the current setting. With 32GB VRAM, f16 KV cache is
preferable to q8_0 because:
- Better quality (no quantization on attention keys/values)
- V100 has high memory bandwidth (900 GB/s HBM2) so the larger f16 KV cache doesn't
  create bandwidth bottlenecks the way it might on consumer GPUs

Keep f16.

### 6.4 Parallelism — `OLLAMA_NUM_PARALLEL`

Currently `OLLAMA_NUM_PARALLEL=1` for GPU pods. The V100 can serve multiple concurrent
inference requests. However, both `ollama-llama3` and `ollama-qwen32b` share the single
V100, so increasing parallelism on one reduces throughput for the other.

Recommendation: **keep `OLLAMA_NUM_PARALLEL=1`** for GPU pods until the single-request
latency baseline is validated. Each pod gets half the GPU's compute budget at contention.

---

## 7. Updated Test Matrix

With the new models, the test matrix (`model_matrix.py`) should expand to:

| Embedding model | Dims | Planner | Executor |
|---|---|---|---|
| all-minilm:l6-v2 | 384 | granite3.1-dense:8b | qwen3:32b |
| all-minilm:l6-v2 | 384 | llama3.2:3b (CPU) | qwen3:32b |
| nomic-embed-text | 768 | granite3.1-dense:8b | qwen3:32b |
| nomic-embed-text | 768 | llama3.2:3b (CPU) | qwen3:32b |
| mxbai-embed-large | 1024 | granite3.1-dense:8b | qwen3:32b |
| mxbai-embed-large | 1024 | llama3.2:3b (CPU) | qwen3:32b |

Run the existing 8-case matrix with qwen3:32b as executor across all cases.
Add 2 new mxbai cases once that model is seeded.

---

## 8. Implementation Plan

### Phase 1 — Executor upgrade (low risk, immediate gain)

1. Add `qwen3:32b` to `push-models-to-cluster.sh` MODELS list
2. Push qwen3:32b to cluster registry: run `push-models-to-cluster.sh` on hierophant
3. Seed qwen3:32b into `ollama-qwen32b` PVC via `seed-models.sh` or manual exec
4. Update `EXECUTOR_MODEL` in `rag-worker/k8s/deployment.yaml` to `qwen3:32b`
5. Update rag-explorer model list constant `kAvailableModels` to include `qwen3:32b`
   (per `rag-explorer-iteration-10-changes.md` §3.5)
6. Build and deploy rag-worker
7. Run E2E test suite

### Phase 2 — Embedding addition: mxbai-embed-large

1. Add `mxbai-embed-large` to `push-models-to-cluster.sh` and `seed-models.sh`
2. Seed into all 10 embed pods (embed-0 through embed-9)
3. Update rag-explorer `kAvailableEmbeddingModels` constant to add `mxbai-embed-large`
4. Add 2 new test cases to `model_matrix.py` for 1024-dim collection
5. Run cross-model test suite with mxbai cases

### Phase 3 — Context window increase

1. Update `OLLAMA_NUM_CTX=8192` in `values.yaml` and `values-qwen32b.yaml`
2. Redeploy both GPU Ollama instances via Helm upgrade
3. Verify rag-worker pipeline can inject larger context (no truncation in logs)

### Phase 4 — Optional: snowflake-arctic-embed2

Defer until Phase 1–3 are stable and there is a specific use case for longer chunks or
multilingual content.

---

## 9. What Does NOT Change

- CPU embed infrastructure — worker-node pods continue unchanged
- Alt planner (llama3.2:3b) — stays on CPU, no changes
- Qdrant collection naming scheme — `vectors-{model}-{dims}` format continues
- Ingestion pipeline — embedding model is passed per-request, no changes needed beyond
  seeding the new model
- Pulsar embed fanout — works for any model passed in the EmbedJob payload

---

## 10. Sources

- [Ollama LLM Benchmark on NVIDIA V100](https://www.databasemart.com/blog/ollama-gpu-benchmark-v100)
- [Best Ollama Models: 12 Models Ranked — June 2026](https://www.morphllm.com/best-ollama-models)
- [Best Ollama Embedding Models 2026: 7 Benchmarked by MTEB Score](https://www.morphllm.com/ollama-embedding-models)
- [Qwen3 GPU Requirements Guide](https://willitrunai.com/blog/qwen-3-gpu-requirements)
- [DeepSeek R1 32B vs Qwen3 32B Comparison](https://llm-stats.com/models/compare/deepseek-r1-vs-qwen3-32b)
- [Best Embedding Models for RAG in 2026](https://innovativeais.com/blog/best-embedding-models-for-rag-in-2026)
- [Home GPU LLM Leaderboard by VRAM Tier](https://awesomeagents.ai/leaderboards/home-gpu-llm-leaderboard/)
- [Run Qwen3 Locally with Ollama](https://localaimaster.com/blog/qwen-3-local-setup-guide)
- [Qwen3 Technical Report](https://arxiv.org/pdf/2505.09388)
