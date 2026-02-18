### Executive Summary: Production-Grade Organized RAG Architecture (v3)

This project implements a high-performance, scalable **Retrieval-Augmented Generation (RAG)** system optimized for local Kubernetes environments. The architecture has evolved into a fully organized, tag-aware, and event-driven ecosystem that prioritizes data traceability, resource efficiency, and operational speed.

#### 1. Core Architecture & Services

The system utilizes a modular "micro-services" approach, combining **Go** for high-concurrency infrastructure and **FastAPI (Python)** for specialized data ingestion.

*   **LLM Gateway (Go)**: An OpenAI-compatible API entry point. It manages session state in TimescaleDB and publishes tasks to **Apache Pulsar**, decoupling client requests from back-end inference.
*   **Ingestion Service (FastAPI)**: A persistent service that handles multi-source data ingestion. It leverages **Ollama** for embedding generation, eliminating heavy local dependencies (PyTorch/Transformers) and ensuring vector alignment between ingestion and retrieval.
*   **RAG Worker (Go)**: The retrieval engine that consumes tasks from Pulsar. It performs tag-filtered semantic searches in **Qdrant** and orchestrates augmented prompt completion via Ollama.
*   **Vector Database (Qdrant)**: High-performance vector store hosting code-chunk embeddings, organized by `ingestion_id` and metadata tags.
*   **Relational & Timeline Store (TimescaleDB)**: Manages structured metadata, including:
    *   **Tagging System**: Many-to-many relationships between ingestion events and searchable tags.
    *   **Session Management**: User-aware session tracking with 24-hour automated data expiration.
    *   **Embedding Backup**: A relational index of vectors and metadata for data redundancy and auditing.
*   **Local Object Store (Rook-Ceph S3)**: Native S3 storage for codebase persistence, supporting path preservation and direct lifecycle management.

#### 2. Advanced Features & Lifecycle Management

| Feature | Implementation | Benefit |
| --- | --- | --- |
| **Granular Tagging** | Multi-tenant Tagging Logic | Isolate knowledge bases by project, version, or team within a single collection. |
| **Data Lifecycle** | Tag-based Deletion | Automated cleanup across S3, Qdrant, and Postgres based on intersecting tags. |
| **Session Persistence** | Auto-Expiring Sessions | Balances resource usage with 24h cleanup of stale chat history and tags. |
| **Path Preservation** | Directory-Aware Uploads | Maintains relative folder structures from local machines to the RAG context. |
| **Inference Efficiency** | Delegated Embeddings | Uses the cluster's GPU/Inference nodes (Ollama) for both ingest and chat, ensuring 100% vector consistency. |

#### 3. Operational & DevOps Excellence

*   **Local Container Registry**: Integrated private registry (`172.20.1.26:5000`) with Talos-level trust, enabling near-instant pod startups and bypassing external network bottlenecks.
*   **Shadow Build Strategy**: Optimized build pipeline on `hierophant` that vendors dependencies and pre-bakes images, removing all `initContainer` overhead and runtime compilation.
*   **Fast E2E Verification**: A dedicated Go-based integration test driver that validates the entire RAG pipeline—from tag creation and S3 upload to LLM response verification—in under **60 seconds**.
*   **Dark-Themed UI**: A professional-grade Control Center featuring real-time upload progress (v3.1.2), directory pickers, and integrated dataset cleanup tools.

#### 4. Conclusion

The RAG stack has transitioned from a basic "document retriever" to a **Structured Knowledge Management System**. By combining the concurrency of Go, the reliability of Apache Pulsar, and the organized metadata of TimescaleDB, we have established a framework that is both highly performant and easy to maintain over long-term development cycles.
