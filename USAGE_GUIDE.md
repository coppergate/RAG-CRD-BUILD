# RAG Pipeline Usage Guide

This document provides a step-by-step guide for using the RAG (Retrieval-Augmented Generation) system.

## 1. Environment Preparation
All system-wide operations, builds, and cluster management are performed on the **hierophant** host.

### 1.1 Accessing the Cluster
1. Establish an SSH connection to **hierophant**:
   ```bash
   ./enable-junie-hierophant.sh
   ```
2. Once on hierophant, use the specialized `kubectl` and `kubeconfig`:
   ```bash
   export KUBECONFIG=/home/k8s/kube/config/kubeconfig
   /home/k8s/kube/kubectl get pods -A
   ```

## 2. Ingesting Data
The RAG system requires data (PDFs, text, etc.) to provide context for AI responses.

### 2.1 File Upload
Currently, ingestion is triggered by uploading files to the cluster's S3 storage (Rook-Ceph) or using the `rag-ingestion` service.
- **Workflow**:
  1. Upload your documents to the `rag-data` bucket.
  2. Trigger the ingestion pipeline via the `rag-admin-api` or directly calling `rag-ingestion`.
  3. Documents are chunked, embedded, and stored in the Qdrant vector database.

### 2.2 Tagging
When ingesting documents, assign **tags** (e.g., `project-alpha`, `internal-docs`) to enable isolated retrieval during chat sessions.

## 3. Interactive Chat
Use the **RAG Pipeline Explorer** (Flutter UI) or the legacy web UI for interacting with the system.

### 3.1 Accessing the Explorer
The UI is available in two forms:
- **Web UI**: `https://rag-explorer.rag.hierocracy.home` (standard access).
- **Linux Desktop App**: For a more integrated experience on this VM, you can run the RAG Explorer as a native Linux application.
  - Follow the setup instructions in `OPERATIONS.md` to install Flutter and dependencies.
  - Launch with `flutter run -d linux` from the `rag-stack/services/rag-explorer` directory.

### 3.2 Chat Workflow
1. **Select Models**: Choose a `Planner` (for reasoning) and an `Executor` (for generation).
2. **Set Context**: Select the tags corresponding to the data you want the AI to "remember."
3. **Configure Memory**:
   - `off`: Standard RAG retrieval only.
   - `session`: Enables short-term context within the current chat.
   - `full`: Enables long-term recall from previous interactions (Iteration 7).
4. **Submit Prompt**: Enter your query and receive a streaming response with the retrieved context and memory trace visible in the metadata panel.

## 4. System Monitoring and Management
The RAG stack includes a full APM suite for monitoring health and performance.

### 4.1 Health Checks
Check the status of all services via the `rag-admin-api`:
```bash
curl -sk https://rag-admin-api.rag.hierocracy.home/api/health/all
```

### 4.2 Dashboards
- **Grafana**: `https://grafana.rag.hierocracy.home` (Metrics, Logs, Traces).
- **Headlamp**: Kubernetes management UI (use token from hierophant).
- **Qdrant Dashboard**: Direct vector exploration (if enabled).

## 5. Maintenance and Troubleshooting
### 5.1 Rebuilding Services
To update the system with new code changes:
1. Update code in `rag-stack/services/`.
2. Increment `VERSION` in `setup-complete.sh`.
3. Run the cluster-native build:
   ```bash
   ssh junie@hierophant "VERSION=X.Y.Z bash /mnt/hegemon-share/share/code/complete-build/rag-stack/build-all-on-cluster.sh --wait"
   ```

### 5.2 Common Issues
- **Image Pull Backoff**: Ensure the local registry is healthy and nodes trust the private CA.
- **Connection Refused**: Verify that the target service and its dependency (Pulsar, DB) are running and the `IngressRoute` is correctly configured.
