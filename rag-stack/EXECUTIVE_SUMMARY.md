### Executive Summary: Intelligent Contextual RAG Architecture (v4)

This project implements a high-performance, scalable **Retrieval-Augmented Generation (RAG)** system with integrated **Contextual Memory (Miras/Titans-inspired)**. The architecture has evolved into a fully organized, tag-aware, and memory-persistent ecosystem that prioritizes long-session consistency, data traceability, and resource efficiency.

#### 1. Core Architecture & Services

The system utilizes a modular Go-first micro-services approach, with specialized Python components for data processing.

*   **LLM Gateway (Go)**: OpenAI-compatible entry point. It manages session state in TimescaleDB and publishes tasks to **Apache Pulsar**, enabling fully asynchronous request processing.
*   **Contextual Memory Controller (Go)**: A sophisticated memory orchestration layer that manages **Short-Term**, **Long-Term**, and **Persistent** memories. It performs salience scoring, retention/decay logic, and assembles deterministic "Memory Packs" for inference.
*   **RAG Worker (Go)**: The core retrieval and execution engine. It uses a modular factory to support multiple LLM backends (Llama, Granite) and integrates memory recall into the final prompt assembly.
*   **Ingestion Service (FastAPI)**: Persistent service for multi-source data ingestion, leveraging **Ollama** for consistent embedding generation.
*   **Vector Database (Qdrant)**: High-performance vector store hosting code-chunk embeddings and semantic memory items, organized by `ingestion_id` and metadata tags.
*   **Relational & Timeline Store (TimescaleDB)**: Manages structured metadata, session state, and the advanced memory model (`memory_items`, `memory_links`, `memory_events`).
*   **Local Object Store (Rook-Ceph S3)**: Native S3 storage for codebase persistence and lifecycle management.

#### 2. Advanced Features & Lifecycle Management

| Feature | Implementation | Benefit |
| --- | --- | --- |
| **Contextual Memory** | Triple-tier (ST/LT/Persistent) | Maintains factual consistency and user preferences across long interactive sessions. |
| **Granular Tagging** | Multi-tenant Tagging Logic | Isolate knowledge bases by project, version, or team within a single collection. |
| **End-to-End TLS** | cert-manager + Root CA | Secure communication between all services and storage components (Pulsar+SSL, HTTPS). |
| **Data Lifecycle** | Tag-based Deletion | Automated cleanup across S3, Qdrant, and Postgres based on intersecting tags. |
| **Inference Efficiency** | Delegated Embeddings | Uses the cluster's GPU nodes for both ingest and chat, ensuring 100% vector consistency. |

#### 3. Operational & DevOps Excellence

*   **Local Container Registry**: Integrated private registry (`registry.hierocracy.home:5000`) with Talos-level trust, enabling near-instant pod startups.
*   **Cluster-Native Builds**: Optimized pipeline on `hierophant` using **Kaniko** and **Build Orchestrator**, removing local build dependencies.
*   **Fast E2E Verification**: Dedicated Go-based integration test driver validating the entire RAG + Memory pipeline in under **60 seconds**.
*   **Advanced APM Stack**: Full observability with **Grafana**, **Loki**, **Mimir**, and **Tempo** for logs, metrics, and distributed tracing.

#### 4. Conclusion

The RAG stack has transitioned from a document retriever to an **Intelligent Knowledge Management System**. By integrating contextual memory and a robust asynchronous message bus, we have established a framework that provides high-quality, consistent AI interactions in a secure, local-first environment.
