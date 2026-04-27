# Production-Grade Kubernetes RAG Stack

This project implements a high-performance, scalable **Retrieval-Augmented Generation (RAG)** system optimized for local Kubernetes environments. It is a fully event-driven ecosystem featuring tag-aware ingestion, asynchronous processing via Apache Pulsar, and multi-model LLM support.

## 🚀 Project Synopsis

The RAG Stack has evolved into a **Knowledge-First Intelligent Agent Platform**. It leverages the high concurrency of **Go** for its core infrastructure, the reliability of **Apache Pulsar** for its messaging backbone, and a sophisticated **Local Prompt Memory** system for long-session consistency.

Key capabilities include:
- **Asynchronous Processing**: Decoupled client requests from heavy LLM inference using Pulsar topics.
- **Titans/Miras-Inspired Memory**: A sophisticated local-first memory pipeline with salience scoring and multi-tier recall (short-term, long-term, persistent).
- **Granular Knowledge Isolation**: A multi-tenant tagging system allowing overlapping knowledge bases to coexist and be selectively queried.
- **Vector Alignment**: Using **Ollama** for both ingestion (embeddings) and chat (inference) ensuring 100% vector consistency.
- **Local Sovereignty**: Entirely self-hosted on Kubernetes, utilizing **Rook-Ceph S3** for object storage and a local container registry.
- **Observability**: A full LGTM stack (Loki, Grafana, Tempo, Mimir) for tracing, logging, and metrics.

## 🏗️ Architecture & Core Components

The system is built as a set of modular microservices:

- **LLM Gateway (Go)**: OpenAI-compatible entry point that manages session state, dispatches tasks, and configures memory modes.
- **RAG Worker (Go)**: The retrieval engine that orchestrates semantic searches, memory recall, and augmented prompt completion.
- **Memory Controller (Go)**: Manages structured memory items, salience scoring, and session-based graph links.
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

- [**Iteration 7 (Current)**](./iteration-7.md): Local Prompt Memory + Recall (Miras/Titans-Inspired), Memory Controller service, and contextual salience scoring.
- [**Iteration 6 & 6b**](./iteration-6.md) ([6b](./iteration-6b.md)): Knowledge tags, multi-file upload, and session-specific Pulsar topics.
- [**Iteration 5**](./iteration-5.md): Multi-model selection mechanism, Pulsar-based model routing, and UI for model discovery.

## 📂 Documentation Index

Below is a comprehensive list of project documentation:

### Core Documentation
- [**RAG Stack Architecture.md**](./RAG%20Stack%20Architecture.md): Detailed diagrams and component descriptions.
- [**rag-stack/EXECUTIVE_SUMMARY.md**](./rag-stack/EXECUTIVE_SUMMARY.md): Strategic overview of the system's value and features.
- [**rag-stack/README.md**](./rag-stack/README.md): Practical guide for deploying and using the RAG microservices.

### Iteration Logs
- [**iteration-7.md**](./iteration-7.md): Current development goals (Local Prompt Memory).
- [**iteration-6.md**](./iteration-6.md) / [**iteration-6b.md**](./iteration-6b.md): Knowledge tags and session topics.
- [**iteration-5.md**](./iteration-5.md): Multi-model selection mechanism.
- [**iteration-4.md**](./iteration-4.md) / [**iteration-4a.md**](./iteration-4a.md): APM, Monitoring, and infrastructure refinement.

### Infrastructure & VMs
- [**doms.md**](./doms.md): Core domain/VM definitions for the cluster.
- [**vm-doms.md**](./vm-doms.md): Extended VM configuration and networking details.

---
*Note: This README was automatically generated to provide a unified entry point for the project.*
