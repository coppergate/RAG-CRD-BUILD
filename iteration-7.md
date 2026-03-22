## Iteration 6: Local Prompt Memory + Recall (Miras/Titans-Inspired)

### Objective
Implement a local-first memory and recall pipeline that improves long-session consistency, recall accuracy, and context efficiency without requiring immediate model retraining.

### Scope
- Add application-layer memory orchestration to the existing RAG stack.
- Implement surprise/salience scoring, retention/decay, and multi-memory retrieval composition.
- Keep inference model-agnostic (Ollama-compatible) while preparing an optional path for future test-time memory adaptation.

### Non-Goals (Iteration 6)
- Full custom model training for Titans/Miras architectures.
- Replacing the current core LLM inference runtime.
- Cross-cluster federation of memory state.

### Phase 1: Memory Data Model and Contracts
- Define canonical memory types:
  - `short_term_memory` (session-local, recent turns)
  - `long_term_memory` (durable semantic memory)
  - `persistent_memory` (task/user profile and durable preferences)
- Extend schema in TimescaleDB:
  - `memory_items` (id, tenant/session/user scope, type, text summary, salience, retention_score, decay_state, created_at, updated_at)
  - `memory_links` (source message ids, ingestion ids, tags)
  - `memory_events` (write/update/prune/audit trail)
- Define worker-facing JSON contracts:
  - `MemoryWriteRequest`
  - `MemoryRetrieveRequest`
  - `MemoryPack` (assembled context slices delivered to generation)

### Phase 1A: Exact Files to Implement First
1. Create SQL migration file:
   - `rag-stack/infrastructure/timescaledb/iteration-6-phase1-memory.sql`
   - Includes:
     - `memory_items` table (scope, salience, retention, decay, status, pinning, ttl fields)
     - `memory_links` table (provenance + correction linkage)
     - `memory_events` table (write/retrieve/prune audit)
     - `updated_at` trigger function + trigger
     - Indexes for scope lookup, rank ordering, expiry scans, metadata/source/event queries
2. Add contract schemas:
   - `rag-stack/contracts/MemoryWriteRequest.schema.json`
   - `rag-stack/contracts/MemoryRetrieveRequest.schema.json`
   - `rag-stack/contracts/MemoryPack.schema.json`
3. Add shared Go interface types for service integration:
   - `rag-stack/services/common/memory/contracts.go`
   - Contains `MemoryWriteRequest`, `MemoryRetrieveRequest`, `MemoryPack`, and supporting scoped/source/token-budget types

### Phase 1B: Integration Sequence (first implementation pass)
1. Apply base schema then phase-1 memory migration:
   - `rag-stack/infrastructure/timescaledb/schema.sql`
   - `rag-stack/infrastructure/timescaledb/iteration-6-phase1-memory.sql`
2. Wire `db-adapter` to consume `MemoryWriteRequest` and persist:
   - upsert `memory_items`
   - insert `memory_links`
   - append `memory_events` (`write` / `score_update`)
3. Wire `rag-worker` retrieval request/response path:
   - produce `MemoryRetrieveRequest`
   - consume and apply returned `MemoryPack` in prompt assembly (token-capped, ranked)
4. Add contract validation tests in `rag-stack/tests/test_contracts.py` for the 3 new schemas

### Phase 2: Surprise/Salience and Retention Logic
- Implement salience scoring from runtime signals:
  - novelty vs recent context
  - explicit user emphasis ("remember this", corrections, constraints)
  - retrieval utility feedback (was memory used in successful answers)
- Implement retention gate policy:
  - soft decay over time/turns
  - hard prune thresholds for stale low-value entries
  - pinned/protected memory rules for high-priority items
- Persist periodic retention updates with deterministic pruning jobs.

### Phase 3: Retrieval Composition in RAG Worker
- Add memory retrieval path before final prompt assembly:
  - fetch top short-term snippets (recency-weighted)
  - fetch long-term semantic memories from Qdrant (tag/session filtered)
  - fetch persistent profile constraints
- Build `MemoryPack` with strict token budgeting:
  - reserve token bands per memory type
  - deduplicate overlapping snippets
  - prioritize higher salience under budget pressure
- Add guardrails:
  - avoid conflicting memories (prefer newest verified correction)
  - avoid unsafe carry-forward of outdated instructions

### Phase 4: Services, Topics, and API Integration
- Add or extend a `memory-controller` service (Go preferred for stack consistency).
- Pulsar topics:
  - `rag.memory.write`
  - `rag.memory.refresh`
  - `rag.memory.prune`
  - `rag.memory.audit`
- Gateway integration:
  - annotate requests with memory scope metadata (session/user/tag)
  - optional flags: `memory_mode=off|session|full`
- UI integration:
  - memory trace panel (what was recalled and why)
  - controls to pin/delete memory entries

### Phase 5: Observability, Evaluation, and Safety
- Metrics:
  - recall hit rate
  - answer correction carry-over rate
  - token overhead from memory pack
  - prune rate and retained-memory half-life
- Tracing/logging:
  - correlate each answer to memory ids included
  - log memory write/prune reasons for auditability
- Evaluation harness:
  - multi-turn recall tests (facts, preferences, constraints)
  - contradiction tests (new correction should override stale memory)
  - long-context stress tests (latency + quality)

### Phase 6: Kubernetes Rollout Plan
- Deploy memory controller to worker/storage nodes (`role=storage-node`).
- Keep GPU inference nodes focused on inference-only workloads.
- Rollout strategy:
  - stage 1: dark launch (`memory_mode=session`) on test traffic
  - stage 2: enable `memory_mode=full` for selected tags/projects
  - stage 3: general availability after SLO validation

### Deliverables
- New `memory-controller` service (or equivalent worker modules).
- DB migrations for memory tables and retention fields.
- Qdrant indexing/query updates for memory collections.
- Prompt assembly updates in `rag-worker` using `MemoryPack`.
- UI memory trace and management controls.
- Integration tests + benchmark report.

### Exit Criteria
- >= 20% improvement in multi-turn recall benchmark over Iteration 5 baseline.
- No > 10% p95 latency regression at current concurrency target.
- Deterministic pruning verified by replay tests.
- Full audit trail for memory write/retrieve/prune actions.

### Risks and Mitigations
- Memory bloat: enforce TTL + hard caps + scheduled pruning.
- Incorrect memory carryover: correction-precedence rules + conflict resolution.
- Token inflation: strict per-band memory token budget.
- Operational complexity: start with session memory, then expand to full mode.

### Stretch Goal (Post-Iteration 6)
Prototype a model-level memory module with test-time adaptation (Titans-style) behind an experimental flag, using the same memory contracts and evaluation harness.
