# RAG Stack Service Interfaces

This document details the HTTP endpoints and Pulsar topics for all services in the RAG stack (v2.6.1).

## 1. LLM Gateway (`llm-gateway`)
The entry point for all LLM and RAG requests. It provides an OpenAI-compatible API and handles session management.

### HTTP Endpoints
- **POST `/v1/chat/completions`**
  - **Description**: OpenAI-compatible chat completions endpoint.
  - **Parameters**: 
    - `model`: (String) The model to use.
    - `messages`: (Array) List of role/content messages.
    - `session_id`: (String, Optional) ID for session tracking.
    - `tags`: (Array, Optional) Tags for RAG context isolation.
- **POST `/v1/rag/chat`**
  - **Description**: Generic RAG chat endpoint.
  - **Parameters**:
    - `prompt`: (String) The user prompt.
    - `session_id`: (String) UUID for the session.
    - `planner`: (String) Planner model.
    - `executor`: (String) Executor model.
    - `tags`: (Array) List of tags to filter context.
- **GET `/v1/rag/chat/stream`** (Websocket)
  - **Description**: Streaming chat over Websocket.
- **GET `/healthz`, `/readyz`, `/health`**
  - **Description**: Standard health and readiness probes.

### Pulsar Topics
- **Publish**: `persistent://rag-pipeline/stage/ingress` (Request start)
- **Publish**: `persistent://rag-pipeline/data/chat-prompts` (Prompt audit)
- **Subscribe**: `persistent://rag-pipeline/stage/results` (Final results)

---

## 2. DB Adapter (`db-adapter`)
Asynchronous persistence layer for database operations (TimescaleDB).

### HTTP Endpoints
- **GET `/sessions`**
  - **Description**: List all chat sessions.
- **GET `/sessions/{id}/messages`**
  - **Description**: Retrieve messages for a specific session.
- **GET/POST `/tags`**
  - **Description**: List or create context tags.
- **DELETE `/tags/{id}`**
  - **Description**: Delete a context tag.
- **GET `/stats`**
  - **Description**: Database statistics (counts for sessions, prompts, responses).
- **GET `/healthz`, `/readyz`, `/health`**
  - **Description**: Standard health and readiness probes.

### Pulsar Topics
- **Subscribe**: `persistent://rag-pipeline/operations/db-ops` (Generic DB operations)
- **Subscribe**: `persistent://rag-pipeline/data/chat-prompts` (Audit prompts)
- **Subscribe**: `persistent://rag-pipeline/stage/results` (Audit responses)

---

## 3. Qdrant Adapter (`qdrant-adapter`)
Interface for the Qdrant Vector Database, handling filtered searches and upserts.

### HTTP Endpoints
- **GET `/collections`**
  - **Description**: List all vector collections.
- **GET `/collections/{name}`**
  - **Description**: Get details for a specific collection.
- **GET `/healthz`, `/readyz`, `/health`**
  - **Description**: Standard health and readiness probes.

### Pulsar Topics
- **Subscribe**: `persistent://rag-pipeline/operations/qdrant-ops` (Search/Upsert operations)
- **Publish**: `persistent://rag-pipeline/operations/qdrant-ops-results` (Results of search)

---

## 4. RAG Worker (`rag-worker`)
Core orchestration engine for the multi-stage RAG pipeline.

### Pulsar Topics
- **Subscribe**: `persistent://rag-pipeline/stage/ingress`
- **Subscribe**: `persistent://rag-pipeline/stage/plan`
- **Subscribe**: `persistent://rag-pipeline/stage/search`
- **Subscribe**: `persistent://rag-pipeline/stage/exec`
- **Subscribe**: `persistent://rag-pipeline/operations/qdrant-ops-results`
- **Publish**: `persistent://rag-pipeline/stage/plan`
- **Publish**: `persistent://rag-pipeline/stage/search`
- **Publish**: `persistent://rag-pipeline/stage/exec`
- **Publish**: `persistent://rag-pipeline/operations/qdrant-ops`
- **Publish**: `persistent://rag-pipeline/stage/completion`
- **Publish**: `persistent://rag-pipeline/sessions/{uuid}` (Streaming chunks)

---

## 5. RAG Ingestion (`rag-ingestion`)
Python service for document processing and embedding.

### HTTP Endpoints
- **POST `/ingest`**
  - **Description**: Process a file from S3 and generate embeddings.
  - **Parameters**: JSON payload with `bucket`, `key`, and `tags`.
- **GET `/health`, `/healthz`, `/readyz`**
  - **Description**: Health and readiness checks.

### Pulsar Topics
- **Publish**: `persistent://rag-pipeline/operations/qdrant-ops` (Upsert embeddings)

---

## 6. Object Store Manager (`object-store-mgr`)
Proxy and management interface for Rook-Ceph S3 storage.

### HTTP Endpoints
- **GET `/buckets`**
  - **Description**: List all S3 buckets.
- **GET `/buckets/{name}`**
  - **Description**: List objects in a bucket.
- **GET/PUT/DELETE `/buckets/{name}/{key}`**
  - **Description**: Object operations.
- **GET `/healthz`, `/readyz`**

---

## 7. Memory Controller (`memory-controller`)
Management of structured memory items and session links.

### HTTP Endpoints
- **GET/POST `/items`**
  - **Description**: List or create memory items.
- **GET `/sessions`**
  - **Description**: List sessions with associated memory items.
- **GET `/healthz`, `/readyz`**

---

## 8. Prompt Aggregator (`prompt-aggregator`)
Aggregates streaming chunks into final responses.

### HTTP Endpoints
- **GET `/healthz`, `/readyz`**

### Pulsar Topics
- **Subscribe**: `persistent://rag-pipeline/stage/completion` (Completion signal)
- **Read**: `persistent://rag-pipeline/sessions/{uuid}` (Reads session history)
- **Publish**: `persistent://rag-pipeline/stage/results` (Final aggregated result)

---

## 9. RAG Admin API (`rag-admin-api`)
Management portal proxy and health aggregator.

### HTTP Endpoints
- **GET `/api/health/all`**
  - **Description**: Aggregated health status of all RAG services.
- **Proxies**:
  - `/api/s3/` -> `object-store-mgr`
  - `/api/db/` -> `db-adapter`
  - `/api/qdrant/` -> `qdrant-adapter`
  - `/api/memory/` -> `memory-controller`
  - `/api/chat/` -> `llm-gateway`
  - `/api/ingest/` -> `rag-ingestion`
  - `/api/grafana/` -> Grafana internal URL

---

## 10. Build Orchestrator (`build-orchestrator`)
Manages in-cluster Kaniko build jobs.

### HTTP Endpoints
- **GET `/status`**
  - **Description**: Current build pipeline status.
- **GET `/events`**
  - **Description**: Server-Sent Events (SSE) for build progress.

### Pulsar Topics
- **Subscribe**: `persistent://rag-pipeline/operations/builds` (Build requests)

---

## 11. RAG Web UI (`rag-web-ui`)
Legacy front-end for data ingestion and interactive chat.

### HTTP Endpoints
- **GET `/`**
  - **Description**: Main ingestion management page.
- **GET `/chat`**
  - **Description**: Interactive chat interface page.
- **GET `/sessions`**
  - **Description**: List chat sessions (via `db-adapter`).
- **GET `/history`**
  - **Description**: Get message history for a session.
- **POST `/ask`**
  - **Description**: Send a prompt to the RAG pipeline.
- **POST `/upload`**
  - **Description**: Upload a file to S3.
- **POST `/trigger-ingest`**
  - **Description**: Trigger ingestion for a file.
- **POST `/create-tag`**
  - **Description**: Create a new context tag.
- **POST `/delete-data`**
  - **Description**: Delete a document and its embeddings.
- **GET `/healthz`, `/readyz`**
