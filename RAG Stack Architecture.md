Based on the current implementation of the RAG stack (Iteration 4), here is a graphical representation of the components, the build process, and the asynchronous message interconnections via the Pulsar bus.

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

    %% External DB Access
    DevDB -->|LoadBalancer| TDB

    %% Operations Flow (Deprecated - logic moved to adapters)
    %% Worker -.->|Operations| QOps
    %% QOps -.->|Consume| Worker
    %% Worker -.->|Results| QRes
```

#### 2. Component Descriptions

*   **`rag-web-ui`**: The front-end service providing pages for **Data Ingestion** and **Interactive Chat**. It triggers ingestion via REST and interacts with the `llm-gateway`.
*   **`llm-gateway`**: Acts as an OpenAI-compatible entry point. It publishes user prompts to the Pulsar bus and waits for results asynchronously.
*   **`rag-worker`**: The core processing unit. It consumes tasks, initiates async vector searches via the `qdrant-adapter`, generates context, and calls Ollama for the final LLM response.
*   **`qdrant-adapter`**: A dedicated service that centralizes all Qdrant database access. It listens to the `qdrant-ops` topic and publishes results to `qdrant-ops-results`, supporting horizontal scaling via Pulsar shared subscriptions.
*   **`db-adapter`**: A dedicated service for data persistence. It listens to all chat-related topics (`chat-prompts`, `chat-responses`) and administrative operations (`db-ops`) to keep TimescaleDB in sync.
*   **Pulsar Bus**: Divided into `data` and `operations` namespaces to segregate application traffic from system management tasks.
*   **TimescaleDB**: Stores session metadata, chat history (split into `prompts` and `responses`), and ingestion tracking.

#### 3. Build & Deployment Flow

```mermaid
flowchart LR
    Repo[Git Repo / Source] --> BuildScript[build-and-push.sh]
    BuildScript --> Podman[Podman Build]
    
    subgraph "Docker Build Stage"
        GoSum[go.sum Sync] --> GoMod[go mod download]
        GoMod --> Build[go build]
    end

    Podman --> Registry[Local Registry: 172.20.1.26:5000]
    Registry --> K8s[Kubernetes Cluster]
    
    subgraph "Deployment"
        Setup[setup-all.sh]
    end
    
    Setup --> K8s
    Update --> K8s
```

*   **Continuous Integration**: The `build-and-push.sh` script runs on the `hierophant` host, using Podman to create "thick" images and OCI artifacts for Ollama models.
*   **Registry**: Images are stored in a local, insecure registry reachable by all cluster nodes.
*   **Deployment**: Automated scripts (`setup-all.sh`) handle the creation of Namespaces, ConfigMaps (including source-code mounting for debugging), Secrets, and the rollouts of the microservices.