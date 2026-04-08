# RAG Pipeline Explorer — Flutter UI Design Document

> **Purpose**: Specification for an AI coding agent to implement a Flutter desktop/web application
> that serves as the primary interface for interacting with, exploring, and managing the RAG pipeline
> services running on the `hierocracy.home` Kubernetes cluster.

---

## 1. Goals and Principles

### 1.1 Goals
- Provide a unified interface to interact with all RAG pipeline services (chat, ingestion, memory, storage).
- Enable model investigation and comparison as new pipeline features are added (e.g., iteration-7 memory/recall).
- Provide data maintenance interfaces for all backing stores: S3 (Rook-Ceph), TimescaleDB, and Qdrant.
- Be extensible — adding a new pipeline feature should only require adding a new sidebar tab and its widgets.

### 1.2 Principles
- **Sidebar-tabbed navigation**: Each functional area is isolated into its own tab. Tabs are independent and do not share transient state.
- **Configuration-driven**: API base URLs, model lists, and feature flags are loaded from a settings panel (persisted locally).
- **Responsive**: Primary target is Flutter Desktop (Linux). Flutter Web supported as secondary target. Layout adapts but sidebar is always visible.
- **Service-name routing**: All backend calls use `*.hierocracy.home` service names (e.g., `https://rag-admin-api.rag.hierocracy.home`), never raw IPs.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   Flutter Application                │
│                                                     │
│  ┌───────────┐  ┌─────────────────────────────────┐ │
│  │           │  │         Content Area             │ │
│  │  Sidebar  │  │  (renders active tab's page)     │ │
│  │  (Tabs)   │  │                                  │ │
│  │           │  │                                  │ │
│  │  • Chat   │  │                                  │ │
│  │  • Ingest │  │                                  │ │
│  │  • Memory │  │                                  │ │
│  │  • S3     │  │                                  │ │
│  │  • Timesc │  │                                  │ │
│  │  • Qdrant │  │                                  │ │
│  │  • Models │  │                                  │ │
│  │  • Observ │  │                                  │ │
│  │  • Config │  │                                  │ │
│  └───────────┘  └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
         │ (HTTPS / WebSockets)
         ▼
┌─────────────────────────────────────────────────────┐
│                  rag-admin-api                      │
│        (BFF / Aggregator for UI Operations)         │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│              Backend Services (K8s)                  │
│                                                     │
│  llm-gateway ─── rag-ingestion ─── object-store-mgr │
│  db-adapter ──── qdrant-adapter ── memory-controller │
│  (all via HTTPS at *.hierocracy.home)               │
└─────────────────────────────────────────────────────┘
```

### 2.1 State Management
- Use **Riverpod** (recommended) or **Bloc** for state management.
- Each tab has its own provider/state scope. Global state is limited to:
  - `AppConfig` (API URLs, TLS settings, selected theme).
  - `AuthState` (Network-level access for now; designed for future Key/OAuth integration).
  - `ServiceHealth` (Background health polling for all services).

### 2.2 Networking Layer
- Create a shared `ApiClient` class wrapping `package:dio` with:
  - Configurable base URL per service.
  - TLS certificate trust (custom CA from the cluster's `registry-ca-cm`).
  - Request/response logging toggle.
  - Timeout and retry policies.
  - OpenTelemetry trace-context header propagation (for distributed tracing).

### 2.3 Project Structure
```
lib/
├── main.dart
├── app.dart                    # MaterialApp, theme, sidebar scaffold
├── app_config_provider.dart    # Centralized configuration provider
├── config/
│   ├── app_config.dart         # Runtime config model
│   └── service_endpoints.dart  # Service URL constants/defaults
├── core/
│   ├── api_client.dart         # Dio wrapper with TLS, logging, tracing
│   ├── models/                 # Shared data models (contracts)
│   │   ├── prompt_message.dart
│   │   ├── response_message.dart
│   │   ├── memory_pack.dart
│   │   ├── memory_write_request.dart
│   │   ├── memory_retrieve_request.dart
│   │   └── db_op_message.dart
│   └── widgets/                # Reusable widgets (JSON viewer, data table, etc.)
├── features/
│   ├── chat/                   # Chat tab
│   ├── ingestion/              # Ingestion tab
│   ├── memory/                 # Memory Explorer tab
│   ├── s3_browser/             # S3 Data Maintenance tab
│   ├── timescale/              # TimescaleDB tab
│   ├── qdrant/                 # Qdrant tab
│   ├── models/                 # Model Comparison tab
│   ├── observability/          # Observability tab
│   └── settings/               # Settings/Config tab
└── providers/                  # Riverpod providers (global + per-feature)
```

---

## 3. Sidebar Tab Specifications

### 3.1 Chat Explorer
**Purpose**: Interactive chat interface for testing RAG pipeline responses with full control over model selection, tags, and memory mode.

**Backend Endpoints**:
- `POST /v1/chat/completions` — OpenAI-compatible chat (llm-gateway)
- `POST /v1/rag/chat` — Generic chat with planner/executor/tag selection (llm-gateway)

**UI Components**:
- **Session panel** (left sub-panel):
  - Session list (from TimescaleDB via db-adapter or direct query).
  - Create new session button.
  - Session metadata display (id, created_at, last_active_at).
- **Chat area** (center):
  - Message thread with role indicators (user/assistant/system).
  - Markdown rendering for assistant responses.
  - Code block syntax highlighting.
  - Streaming response display (WebSocket streaming from `llm-gateway`).
- **Configuration bar** (top of chat area):
  - Model selector dropdown: Planner model (e.g., `llama3.1`, `granite3.1-dense:8b`).
  - Model selector dropdown: Executor model.
  - Tag multi-select input (for RAG context isolation).
  - Memory mode toggle: `off` | `session` | `full`.
- **Response metadata panel** (collapsible right sub-panel): [IMPLEMENTED]
  - Token usage (prompt tokens, completion tokens).
  - Latency breakdown (Total, TTFT, etc.).
  - Model information (Planner, Executor).
  - Retrieved context snippets (from Qdrant) with source metadata.

**Data Flow**:
1. User composes message → Flutter sends `POST /v1/rag/chat` with `{ session_id, prompt, planner, executor, tags }`.
2. Gateway publishes to Pulsar; worker processes; result returns via gateway.
3. Flutter receives streaming updates via WebSocket from `llm-gateway`.
4. On response, display message and populate metadata panel.

---

### 3.2 Data Ingestion [IMPLEMENTED]
**Purpose**: Browse S3, upload documents, manage knowledge tags, and trigger ingestion.

**Backend Endpoints**:
- `POST /ingest` — Trigger ingestion (rag-ingestion service) via `rag-admin-api`
- `PUT /api/s3/buckets/{bucket}/objects/{key}` — Upload object via `object-store-mgr`

**UI Components**:
- **S3 Browser**: List objects in the configured default bucket (`rag-codebase-bucket`).
- **File/Folder Upload**: Multi-file selection and folder upload support with prefix targeting.
- **Knowledge Tags**: CRUD interface for tags (persisted in TimescaleDB).
- **Ingestion Control**: Set target prefix, assign tags, and trigger the pipeline.
- **Status Overlay**: Real-time feedback on upload and ingestion progress.

---

### 3.3 Memory Explorer (Iteration 7)
**Purpose**: Inspect, manage, and debug the memory system (short-term, long-term, persistent).

**Backend Endpoints**:
- `GET /api/memory/items` — List memory items with filters (via `memory-controller`)
- `GET /api/memory/items/{id}` — Get single memory item detail
- `PUT /api/memory/items/{id}` — Update memory item (pin/unpin, edit salience, set TTL)
- `DELETE /api/memory/items/{id}` — Soft-delete a memory item
- `GET /api/memory/events` — Audit log of memory write/retrieve/prune events
- `POST /api/memory/retrieve` — Test a `MemoryRetrieveRequest` and see the resulting `MemoryPack`

**Note**: The `memory-controller` service handles business logic for memory and utilizes the `db-adapter` for all underlying database operations.

**UI Components**:
- **Memory item table**: Sortable/filterable data table with columns:
  - ID, Type (short/long/persistent), Summary (truncated), Salience, Retention Score, Status, Pinned, Created, Updated.
- **Filter bar**: Filter by memory_type, scope (session/user/project), salience range slider, pinned-only toggle, status.
- **Detail panel**: On row click, show full memory item with:
  - Full content text.
  - Source references (linked messages, ingestion IDs).
  - Memory links (provenance chain).
  - Event history for this item.
- **Actions**: Pin/Unpin, Edit salience/retention hints, Set TTL/expiry, Delete.
- **Retrieve tester**: Form to compose a `MemoryRetrieveRequest` (query text, scope, filters, limits) and display the resulting `MemoryPack` with token budget visualization.
- **Memory statistics dashboard**:
  - Total items by type (pie/bar chart).
  - Salience distribution histogram.
  - Retention score distribution.
  - Prune rate over time.

---

### 3.4 S3 Object Browser
**Purpose**: Browse, upload, download, and delete objects in Rook-Ceph S3 buckets.

**Backend Endpoints** (new — requires `object-store-mgr` REST extensions):
- `GET /api/s3/buckets` — List buckets.
- `GET /api/s3/buckets/{bucket}/objects?prefix=&delimiter=` — List objects with prefix browsing.
- `GET /api/s3/buckets/{bucket}/objects/{key}` — Download/preview object.
- `PUT /api/s3/buckets/{bucket}/objects/{key}` — Upload object.
- `DELETE /api/s3/buckets/{bucket}/objects/{key}` — Delete object.
- `GET /api/s3/buckets/{bucket}/objects/{key}/metadata` — Object metadata (size, content-type, last-modified).

**UI Components**:
- **Bucket selector**: Dropdown listing all S3 buckets.
- **Object browser**: File-tree or table view with prefix-based navigation (folder-like UX).
  - Columns: Key, Size, Last Modified, Content-Type.
- **Preview panel**: For text/JSON/image objects, render inline preview.
- **Actions**: Upload file, Download, Delete (with confirmation), Copy key to clipboard.
- **Bucket statistics**: Object count, total size, storage class.

---

### 3.5 TimescaleDB Explorer
**Purpose**: Browse and manage data in the TimescaleDB relational store (sessions, prompts, responses, memory tables, audit logs).

**Backend Endpoints** (new — requires `db-adapter` REST extensions):
- `GET /api/db/tables` — List available tables.
- `GET /api/db/tables/{table}?limit=&offset=&sort=&filter=` — Paginated table browser.
- `GET /api/db/tables/{table}/{id}` — Single row detail.
- `DELETE /api/db/tables/{table}/{id}` — Delete row (with confirmation and audit).
- `GET /api/db/sessions` — List sessions with metadata.
- `GET /api/db/sessions/{id}/history` — Full chat history for a session.
- `DELETE /api/db/sessions/{id}` — Delete session and cascade.
- `GET /api/db/stats` — Table sizes, row counts, hypertable info.

**UI Components**:
- **Table navigator**: Sidebar or dropdown listing tables: `sessions`, `prompts`, `responses`, `memory_items`, `memory_links`, `memory_events`, `ingestion_records`, etc.
- **Data table view**: Paginated, sortable table with column-level filters.
  - Date columns render with human-friendly formatting.
  - JSON columns are expandable inline.
  - UUID columns are copyable.
- **Row detail panel**: Slide-out or modal with full row data, related records, and JSON fields pretty-printed.
- **Session browser**: Dedicated session list → click to see full chat history (prompts + responses interleaved by timestamp).
- **Bulk actions**: Multi-select rows for bulk delete (with confirmation dialog).
- **Stats dashboard**: Table sizes, row counts, hypertable chunk information.

---

### 3.6 Qdrant Vector Explorer
**Purpose**: Browse, search, and manage vector collections in Qdrant.

**Backend Endpoints** (MUST use `qdrant-adapter` REST extensions; direct Qdrant REST access is prohibited):
- `GET /api/qdrant/collections` — List collections (e.g., `vectors-384`, `vectors-4096`).
- `GET /api/qdrant/collections/{name}` — Collection info (point count, config, dimension).
- `POST /api/qdrant/collections/{name}/search` — Vector similarity search with filters.
- `GET /api/qdrant/collections/{name}/points/{id}` — Get point by ID.
- `POST /api/qdrant/collections/{name}/scroll` — Paginated point browsing with filter.
- `DELETE /api/qdrant/collections/{name}/points/{id}` — Delete point.
- `DELETE /api/qdrant/collections/{name}` — Delete collection (dangerous, requires double-confirm).

**UI Components**:
- **Collection selector**: Card or list view showing collections with:
  - Name, Vector dimension, Point count, Distance metric, Storage size.
- **Point browser**: Paginated table of points with:
  - ID, Payload preview (tags, source doc, chunk text), Vector magnitude.
  - Filter by tag_ids (UUID multi-select), payload fields.
- **Similarity search panel**:
  - Text input → generate embedding (via ingestion service) → search.
  - OR paste raw vector for direct search.
  - Results with score, highlighted payload, and vector distance.
- **Point detail**: Full payload JSON view, vector visualization (dimensionality-reduced 2D/3D scatter plot via t-SNE/UMAP — stretch goal).
- **Collection management**: Create collection, delete collection, optimize/compact.

---

### 3.7 Model Comparison Lab
**Purpose**: Side-by-side comparison of model responses for the same prompt to evaluate quality, latency, and token usage.

**Backend Endpoints**:
- `POST /v1/rag/chat` — Called once per model configuration being compared.

**UI Components**:
- **Comparison setup**:
  - Prompt input (shared across comparisons).
  - Tag selection (shared).
  - Add comparison slot (each slot has independent planner + executor selection).
  - Up to 4 slots (2x2 grid or scrollable row).
- **Execution**: "Run All" button fires parallel requests.
- **Results grid**: Each slot shows:
  - Model names (planner/executor).
  - Response text with markdown rendering.
  - Latency (ms).
  - Token counts.
  - Memory trace (if memory mode enabled).
- **History**: Save comparison results locally for later review.
- **Diff view**: Toggle a diff overlay between two selected responses.

---

### 3.8 Observability Dashboard
**Purpose**: Quick health check and link hub for deeper monitoring tools.

**Backend Endpoints**:
- Health endpoints: `/health` and `/readyz` on each service.
- Grafana link: `https://grafana.rag.hierocracy.home`

**UI Components**:
- **Service health grid**: Card per service showing:
  - Service name, status (healthy/degraded/down), last checked timestamp.
  - Background polling every 30 seconds.
- **Pulsar topic monitor**: Show topic names and basic stats (if Pulsar admin API is accessible).
- **Quick links**: Buttons to open Grafana dashboards, Headlamp, build orchestrator UI in external browser.
- **Recent errors**: If an error log endpoint is available, show last N errors across services.

---

### 3.9 Settings
**Purpose**: Configure API endpoints, TLS, theme, and feature flags.

**UI Components**:
- **Service endpoints**: Editable URL fields for each backend service:
  - llm-gateway: `https://llm-gateway.rag.hierocracy.home` (default)
  - rag-ingestion: `https://rag-ingestion.rag.hierocracy.home` (default)
  - object-store-mgr: `https://object-store-mgr.rag.hierocracy.home` (default)
  - db-adapter: `https://db-adapter.rag.hierocracy.home` (default)
  - qdrant-adapter: `https://qdrant-adapter.rag.hierocracy.home` (default)
  - memory-controller: `https://memory-controller.rag.hierocracy.home` (default)
  - Qdrant direct: `https://qdrant.rag.hierocracy.home` (default)
  - Grafana: `https://grafana.rag.hierocracy.home` (default)
- **TLS Configuration**:
  - CA certificate path or inline PEM (for trusting cluster's internal CA).
  - Toggle: Skip TLS verification (dev only, with warning).
- **Available models**: Editable list of known model names (pre-populated with `llama3.1`, `granite3.1-dense:8b`).
- **Feature flags**:
  - Enable/disable Memory Explorer tab (hidden if iteration-7 not deployed).
  - Enable/disable Model Comparison Lab.
- **Theme**: Light/Dark mode toggle.
- **Persistence**: All settings saved to local storage (`shared_preferences` on desktop, `localStorage` on web).
- **Connection test**: "Test All Connections" button that pings every configured endpoint.

---

## 4. Backend API Services Required

The Flutter UI relies on a set of REST APIs. A new `rag-admin-api` service will be created to act as the primary Backend-for-Frontend (BFF), aggregating data from specialized adapters.

### 4.1 `rag-admin-api` (New BFF Service)
**Purpose**: Primary entry point for the Flutter UI. Proxies and aggregates requests to specialized adapters.
- Implements the high-level API used by the Flutter tabs.
- Handles UI-specific aggregation (e.g., combining health stats).
- Future home for Authentication/Authorization logic.

### 4.2 `llm-gateway` — Streaming Support
| Method | Path | Description |
|--------|------|-------------|
| WS | `/v1/rag/chat/stream` | WebSocket for streaming chat responses |

### 4.3 `object-store-mgr` — S3 CRUD REST API
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/s3/buckets` | List all S3 buckets |
| GET | `/api/s3/buckets/{bucket}/objects` | List objects (with `prefix`, `delimiter`, `max_keys` query params) |
| GET | `/api/s3/buckets/{bucket}/objects/{key}` | Download object |
| PUT | `/api/s3/buckets/{bucket}/objects/{key}` | Upload object |
| DELETE | `/api/s3/buckets/{bucket}/objects/{key}` | Delete object |
| HEAD | `/api/s3/buckets/{bucket}/objects/{key}` | Object metadata |

### 4.4 `db-adapter` — REST Query API
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/db/tables` | List tables with row counts |
| GET | `/api/db/tables/{table}` | Paginated browse with sort/filter |
| GET | `/api/db/sessions` | List sessions |
| GET | `/api/db/sessions/{id}/history` | Full prompt/response history for session |
| DELETE | `/api/db/sessions/{id}` | Delete session (publishes DbOpMessage) |
| GET | `/api/db/stats` | Aggregate stats |

### 4.5 `qdrant-adapter` — REST Query/Management API
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/qdrant/collections` | List collections with metadata |
| GET | `/api/qdrant/collections/{name}` | Collection detail |
| POST | `/api/qdrant/collections/{name}/search` | Vector search with filters |
| POST | `/api/qdrant/collections/{name}/scroll` | Paginated point browsing |
| DELETE | `/api/qdrant/collections/{name}/points/{id}` | Delete point |

### 4.6 `memory-controller` (New Service)
**Note**: Utilizes `db-adapter` for database persistence.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/memory/items` | List/filter memory items |
| GET | `/api/memory/items/{id}` | Single memory item with links/events |
| PUT | `/api/memory/items/{id}` | Update (pin, salience, TTL) |
| DELETE | `/api/memory/items/{id}` | Soft-delete |
| GET | `/api/memory/events` | Audit log |
| POST | `/api/memory/retrieve` | Test MemoryRetrieveRequest → MemoryPack |
| GET | `/api/memory/stats` | Aggregate memory statistics |

---

## 5. Shared Data Models (Dart)

Generate Dart model classes from the existing JSON schema contracts in `rag-stack/contracts/`:

| Contract Schema | Dart Class | Used By Tabs |
|----------------|------------|--------------|
| `PromptMessage.schema.json` | `PromptMessage` | Chat, TimescaleDB |
| `ResponseMessage.schema.json` | `ResponseMessage` | Chat, TimescaleDB |
| `DbOpMessage.schema.json` | `DbOpMessage` | TimescaleDB |
| `MemoryPack.schema.json` | `MemoryPack` | Memory, Chat |
| `MemoryWriteRequest.schema.json` | `MemoryWriteRequest` | Memory |
| `MemoryRetrieveRequest.schema.json` | `MemoryRetrieveRequest` | Memory |

Use `json_serializable` + `freezed` for immutable models with JSON serialization.

---

## 6. Cross-Cutting Concerns

### 6.1 Error Handling
- All API calls wrapped in try/catch with user-friendly snackbar/toast notifications.
- Network errors show service name + status code + retry option.
- Distinguish between "service unreachable" (connection refused) and "service error" (5xx).

### 6.2 Loading States
- Every data-fetching widget uses a tri-state pattern: Loading → Data → Error.
- Use shimmer/skeleton placeholders during loading.

### 6.3 TLS Trust
- On Flutter Desktop (Linux): Load custom CA cert from file path configured in Settings.
- On Flutter Web: Relies on browser's trust store (user must import CA into browser or OS).
- Use `SecurityContext` with `setTrustedCertificates()` for `dart:io` HTTP clients.

### 6.4 Extensibility Pattern
To add a new tab for a future pipeline feature:
1. Create a new directory under `lib/features/<feature_name>/`.
2. Implement a page widget extending a common `TabPage` base.
3. Register the tab in `lib/app.dart`'s sidebar configuration list.
4. Optionally gate it behind a feature flag in Settings.

---

## 7. Technology Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Framework | Flutter 3.x | Web + Linux desktop targets |
| Language | Dart 3.x | Null-safe |
| State Management | Riverpod 2.x | Provider-based, testable |
| HTTP Client | Dio | Interceptors, TLS, logging |
| JSON Serialization | freezed + json_serializable | Code-gen from models |
| Routing | go_router | Declarative, deep-link capable |
| Charts | fl_chart | For memory stats, token budgets |
| Markdown | flutter_markdown | Chat response rendering |
| Code Highlighting | flutter_highlight | Code blocks in responses |
| Local Storage | shared_preferences | Settings persistence |
| Testing | flutter_test + mockito | Unit + widget tests |

---

## 8. Build and Deployment

### 8.1 Development
```bash
flutter create rag_explorer
cd rag_explorer
flutter run -d linux    # Desktop
flutter run -d chrome   # Web
```

### 8.2 Production Web Build
```bash
flutter build web --release
```
- Serve the `build/web/` output via a lightweight container (nginx or the existing `rag-web-ui` Go server).
- Deploy to the cluster with a Traefik `IngressRoute` at `https://rag-explorer.rag.hierocracy.home`.

### 8.3 Containerization
- **Initial Version**: `1.7.0` (aligned with Iteration 7).
- Build via the existing Kaniko pipeline (add `rag-explorer` to `build-all-on-cluster.sh`).
- Image pushed to `registry.hierocracy.home:5000/rag-explorer:<version>`.

### 8.4 Kubernetes Deployment
- Namespace: `rag-system` (alongside other RAG services).
- Node affinity: `role=storage-node` (no GPU needed).
- Service: ClusterIP on port 80.
- IngressRoute: `rag-explorer.rag.hierocracy.home` via Traefik.

---

## 9. Implementation Phases

### Phase 1 — Scaffold and Chat (MVP)
1. Flutter project setup (Linux Desktop focus) with sidebar scaffold and settings tab.
2. `ApiClient` with TLS support and service endpoint configuration.
3. `rag-admin-api` BFF service scaffold.
4. `llm-gateway` WebSocket streaming implementation.
5. Chat Explorer tab — basic send/receive via WebSocket.
6. Settings tab — endpoint configuration and connection testing.

### Phase 2 — Data Maintenance
7. Extend adapters (`object-store-mgr`, `db-adapter`, `qdrant-adapter`) with required REST APIs.
8. `rag-admin-api` integration with adapters.
9. S3 Object Browser tab.
10. TimescaleDB Explorer tab.
11. Qdrant Vector Explorer tab.

### Phase 3 — Memory and Models
12. `memory-controller` service implementation (utilizing `db-adapter`).
13. Memory Explorer tab.
14. Model Comparison Lab.

### Phase 4 — Observability and Polish
10. Observability dashboard.
11. Theming, responsive layout polish, keyboard shortcuts.
12. Automated tests (unit + widget).

---

## 10. Design Decisions (Resolved)

1. **Authentication**: Network-level access is sufficient for the initial release. The design must accommodate future API Key or OAuth2 integration.

2. **Streaming responses**: `llm-gateway` will be enhanced to support WebSocket streaming for chat responses.

3. **Direct Qdrant access**: Prohibited. All data store access must go through specialized adapters to ensure consistent tagging and filtering logic.

4. **Backend API architecture**: A new `rag-admin-api` service will be created to handle UI-specific logic and aggregate calls to backend adapters.

5. **Memory controller**: The `memory-controller` service will be implemented as part of Iteration 7 and will use `db-adapter` for all database interactions.

6. **Primary Target**: Flutter Desktop (Linux) is the primary target. Flutter Web is a secondary target.

7. **Existing Web UI**: The legacy `rag-web-ui` will be maintained as a lightweight web fallback.

8. **Versioning**: The service will start at version `1.7.0` to align with the current RAG stack iteration.