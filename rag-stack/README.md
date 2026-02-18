# Kubernetes RAG Build

This repository contains all the necessary components to build and deploy a production-grade, event-driven Retrieval-Augmented Generation (RAG) system on a Kubernetes cluster.

## Architecture Overview

The system utilizes a modular microservices architecture:
- **LLM Gateway (Go)**: OpenAI-compatible API entry point.
- **Apache Pulsar**: Asynchronous message bus for task orchestration.
- **RAG Worker (Go)**: Core logic for embeddings, vector search, and LLM coordination.
- **TimescaleDB**: Session and chat history management.
- **Qdrant**: Vector database for code snippet embeddings.
- **Rook-Ceph S3**: Local object storage for the codebase.
- **RAG Web UI (Go)**: User interface for file management and chat.

## Repository Structure

- `infrastructure/`: Core services (Pulsar, TimescaleDB, S3 OBC).
- `services/`: RAG-specific microservices (Gateway, Worker, UI, Qdrant).
- `ingestion/`: Pipeline for vectorizing files from S3 to Qdrant.
- `tests/`: Integration and context verification suites.
- `setup-all.sh`: Master orchestration script.

## Deployment Instructions

To stand up the entire RAG stack, execute the following command on the **hierophant** host:

```bash
cd /mnt/hegemon-share/share/code/kubernetes-rag-build
bash setup-all.sh
```

## Post-Deployment

1.  **Access the Web UI**: Check the LoadBalancer IP for the `rag-web-ui` service.
2.  **Upload Codebase**: Use the UI to upload files to the local S3 bucket.
3.  **Trigger Ingestion**: Start the ingestion job via the UI to populate Qdrant.
4.  **Ask the RAG**: Use the chat interface to query your ingested documents.

## Testing

Run the automated test suite to verify system integrity:

```bash
cd /mnt/hegemon-share/share/code/kubernetes-rag-build/tests
bash run-tests.sh
```
