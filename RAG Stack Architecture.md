Based on the current implementation of the RAG stack (Iteration 5), here is a graphical representation of the components, the build process, and the asynchronous message interconnections via the Pulsar bus.

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
    UI & Gateway & Worker & DBAdapter & QAdapter & OSMgr -->|Metrics/Traces| OTel
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

*   **`rag-web-ui`**: The front-end service providing pages for **Data Ingestion** and **Interactive Chat**. It triggers ingestion via REST and interacts with the `llm-gateway`.
*   **`llm-gateway`**: Acts as an OpenAI-compatible entry point. It publishes user prompts to the Pulsar bus and waits for results asynchronously.
*   **`rag-worker`**: The core processing unit. It consumes tasks, initiates async vector searches via the `qdrant-adapter`, generates context, and calls Ollama for the final LLM response.
*   **`qdrant-adapter`**: A dedicated service that centralizes all Qdrant database access. It listens to the `qdrant-ops` topic and publishes results to `qdrant-ops-results`, supporting horizontal scaling via Pulsar shared subscriptions.
*   **`db-adapter`**: A dedicated service for data persistence. It listens to all chat-related topics (`chat-prompts`, `chat-responses`) and administrative operations (`db-ops`) to keep TimescaleDB in sync.
*   **`object-store-mgr`**: Manages S3 operations and metadata for the RAG stack.
*   **`build-orchestrator`**: A cluster-native service that listens to build requests on Pulsar and orchestrates **Kaniko** jobs to build container images within the cluster.
*   **`common/telemetry`**: A shared Go library used by all services to initialize OpenTelemetry (OTLP) metrics and distributed tracing.
*   **Pulsar Bus**: Divided into `data` and `operations` namespaces to segregate application traffic from system management tasks.
*   **TimescaleDB**: Stores session metadata, chat history (split into `prompts` and `responses`), and ingestion tracking.
*   **APM Stack**: Includes Loki (logs), Mimir (metrics), Tempo (traces), and Grafana for visualization. Grafana Alloy collects Kubernetes logs, while the OpenTelemetry Collector receives application telemetry.

#### 3. Build & Deployment Flow

```mermaid
flowchart TD
    subgraph "Phase 1: Bootstrap (Cluster-Native)"
        Repo[Local Source] --> Pack[tar source]
        Pack --> Upload[S3 Upload Pod]
        Upload --> S3[(Build S3/OBC)]
        S3 --> BootstrapJob[Kaniko Bootstrap Job]
        BootstrapJob --> Registry[Local Registry: 172.20.1.26:5000]
        Registry --> OrchDeploy[Deploy Build Orchestrator]
    end

    subgraph "Phase 2: RAG Service Builds (Cluster-Native)"
        Trigger[trigger-build.sh] --> S3_2[(Build S3/OBC)]
        Trigger -.->|Pulsar Msg| Orch[Build Orchestrator]
        Orch --> Kaniko[Kaniko K8s Job]
        S3_2 --> Kaniko
        Kaniko --> Registry
    end

    Registry --> K8s[Kubernetes Cluster]
    
    subgraph "Orchestration"
        Setup[setup-complete.sh]
    end
    
    Setup --> Phase1
    Setup --> Phase2
    Phase2 --> Deploy[Deploy RAG Services]
```

*   **Zero-Host Build Architecture**: The entire stack, including the `build-orchestrator` itself, is now built using cluster-native tools (Kaniko). The `hierophant` host performs only lightweight source packaging (`tar`) and orchestration (`kubectl`/`pulsar-client`).
*   **Kaniko & S3**: Source code is packaged and uploaded to a dedicated S3 bucket (OBC) in the `build-pipeline` namespace. Kaniko pods download these tarballs to build images, avoiding the need for a local Docker/Podman daemon.
*   **Orchestration**: The master script `setup-complete.sh` ensures that the build infrastructure is bootstrapped first, then triggers builds for all services, and finally deploys the RAG stack once images are verified in the registry.