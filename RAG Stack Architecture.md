Based on the current implementation of the RAG stack (Iteration 6 planning + Iteration 5 runtime), here is a refreshed architecture representation of components, build flow, and asynchronous interconnections.

#### 1. Architecture & Message Interconnections (Mermaid Diagram)

```mermaid
graph TD
    subgraph "External Clients"
        Browser[Web Browser]
        DevDB[Dev Database Tools]
    end

    subgraph "Kubernetes: rag-system namespace"
        UI[rag-web-ui]
        Gateway[llm-gateway]
        Worker[rag-worker]
        DBAdapter[db-adapter]
        Ingestor[rag-ingestion-service]
        QAdapter[qdrant-adapter]
        OSMgr[object-store-mgr]
        MemCtl[memory-controller]
    end

    subgraph "Kubernetes: monitoring namespace (APM)"
        Alloy[Grafana Alloy]
        OTel[OTel Collector]
        Loki[Loki - Logs]
        Mimir[Mimir - Metrics]
        Tempo[Tempo - Traces]
        Grafana[Grafana Dashboards]
    end

    subgraph "Kubernetes: build-pipeline namespace"
        Orch[Build Orchestrator]
        Kaniko[Kaniko Builder]
        BuildS3[(Build S3/OBC)]
    end

    subgraph "Pulsar Message Bus (rag-pipeline namespace)"
        direction LR
        Tasks[data/llm-tasks]
        Results[data/llm-results]
        Prompts[data/chat-prompts]
        Responses[data/chat-responses]
        Ops[operations/db-ops]
        QOps[operations/qdrant-ops]
        QRes[operations/qdrant-ops-results]
        BuildTopic[operations/builds]
        MWrite[operations/memory-write]
        MRetrieve[operations/memory-retrieve]
        MPack[operations/memory-pack]
        MAudit[operations/memory-audit]
    end

    subgraph "Storage & Infrastructure"
        S3[(Rook-Ceph S3)]
        Qdrant[(Qdrant Vector DB)]
        TDB[(TimescaleDB)]
        Ollama[Ollama LLM Service]
    end

    %% Interaction Flows
    Browser <-->|HTTP/80| UI
    Browser -->|HTTP/80| Gateway

    %% Ingestion Flow
    UI -->|Upload| S3
    UI -->|Trigger| Ingestor
    Ingestor -->|Store Metadata| TDB
    Ingestor -.->|1. Publish| QOps
    QAdapter -.->|2. Consume| QOps
    QAdapter -->|3. Upsert| Qdrant
    Ingestor -->|Read Files| S3
    Ingestor -->|Embeddings| Ollama

    %% Chat Flow (Asynchronous)
    Gateway -.->|1. Publish| Prompts
    Gateway -.->|2. Publish| Tasks

    Tasks -.->|3. Consume| Worker
    Worker -.->|4. Search Op| QOps
    QOps -.->|5. Consume| QAdapter
    QAdapter -->|6. HTTP| Qdrant
    QAdapter -.->|7. Publish| QRes
    QRes -.->|8. Consume| Worker

    %% Memory Flow (Iteration 6)
    Worker -.->|A. Publish| MRetrieve
    MRetrieve -.->|B. Consume| MemCtl
    MemCtl -->|C. Read/Rank| TDB
    MemCtl -.->|D. Optional semantic recall| QOps
    MemCtl -.->|E. Publish| MPack
    MPack -.->|F. Consume| Worker
    Worker -.->|G. Publish| MWrite
    MWrite -.->|H. Consume| MemCtl
    MemCtl -->|I. Persist memory state| TDB
    MemCtl -.->|J. Publish audit| MAudit

    Worker -->|9. Inference| Ollama
    Worker -.->|10. Publish| Responses
    Worker -.->|10. Publish| Results

    Results -.->|11. Consume| Gateway
    Gateway -->|12. HTTP Response| Browser

    %% Persistent Flow (DB Adapter)
    Prompts -.->|Consume| DBAdapter
    Responses -.->|Consume| DBAdapter
    Ops -.->|Consume| DBAdapter
    DBAdapter -->|Persist| TDB

    %% Observability Flow
    UI & Gateway & Worker & DBAdapter & QAdapter & OSMgr & MemCtl -->|Metrics/Traces| OTel
    Alloy -->|Kubernetes Logs| Loki
    OTel --> Mimir
    OTel --> Tempo
    Mimir & Loki & Tempo --> Grafana

    %% Build Pipeline Flow
    Orch -.->|Listen| BuildTopic
    Orch -->|Trigger Job| Kaniko
    Kaniko -->|Download Source| BuildS3
    Kaniko -->|Push Image| Registry[Local Registry]
```

#### 2. Component Descriptions

- `rag-web-ui`: Front-end for data ingestion and interactive chat.
- `llm-gateway`: OpenAI-compatible entry point; publishes prompts/tasks and returns final async response.
- `rag-worker`: Core orchestration engine for retrieval + generation, now requesting/synthesizing memory packs.
- `memory-controller`: New Iteration 6 service for memory write/retrieve orchestration, ranking, retention updates, and audit events.
- `qdrant-adapter`: Centralized vector DB adapter consuming `qdrant-ops` and returning `qdrant-ops-results`.
- `db-adapter`: Persists prompts/responses and db operations into TimescaleDB.
- `object-store-mgr`: S3 metadata and object lifecycle manager.
- `build-orchestrator`: Cluster-native Kaniko build dispatcher.
- `common/telemetry`: Shared OTLP/tracing initialization package used by Go services.
- Pulsar bus: Segregated `data` and `operations` topics, extended with memory topics.
- TimescaleDB: Session/chat state plus Iteration 6 memory model (`memory_items`, `memory_links`, `memory_events`).
- APM stack: Loki, Mimir, Tempo, Grafana, and Alloy.

#### 3. Build & Deployment Flow

```mermaid
flowchart TD
    subgraph "Phase 1: Bootstrap (Cluster-Native)"
        Repo[Local Source] --> Pack[tar source]
        Pack --> Upload[S3 Upload Pod]
        Upload --> S3[(Build S3/OBC)]
        S3 --> BootstrapJob[Kaniko Bootstrap Job]
        BootstrapJob --> Registry[Local Registry: registry.hierocracy.home:5000]
        Registry --> OrchDeploy[Deploy Build Orchestrator]
    end

    subgraph "Phase 2: RAG Service Builds (Cluster-Native)"
        Trigger[trigger-build.sh] --> S3_2[(Build S3/OBC)]
        Trigger -.->|Pulsar Msg| Orch[Build Orchestrator]
        Orch --> Kaniko[Kaniko K8s Job]
        S3_2 --> Kaniko
        Kaniko --> Registry
    end

    subgraph "Phase 3: Iteration 6 Memory Enablement"
        Migrate[Apply TimescaleDB memory migration] --> MemDeploy[Deploy memory-controller]
        MemDeploy --> TopicInit[Create memory topics]
        TopicInit --> WorkerWire[Wire rag-worker memory request/pack path]
        WorkerWire --> GatewayFlags[Enable memory_mode flags in gateway]
        GatewayFlags --> Eval[Run recall/latency benchmarks]
    end

    Registry --> K8s[Kubernetes Cluster]

    subgraph "Orchestration"
        Setup[setup-complete.sh]
    end

    Setup --> Phase1
    Setup --> Phase2
    Setup --> Deploy[Deploy RAG Services]
    Deploy --> Phase3
```

- Zero-host build architecture remains unchanged: source packaging + in-cluster Kaniko builds.
- Iteration 6 adds a memory enablement deployment phase after core service deployment.
