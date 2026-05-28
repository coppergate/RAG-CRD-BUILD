## Iteration 10: Model-Aware Embeddings and On-Demand Context Hydration

### Objective
Make retrieval correct when embedding models vary across ingestion and prompting. The system must track which embedding model created each vector store, resolve the correct model at prompt time, and hydrate missing context embeddings on demand when the source text exists but the vector store does not.

### Why This Iteration Exists
Today, the stack assumes a single embedding model path in practice even though planning and execution models are already selectable per prompt. That creates two failure modes:

1. Vector stores are created without a durable embedding-model label, so retrieval cannot reliably tell which store belongs to which embedding model.
2. Prompt-time retrieval uses the wrong model identity for embeddings, which can produce mismatched vectors and poor or incorrect context lookup.

Iteration 10 fixes both problems and adds a recovery path:

- label every embedding store by model,
- keep planning and execution models separate from embedding models,
- and if the needed embeddings are missing but the tagged source text exists, generate the embeddings on the fly and continue retrieval.

### Core Requirement
The prompt path must not fail simply because a vector store has not been prebuilt for the requested embedding model.

If the system can still reach the underlying context by tag, session, or path, it should:

1. resolve the embedding model,
2. fetch the raw source context,
3. generate embeddings with the correct model,
4. persist them in the correct model-specific store,
5. and then retry retrieval.

### What Must Be True After This Iteration

1. Every embedding record has a durable model identity.
2. Every Qdrant collection or vector store is namespaced by embedding model, not just by vector size.
3. Prompt-time retrieval uses an embedding model resolved from context, not the planner model by default.
4. Missing embeddings are a recoverable runtime condition when the underlying source text is available.
5. The system can explain which embedding model was used to retrieve or hydrate a given response.

### Non-Goals

- Replacing the current planner or executor model selection UI.
- Changing the user-facing chat flow for choosing generation models.
- Rewriting the vector store backend.
- Building a generic multi-model ensemble retriever in this iteration.
- Automatically re-embedding every historical corpus before the new runtime path exists.

### Current Weaknesses To Fix

1. Ingestion writes vectors with no explicit embedding-model label.
2. Retrieval assumes the selected planning model can stand in for the embedding model.
3. Collection naming only reflects vector size, which is not enough to prevent collisions.
4. The system has no runtime hydration fallback when the requested model-specific context store is missing.
5. Existing corpus and prompt metadata do not carry enough provenance to determine which embedding model should be used.

### Required Behavioral Change

The prompt path must follow this order:

1. Determine the relevant context scope from the prompt, tags, session, or corpus selection.
2. Resolve the correct embedding model for that context scope.
3. Look for the model-specific vector store.
4. If the store or the required vectors are missing, hydrate them from source text.
5. Retry retrieval against the hydrated store.
6. Pass the retrieved context into planning and execution as usual.

### Embedding Model Resolution Rules

Embedding model selection must be explicit and deterministic.

Preferred precedence:

1. An explicit embedding model attached to the request.
2. A corpus or tag-scoped embedding model mapping from stored metadata.
3. A project or session default embedding model.
4. A service default embedding model.

The planner model and executor model must not be used as a fallback for retrieval embeddings unless the system explicitly documents that mapping.

### Store Identity Rules

Vector stores must be identified by embedding model and vector size together.

Recommended identity shape:

- `embedding_model`
- `vector_size`

Recommended collection naming:

- a canonical collection prefix,
- plus the embedding model identity,
- plus the vector size.

This prevents collisions when two embedding models share the same vector dimension.

### Hydration Path Requirements

The on-demand hydration path is a first-class retrieval feature. It must support:

1. Tag-scoped hydration.
2. Session-scoped hydration.
3. Path-scoped hydration where source files are known.
4. Bucket or corpus scoped hydration when the prompt references a known ingestion source.
5. Safe retry after hydration completes.

Hydration must be bounded:

- do not hydrate if the source context cannot be identified,
- do not hydrate if the request has no usable scope,
- do not silently mix vectors from different embedding models in the same store.

### Required Data Contracts

The contracts layer must carry enough information to preserve embedding provenance end to end.

At minimum, the request and operation contracts need to represent:

- embedding model,
- vector size,
- store or collection identity,
- source scope,
- and hydration status or intent.

### Required Metadata

Embedding metadata should persist:

- the embedding model name,
- the vector size,
- the source path or source identifier,
- tag or session scope,
- a source content hash or equivalent version marker,
- and the creation timestamp.

This metadata is required so the system can answer:

- what created this vector,
- where it came from,
- and whether it belongs in the current retrieval path.

### Service Impact

#### 1. `rag-ingestion`

Responsibilities:

- Produce embeddings with an explicit embedding-model identity.
- Store that model identity in the database and in Qdrant payloads.
- Write collection names using the embedding model plus size.
- Preserve enough source metadata to support later hydration.

Required changes:

- add an embedding-model field to the ingestion configuration and/or request payload,
- label each stored vector with that model,
- persist provenance metadata for each chunk,
- emit model-aware collection creation and upsert operations,
- keep the raw source scope queryable by tag, session, and path.

#### 2. `rag-worker`

Responsibilities:

- Resolve the correct embedding model for retrieval.
- Detect when the needed context vectors are missing.
- Hydrate missing context from source text when possible.
- Retry retrieval after hydration.
- Keep planner and executor model selection separate from embedding model selection.

Required changes:

- add an embedding-model resolver,
- add a missing-context hydration pipeline,
- update search flow to use the resolved embedding model,
- add fan-out behavior if a prompt spans multiple embedding-model-backed corpora,
- attach retrieval provenance to metadata and traces.

#### 3. `qdrant-adapter`

Responsibilities:

- Treat collections as model-specific stores.
- Create, search, upsert, and delete using the embedding-model identity.
- Expose collection identity clearly in stats and list responses.

Required changes:

- make collection naming model-aware,
- avoid assuming vector size alone is enough to locate a collection,
- expose model metadata in stats endpoints,
- support hydration workflows cleanly when collections do not yet exist.

#### 4. `db-adapter`

Responsibilities:

- Provide the source records needed for hydration.
- Expose embedding provenance in vector/file queries.
- Preserve model identity during merge and reingest flows.

Required changes:

- return embedding model fields in storage/vector endpoints,
- support filtering by embedding model where useful,
- update maintenance flows so reingestion does not default to an unlabeled collection,
- keep raw source context available for prompt-side hydration.

#### 5. `llm-gateway`

Responsibilities:

- Pass through embedding-model hints when they are known.
- Preserve enough prompt/session metadata for worker-side resolution.

Required changes:

- add an embedding-model field or metadata entry to the internal request path,
- derive or attach the context scope that the worker will need for hydration,
- stop treating planner/executor selection as sufficient for retrieval embeddings.

#### 6. `common/contracts`

Responsibilities:

- Carry the new embedding identity through the pipeline.

Required changes:

- extend the internal request and Qdrant operation contracts,
- keep the generated protobufs and any mirrored bindings in sync,
- avoid overloading planner or executor fields with retrieval embedding semantics.

#### 7. `common/ent/schema`

Responsibilities:

- Persist embedding provenance in the database.

Required changes:

- add embedding-model fields to the embedding schema,
- add any supporting source-hash or hydration-status fields needed by the runtime path,
- migrate existing storage without losing historical vectors.

#### 8. `rag-explorer`

Responsibilities:

- Surface the new model-aware state when useful for debugging or administration.

Required changes:

- optionally show the active embedding model for a corpus or response,
- optionally expose hydration status in inspection views,
- do not block the backend work on UI additions.

### Prompt-Time Control Flow

The desired flow for a prompt request is:

1. User selects planning model and execution model as before.
2. System resolves the embedding model for the relevant context scope.
3. Worker attempts retrieval against the model-specific vector store.
4. If the store is absent or incomplete, worker asks the database for the source text associated with the selected tags/session/path.
5. Worker generates the missing embeddings with the resolved embedding model.
6. Worker writes the hydrated vectors into the correct model-specific collection.
7. Worker retries retrieval and continues the existing planning/execution pipeline.

### Hydration Guardrails

Hydration must obey these constraints:

- Do not hydrate if there is no trustworthy source scope.
- Do not hydrate if the source text cannot be unambiguously mapped to the requested tags, session, or path.
- Do not write hydrated vectors into a generic store that mixes embedding models.
- Do not substitute the planner model for the embedding model unless the request explicitly says that is the intended mapping.

### Migration And Backfill Strategy

The new runtime path must coexist with existing unlabeled stores.

Required migration behavior:

1. Existing stores should be classified with a best-effort model label where possible.
2. Unlabeled stores should be treated as legacy and never silently mixed with model-labeled stores.
3. The system should be able to rehydrate or reindex legacy context into the new model-aware layout.
4. Backfill should be safe to run incrementally, not only as a full rebuild.

### Observability Requirements

The system should be able to answer:

- which embedding model was used for a given prompt,
- whether the prompt used an existing store or hydrated missing context,
- how many vectors were generated on demand,
- and whether retrieval failed because source text was missing or because the embedding model was unresolved.

Recommended metrics:

- hydration attempts,
- hydration successes,
- hydration failures,
- prompt-time retrieval misses,
- model-specific collection counts,
- and retrieval latency before and after hydration.

### Test Requirements

The implementation must add tests for:

1. Ingestion stores the embedding model in metadata and schema fields.
2. Retrieval uses the resolved embedding model instead of the planner model by default.
3. Collection naming includes model identity and does not collide on size alone.
4. Hydration triggers when a store is missing but source text exists.
5. Hydration does not trigger when no usable source scope exists.
6. The worker retries retrieval after hydration and continues the prompt pipeline.
7. Legacy unlabeled stores remain readable during the migration period.

### Recommended Implementation Phases

#### Phase 1: Contract and schema changes

- Add embedding-model fields to the contracts.
- Add embedding-model provenance to the embedding schema.
- Update generated bindings and any mirrored request structures.

#### Phase 2: Model-aware ingestion

- Write model identity during ingestion.
- Name stores by model and size.
- Preserve source provenance for rehydration.

#### Phase 3: Retrieval model resolution

- Stop using the planner model as the retrieval embedding default.
- Resolve the embedding model from request, tag, or corpus metadata.
- Search the correct model-specific store.

#### Phase 4: Hydration fallback

- Detect missing embeddings at prompt time.
- Query the source context by tag/session/path.
- Embed on the fly and persist into the correct store.
- Retry retrieval.

#### Phase 5: Legacy handling and backfill

- Classify existing stores.
- Rehydrate or reindex old context.
- Keep the migration safe and incremental.

### Exit Criteria

Iteration 10 is complete when:

- embedding vectors are labeled by model at ingest time,
- prompt-time retrieval resolves the correct embedding model,
- missing context can be hydrated from source text on demand,
- model-specific stores do not collide across different embedding models,
- and the system can prove which model was used for a given retrieval path.

### Implementation Notes

The important design shift is that retrieval is no longer a passive lookup against a prebuilt store. It is a model-aware workflow with recovery behavior.

The prompt path must be able to do three things:

1. find the right embeddings if they already exist,
2. build them if the source exists but the vectors do not,
3. and fail only when both the source and the vectors are unavailable.

That is the behavior this iteration should enforce.
