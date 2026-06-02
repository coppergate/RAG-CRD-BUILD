# Kubernetes RAG Build

This repository contains all the necessary components to build and deploy a production-grade, event-driven Retrieval-Augmented Generation (RAG) system on a Kubernetes cluster.

## Architecture Overview

The system utilizes a modular microservices architecture:
- **LLM Gateway (Go)**: OpenAI-compatible API entry point with strict CORS and session management.
- **Apache Pulsar**: High-concurrency message bus for asynchronous task orchestration.
- **RAG Worker (Go)**: Core orchestration engine using high-speed direct HTTP retrieval for vector searches.
- **TimescaleDB**: Relational metadata, session tracking, and structured memory persistence.
- **Qdrant**: High-performance vector database with dual-mode (Pulsar/HTTP) access.
- **Rook-Ceph S3**: Local-first S3 storage for document and source context persistence.
- **RAG Explorer (Flutter)**: Modularized management UI for ingestion, memory, and maintenance.

## Repository Structure

- `infrastructure/`: Core services (Pulsar, TimescaleDB, S3 OBC).
- `services/`: RAG-specific microservices (Gateway, Worker, Admin API, Qdrant).
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

1.  **Access the Admin API**: Verify health via the `rag-admin-api`.
2.  **Use RAG Explorer**: Connect your RAG Explorer desktop client to the cluster.
3.  **Chat & Ingest**: Use the explorer to manage ingestion and chat with the pipeline.

## Testing

`tests/run-tests.sh` is the full test runner. It runs Go unit tests across all service modules and then the end-to-end cluster tests. Run it whenever you want full confidence in the services — before merging a branch, after a deploy, or after a change that touches multiple services.

```bash
# Full test: unit tests + E2E (requires cluster access on hierophant)
bash /mnt/hegemon-share/share/code/complete-build/rag-stack/tests/run-tests.sh

# Unit tests only — no cluster required, fast feedback during development
bash /mnt/hegemon-share/share/code/complete-build/rag-stack/tests/run-tests.sh --unit-only

# E2E only — skip unit tests, run cluster tests directly
bash /mnt/hegemon-share/share/code/complete-build/rag-stack/tests/run-tests.sh --e2e-only

# Stop at first unit test failure instead of running all modules
bash /mnt/hegemon-share/share/code/complete-build/rag-stack/tests/run-tests.sh --fail-fast
```

The unit test phase runs `go vet` on all 10 service modules and `go test ./...` on the 8 that have test files, printing a per-module summary. The E2E phase deploys a test job to the `rag-system` namespace on hierophant and runs the Python integration suite, followed by the Go E2E driver.
