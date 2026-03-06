# Production-Grade Kubernetes RAG Stack

This project implements a high-performance, scalable **Retrieval-Augmented Generation (RAG)** system optimized for local Kubernetes environments. It is a fully event-driven ecosystem featuring tag-aware ingestion, asynchronous processing via Apache Pulsar, and multi-model LLM support.

## 🚀 Project Synopsis

The RAG Stack has evolved from a simple document retriever into a **Structured Knowledge Management System**. It leverages the high concurrency of **Go** for its core infrastructure, the reliability of **Apache Pulsar** for its messaging backbone, and the specialized analytical capabilities of **TimescaleDB** and **Qdrant**.

Key capabilities include:
- **Asynchronous Processing**: Decoupled client requests from heavy LLM inference using Pulsar topics.
- **Granular Knowledge Isolation**: A multi-tenant tagging system allowing overlapping knowledge bases to coexist and be selectively queried.
- **Vector Alignment**: Using **Ollama** for both ingestion (embeddings) and chat (inference) ensuring 100% vector consistency.
- **Local Sovereignty**: Entirely self-hosted on Kubernetes, utilizing **Rook-Ceph S3** for object storage and a local container registry.
- **Observability**: A full LGTM stack (Loki, Grafana, Tempo, Mimir) for tracing, logging, and metrics.

## 🏗️ Architecture & Core Components

The system is built as a set of modular microservices:

- **LLM Gateway (Go)**: OpenAI-compatible entry point that manages session state and dispatches tasks.
- **RAG Worker (Go)**: The retrieval engine that orchestrates semantic searches in Qdrant and augmented prompt completion.
- **Ingestion Service (FastAPI)**: Handles multi-source data ingestion and embedding generation.
- **Qdrant Adapter & DB Adapter**: Specialized services for centralized access to the vector store and relational database.
- **Object Store Manager (Go)**: Centralized management of S3 storage and file metadata.
- **Build Orchestrator (Go)**: Cluster-native service that automates image builds via Kaniko and Pulsar messages.
- **Infrastructure**:
    - **Pulsar**: Message bus for task orchestration.
    - **Qdrant**: High-performance vector database.
    - **TimescaleDB**: Relational metadata, session tracking, and embedding backup.
    - **Rook-Ceph S3**: Native S3 storage for document persistence.

For a deep dive into the architecture, diagrams, and component interactions, see:
- [**RAG Stack Architecture**](./RAG%20Stack%20Architecture.md)
- [**Executive Summary**](./rag-stack/EXECUTIVE_SUMMARY.md)

## 🛠️ Deployment & Orchestration

The project is designed for deployment on the **hierophant** host using automated bootstrap scripts.

- **Main Entry Point**: `setup-complete.sh` — Orchestrates everything from basic infra (Rook-Ceph/Traefik) to the RAG stack deployment.
- **RAG Stack Deployment**: `rag-stack/setup-all.sh` — Handles Namespaces, ConfigMaps, Secrets, and Microservice rollouts.
- **Build System**: Features a **Zero-Host Build Architecture** using a cluster-native pipeline (Kaniko + S3 + Pulsar) to prevent host resource exhaustion.

For detailed instructions, refer to:
- [**Installation Guide**](./INSTALLATION.md)
- [**RAG Stack Deployment Guide**](./rag-stack/README.md)

## 📈 Project Evolution & Roadmaps

The project follows a structured iteration-based development cycle:

- [**Iteration 5 (Current)**](./iteration-5.md): Multi-model selection mechanism, Pulsar-based model routing, and UI for model discovery.
- [**Iteration 4 & 4a**](./iteration-4.md) ([4a](./iteration-4a.md)): APM integration (Grafana LGTM stack) and improved S3 storage handling.
- [**Iteration 3**](./iteration-3.md) & [**Iteration 2**](./iteration-2.md): Evolution from basic ingestion to stable asynchronous processing.

## 📂 Documentation Index

Below is a comprehensive list of project documentation:

### Core Documentation
- [**RAG Stack Architecture.md**](./RAG%20Stack%20Architecture.md): Detailed diagrams and component descriptions.
- [**rag-stack/EXECUTIVE_SUMMARY.md**](./rag-stack/EXECUTIVE_SUMMARY.md): Strategic overview of the system's value and features.
- [**rag-stack/README.md**](./rag-stack/README.md): Practical guide for deploying and using the RAG microservices.

### Iteration Logs
- [**iteration-5.md**](./iteration-5.md): Current development goals (Multi-model support).
- [**iteration-4.md**](./iteration-4.md) / [**iteration-4a.md**](./iteration-4a.md): APM, Monitoring, and infrastructure refinement.
- [**iteration-3.md**](./iteration-3.md): Stability and Pulsar integration.
- [**iteration-2.md**](./iteration-2.md): Initial microservice separation.

### Infrastructure & VMs
- [**doms.md**](./doms.md): Core domain/VM definitions for the cluster.
- [**vm-doms.md**](./vm-doms.md): Extended VM configuration and networking details.

---
*Note: This README was automatically generated to provide a unified entry point for the project.*
