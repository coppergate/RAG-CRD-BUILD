# Operational Instructions

This document tracks basic tasks and procedures determined during development to ensure efficiency and avoid redundant logic parsing. These instructions are designed for the **Junie** agent to follow directly.

## Building Service Images — ALWAYS Use the Cluster Pipeline

**IMPORTANT**: All RAG service image builds MUST go through the in-cluster Kaniko build pipeline. Do NOT use `podman build` or `docker build` on the host to build service images. The host-based `build-and-push.sh` is only for bootstrapping when the cluster is not available.

### How the Build Pipeline Works
1. `build-all-on-cluster.sh` packages the `services/` directory into a tarball.
2. The tarball is uploaded to the Ceph S3 object store via a temporary uploader pod.
3. A pre-signed S3 URL is generated for each service.
4. Build tasks (JSON messages with service name, version, dockerfile path, source URL) are published to the Pulsar `build-tasks` topic.
5. The `build-orchestrator` (running in `build-pipeline` namespace) consumes these messages and launches Kaniko `Job` resources.
6. Kaniko pulls the source tarball from S3, builds the Docker image, and pushes it directly to the in-cluster registry.

### Triggering a Build
1.  **Access Hierophant**: Use `./run-on-hierophant.sh` or SSH directly.
2.  **Versioning**: Set the `VERSION` environment variable (e.g., `2.2.0`).
3.  **Command**: Run `rag-stack/build-all-on-cluster.sh --wait` (the `--wait` flag polls the registry until all images are available).
4.  **Example Command**:
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
      "cd /mnt/hegemon-share/share/code/complete-build/rag-stack && \
       VERSION=2.2.0 bash ./build-all-on-cluster.sh --wait"
    ```

### Monitoring Builds
- **Jobs**: Check Kaniko job status in the `build-pipeline` namespace:
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
      "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
       /home/k8s/kube/kubectl get jobs -n build-pipeline"
    ```
- **Build Orchestrator Logs**:
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
      "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
       /home/k8s/kube/kubectl logs -n build-pipeline deploy/build-orchestrator --tail=100"
    ```
- **Build Status Dashboard**: The build-orchestrator exposes a web UI at its service endpoint (port 8080) with SSE-based live updates.

### Verifying Images in Registry
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "for svc in rag-worker llm-gateway db-adapter qdrant-adapter \
              rag-ingestion rag-web-ui object-store-mgr rag-test-runner \
              rag-admin-api memory-controller; do \
     echo \"\$svc: \$(curl -sk https://registry.hierocracy.home:5000/v2/\$svc/tags/list)\"; \
   done"
```

## RAG Pipeline Explorer (Flutter UI)
The RAG Pipeline Explorer is a Flutter-based desktop/web application for managing the RAG cluster.
1.  **Source Directory**: `rag-stack/rag-flutter`
2.  **Development (Linux Desktop)**:
    ```bash
    cd rag-stack/rag-flutter
    flutter run -d linux
    ```
3.  **Development (Web)**:
    ```bash
    cd rag-stack/rag-flutter
    flutter run -d chrome
    ```
4.  **Production Build (Web)**:
    ```bash
    cd rag-stack/rag-flutter
    flutter build web --release
    ```
5.  **BFF (Backend for Frontend)**:
    The Flutter UI communicates with the cluster via the `rag-admin-api` (BFF) service.
    -   **Endpoint**: `https://rag-admin-api.rag.hierocracy.home`
    -   **Streaming**: Chat streaming uses WebSockets at `wss://gateway.hierocracy.home/v1/rag/chat/stream`.
    -   **Adapter APIs**: The BFF proxies requests to:
        -   `object-store-mgr`: `/api/s3/*` for bucket/object browsing.
        -   `db-adapter`: `/api/db/*` for TimescaleDB session/stats browsing.
        -   `qdrant-adapter`: `/api/qdrant/*` for vector collection browsing.
        -   `memory-controller`: `/api/memory/*` for memory management.

## Local/Bootstrap Build and Push (Host-Based)
Use this only for bootstrapping or when the cluster-native pipeline is unavailable.
1.  **Script**: `rag-stack/build-and-push.sh`.
2.  **Journaling**: Use a local directory for journaling to avoid shared mount permission issues.
    -   Default: `/home/junie/rag-build-journals`
    -   Override: `JOURNAL_DIR=/tmp/.rag-build`
3.  **Force Build**: Use `FORCE_BUILD=true` to ensure fresh builds when code is modified.
4.  **Example Command**:
    ```bash
    ./run-on-hierophant.sh "cd /mnt/hegemon-share/share/code/complete-build/rag-stack && VERSION=X.Y.Z FORCE_BUILD=true ./build-and-push.sh"
    ```

## Running End-to-End Tests
To execute the full RAG stack E2E test suite:
1.  **Preparation**: Ensure services are deployed and running with the correct version and domain configuration (`*.hierocracy.home`).
2.  **Execution**: Run the `run-e2e-on-hierophant.sh` script via the remote access script.
    -   **Important**: If the mount has `noexec`, explicitly call the script with `bash`.
3.  **Verification**: The script performs:
    -   Connectivity checks.
    -   ConfigMap refresh for Python tests.
    -   Kubernetes Job launch (`rag-integration-test`).
    -   Go E2E driver execution via Podman (local to hierophant).
4.  **Example Command**:
    ```bash
    ./run-on-hierophant.sh "export VERSION=X.Y.Z && bash /mnt/hegemon-share/share/code/complete-build/rag-stack/tests/run-e2e-on-hierophant.sh"
    ```

## Cross-Model Verification (Automated)
To verify multiple LLM model combinations (e.g., Scenario A: Llama+Granite, Scenario B: Granite+Llama):
1.  **Script**: `rag-stack/tests/run-cross-model-tests.sh`.
2.  **Execution**: Run on **hierophant**.
    ```bash
    ./run-on-hierophant.sh "export VERSION=X.Y.Z && cd /mnt/hegemon-share/share/code/complete-build/rag-stack/tests && bash ./run-cross-model-tests.sh"
    ```
3.  **Mechanism**: This script automatically updates the `rag-worker` deployment's environment variables (`PLANNER_MODEL`, `EXECUTOR_MODEL`), waits for rollout, and runs the standard integration tests for each scenario.

## Journaling and Permissions
To avoid `Permission denied` errors on the shared `/mnt/hegemon-share` mount:
1.  **Log/State Storage**: Redirect any script that writes state files, locks, or persistent journals to local storage on **hierophant**.
2.  **Preferred Paths**: Use `/tmp` (for transient state) or `/home/junie` (for persistent user state).
3.  **Implementation**: Pass environment variables like `JOURNAL_DIR` or use `sh -c` to set context before running the target script.

## Storage and Collection Naming
- **Base Name**: Use `vectors` as the base collection name.
- **Dimension-Based Identification**: Collections are automatically identified by their vector dimensions using the format `vectors-<dim>` (e.g., `vectors-384`, `vectors-4096`).
- **Isolation**: Tag-based filtering uses a strict `must` match to ensure context isolation.
- **Tag Matching**: Filtering and storage must use UUID `tag_ids` for consistency. Human-readable `tag_names` are for display only.

## Health and Readiness Checks
All RAG services implement standardized health and readiness endpoints for Kubernetes probes and external monitoring.
1.  **Endpoints**:
    -   `/healthz`: Liveness probe. Returns `200 OK` if the process is running.
    -   `/readyz`: Readiness probe. Returns `200 OK` only if all critical dependencies (DB, Pulsar, Ollama, S3) are reachable.
    -   `/health`: Legacy endpoint (maps to `/healthz`).
2.  **Implementation**:
    -   **Go Services**: Use the `app-builds/common/health` package.
    -   **Python Services**: Use FastAPI with explicit `/healthz` and `/readyz` decorators.
3.  **Dependency Checks**:
    -   `readyz` performs deep checks:
        -   `database`: `SELECT 1` or lightweight query.
        -   `pulsar`: Client/Producer/Consumer connectivity.
        -   `ollama`: `/api/tags` connectivity.
        -   `s3`: `ListBuckets` or similar.
4.  **Monitoring**: The `rag-admin-api` (BFF) aggregates these checks for the UI.

## Pulsar Installation
Pulsar is installed by `setup-complete.sh` (Step 1.5.8) — NOT by `setup-all.sh`.
`setup-all.sh` only deploys RAG services and **verifies** that Pulsar is already running.

### Prerequisites
- **Rook-Ceph**: The `rook-ceph-block` StorageClass must exist (Pulsar PVCs depend on it).
- **cert-manager**: Must be running for Pulsar TLS certificates.
- Both are installed by `setup-01-basic.sh` (Step 1 of `setup-complete.sh`).

### Installation Flow
1. `setup-complete.sh` → Step 1.5.8 calls `rag-stack/infrastructure/pulsar/install.sh`
2. `install.sh` creates namespace, labels nodes, adds Helm repo, runs `helm upgrade --install` with `--wait --timeout 60m`
3. Post-install verification checks all 4 component types (ZK, BK, Broker, Proxy) are running
4. `setup-complete.sh` → Step 1.5.8.1 calls `init-rag-pulsar.sh` to create tenant `rag-pipeline` and namespaces (`stage`, `data`, `operations`)

### Standalone Pulsar Install (without full setup)
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
   bash /mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/pulsar/install.sh && \
   bash /mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/pulsar/init-rag-pulsar.sh"
```

### Verifying Pulsar Health
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
   /home/k8s/kube/kubectl get pods -n apache-pulsar && \
   /home/k8s/kube/kubectl exec -n apache-pulsar pulsar-toolset-0 -- \
     /pulsar/bin/pulsar-admin tenants list"
```

### Important Notes
- `setup-all.sh` will **exit with an error** if Pulsar brokers are not running. This is intentional — RAG services depend on Pulsar and will fail at runtime without it.
- The Pulsar `install.sh` journal is NOT cleared on success (to prevent redundant re-runs when called from multiple parent scripts).
- Use `FRESH_INSTALL=true` with `setup-complete.sh` to clear all journals and re-run from scratch.

## TLS and Security
1.  **Architecture**: Refer to [TLS-SECURITY.md](TLS-SECURITY.md) for the end-to-end security architecture.
2.  **Trust Distribution**: The combined CA certificate is managed via the `registry-ca-cm` ConfigMap in target namespaces.
3.  **Client Configuration**: Ensure applications use the `SSL_CERT_FILE` environment variable (set to `/etc/ssl/certs/ca-certificates.crt`) for CA trust.
4.  **Verification**: Use `kubectl get certificate -A` to verify certificate status.
5.  **Service TLS**: All RAG services (adapters, gateway, admin-api) now use TLS for their REST APIs (port 8080 or 443).
    -   Certificates and keys are mounted from secrets named `<service>-tls`.
    -   Probes use `scheme: HTTPS`.

## Standardized Health and Readiness Checks
All RAG services now implement standardized endpoints for Kubernetes probes and management:
-   `/healthz` (Liveness): Always returns `OK` (200) if the process is running.
-   `/readyz` (Readiness): Returns JSON with `{"status": "ready"}` (200) only if all downstream dependencies are reachable.
    -   `db-adapter`: Checks TimescaleDB connectivity.
    -   `qdrant-adapter`: Checks Qdrant connectivity.
    -   `object-store-mgr`: Checks S3/Ceph connectivity.
    -   `memory-controller`: Checks database connectivity.
-   `/api/health/all` (Admin API): Aggregates results from all services into a single JSON report.

To manually verify health via `kubectl exec`:
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
   /home/k8s/kube/kubectl exec -n rag-system deploy/rag-admin-api -- \
   curl -sk https://localhost:8080/api/health/all"
```

## Adding Support for New LLMs (Rag-Worker)
The `rag-worker` service is refactored for multi-model modularity.
1.  **Define Implementation**: Create a new package under `rag-stack/services/rag-worker/internal/models/` (e.g., `internal/models/newmodel`).
2.  **Implement Interfaces**: Implement the `Planner` and `Executor` interfaces defined in `internal/models/interfaces.go`.
3.  **Factory Integration**: Update the factory logic in `rag-stack/services/rag-worker/cmd/worker/main.go` to instantiate the new model based on the `PLANNER_MODEL` or `EXECUTOR_MODEL` environment variables.
4.  **Configuration**: Set the respective environment variables in the Kubernetes deployment or via `setup-complete.sh`.

## Running Tests
1.  **Unit Tests**: In `rag-stack/services/rag-worker`, run `go test ./...`.
2.  **Integration Tests**:
    - Build and push images using `VERSION=x.y.z ./build-and-push.sh` in `rag-stack/`.
    - Run on **hierophant**: `cd rag-stack/tests && VERSION=x.y.z bash ./run-tests.sh`.
3.  **Cross-Model Verification**:
    -   Use the automated script: `bash ./run-cross-model-tests.sh` (as documented above).
    -   Supported models: `llama3.1`, `granite3.1-dense:8b`.

## Change Logs
- **Location**: `/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/ai-changes/changelog.json`
- **Frequency**: Update at the conclusion of each prompting session when changes are made.
- **Format**: Structured JSON with datetime stamp and brief description (most recent at the top).
- **Git Policy**: The changelog does NOT need to be committed to git.

## Ent ORM Management (Shared)
The RAG stack uses the **Ent ORM** for type-safe database access, centralized in the **common** module.
1.  **Schema Definition**: Schemas are located in `rag-stack/services/common/ent/schema/`.
2.  **Code Generation**: If schemas are modified, regenerate the Ent client in the `common` module with the `sql/upsert` feature:
    -   **Command**: 
        ```bash
        cd rag-stack/services/common && go run -mod=mod entgo.io/ent/cmd/ent generate --feature sql/upsert ./ent/schema
        ```
3.  **Service Integration**:
    -   All services (e.g., `db-adapter`, `llm-gateway`) should import and use the client from `app-builds/common/ent`.
    -   Ensure `go mod tidy` is run in both `common` and the consuming service after changes.

## Storage Layout on Hierophant
- **Podman storage**: `/mnt/storage/containers/storage` — configured via `~/.config/containers/storage.conf`
- **Registry data**: `/mnt/storage/registry-data` — Docker registry image layers and manifests
- **VM disk images**: `/var/lib/libvirt/images/` — Talos ISOs (symlinked from shared mount)
- **Talos/kubectl configs**: `/home/k8s/kube/` — kubeconfig, kubectl binary
- **Registry TLS/config**: `/mnt/storage/registry-config/` — config.yml, tls.crt, tls.key
- **Pre-pulled LLM models**: `/mnt/storage/ollama-models/` — Ollama model blobs and manifests
- **DO NOT** store large data (container images, registry) on `/home` — it has limited capacity (~143G shared with system)

## LLM Model Management

### Pre-Pulling Models (Outside Install)
Models should be downloaded and pushed to the local registry BEFORE running the cluster install.
This avoids long postStart hangs and internet dependency during install.

1. **Script**: `rag-stack/infrastructure/ollama/pre-pull-models.sh`
2. **Storage**: Models are cached at `/mnt/storage/ollama-models/` on hierophant.
3. **Registry**: Models are also pushed as OCI artifacts to the local registry.
4. **Command**:
    ```bash
    cd /mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/ollama
    bash ./pre-pull-models.sh
    ```

### Model Seeding (During Install)
During install, `ollama.sh` deploys Ollama pods WITHOUT model pulling, then calls `seed-models.sh`
which creates temporary seeder pods that pull models from the local registry into the PVCs.
This is automatic and requires no manual intervention if models are already in the registry.

### TimescaleDB Secret
The `timescaledb-secret` in rag-system is created dynamically during install by `setup-all.sh`.
It fetches the real password from the CloudNativePG-managed `timescaledb-app` secret in the
`timescaledb` namespace. **Do NOT use the hardcoded `timescaledb-secret.yaml` file** — it exists
only as a template reference and its password will not match after a cluster rebuild.

## Headlamp Access
To get the login token for Headlamp:
1.  **Command**: Run the following on **hierophant**:
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && /home/k8s/kube/kubectl get secret headlamp-admin-token -n headlamp -o jsonpath='{.data.token}' | base64 -d"
    ```
2.  **Usage**: Copy the decrypted token and paste it into the Headlamp login page.
3.  **Role**: This token belongs to the `headlamp-admin` ServiceAccount and has `cluster-admin` privileges.
