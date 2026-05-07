# Operational Instructions

This document tracks basic tasks and procedures determined during development to ensure efficiency and avoid redundant logic parsing. These instructions are designed for the **Junie** agent to follow directly.

## 1. Cluster Fundamentals & Infrastructure

### 1.1 Storage Layout on Hierophant
- **Podman storage**: `/mnt/storage/containers/storage` — configured via `~/.config/containers/storage.conf`
- **Registry data**: `/mnt/storage/registry-data` — Docker registry image layers and manifests
- **VM disk images**: `/var/lib/libvirt/images/` — Talos ISOs (symlinked from shared mount)
- **Talos/kubectl configs**: `/home/k8s/kube/` — kubeconfig, kubectl binary
- **Registry TLS/config**: `/mnt/storage/registry-config/` — config.yml, tls.crt, tls.key
- **Pre-pulled LLM models**: `/mnt/storage/ollama-models/` — Ollama model blobs and manifests
- **DO NOT** store large data (container images, registry) on `/home` — it has limited capacity (~143G shared with system)

### 1.2 Host Reboot Recovery (Network & Routing)
If the host (**hierophant**) has been rebooted, the volatile IPTables rules and bridge configurations for external routing are lost. This manifests as a **Connection Timeout** or **No route to host** error when accessing cluster services (like `rag-admin-api`) from external VMs.

To recover the network state:
1. **Initialize Network**: Run the idempotent network initialization script to restore bridges and IPTables.
   ```bash
   # On hierophant:
   sudo /mnt/hegemon-share/share/code/kubernetes-setup/new-setup/00-init-network.sh
   ```
2. **Restore VM Connectivity**: If the network was initialized *after* VMs were already running, their interfaces may be detached from the bridge. Run the restoration script to perform a safe, ordered restart of the cluster.
   ```bash
   # On hierophant:
   sudo /mnt/hegemon-share/share/code/kubernetes-setup/new-setup/05-restore-vms.sh
   ```
   *Note: `05-restore-vms.sh` now automatically calls `00-init-network.sh` at the start.*

#### Prevention (Boot-time Automation)
To prevent routing issues after future reboots, ensure `00-init-network.sh` runs on every boot.
- **Recommended**: Add a `@reboot` entry to the `root` crontab on hierophant:
  ```text
  @reboot /mnt/hegemon-share/share/code/kubernetes-setup/new-setup/00-init-network.sh >> /var/log/network-init.log 2>&1
  ```
- **Alternative**: Create a systemd unit file (e.g., `rag-network-init.service`) that runs the script before `libvirtd.service`.

### 1.3 Cluster Maintenance (Rebooting the Host)
When performing a full host reboot on **hierophant**, use the following procedures to ensure a clean cluster shutdown and graceful recovery.

#### Graceful Shutdown
Before rebooting the host, execute the `cluster-shutdown.sh` script to drain nodes and scale down stateful services (Pulsar, Ceph, DB).

- **Script Location**: `../kubernetes-setup/cluster-shutdown.sh`
- **Execution**: MUST be run on **hierophant**.
```bash
# On hierophant:
cd /mnt/hegemon-share/share/code/kubernetes-setup
bash ./cluster-shutdown.sh
```
- **What it does**:
    0.  **Admission Controller Cleanup**: Deletes the `k8tz` `MutatingWebhookConfiguration` to prevent it from blocking the next cluster startup.
    1.  Scales down all non-system resources in a prioritized order (Apps -> Bus -> Infrastructure).
    2.  Waits for all pods in the scaled namespaces to fully terminate to ensure clean unmounting.
    3.  Quiesces Ceph cluster (sets maintenance flags like `noout`).
    4.  Drains all Kubernetes nodes (control-plane and worker/inference) while storage is still available.
    5.  Scales down Rook-Ceph components (mgr -> others -> osd -> mon).
    6.  Shuts down all cluster VMs via `virsh`.
    7.  Saves the original replica counts to `/home/k8s/kube/cluster-replicas.state`.

#### Rebooting
Once the script confirms all VMs have shut down, you can safely reboot the host.
```bash
sudo reboot
```

#### Graceful Startup
After the host is back up, execute the `cluster-startup.sh` script to restore the cluster state.

- **Script Location**: `../kubernetes-setup/cluster-startup.sh`
- **Execution**: MUST be run on **hierophant**.
```bash
# On hierophant:
cd /mnt/hegemon-share/share/code/kubernetes-setup
bash ./cluster-startup.sh
```
- **What it does**:
    1.  Detaches GPUs from the host PCI bus.
    2.  Starts all cluster VMs.
    3.  Waits for the Kubernetes API and all nodes to be Ready.
    4.  **Admission Controller Cleanup**: Deletes the `k8tz` `MutatingWebhookConfiguration` (if present) as a safeguard to ensure core networking (Flannel) can start without mutation deadlocks.
    5.  Uncordons all nodes.
    6.  Restores Rook-Ceph in order (mon -> osd -> others).
    7.  Unfreezes Ceph state (unsets maintenance flags).
    8.  Restores all other resources from `/home/k8s/kube/cluster-replicas.state` in the correct reverse-shutdown order (Infrastructure -> Bus -> Apps).
    9.  **Admission Controller Restoration**: Reinstalls the `k8tz` admission controller via `helm upgrade --install` once the cluster is stable.

### 1.4 Pulsar Infrastructure & Health
Pulsar is installed by `setup-complete.sh` (Step 1.5.8) — NOT by `setup-all.sh`.
`setup-all.sh` only deploys RAG services and **verifies** that Pulsar is already running.

#### Prerequisites
- **Rook-Ceph**: The `rook-ceph-block` StorageClass must exist (Pulsar PVCs depend on it).
- **cert-manager**: Must be running for Pulsar TLS certificates.
- Both are installed by `setup-01-basic.sh` (Step 1 of `setup-complete.sh`).

#### Installation Flow
1. `setup-complete.sh` → Step 1.5.8 calls `rag-stack/infrastructure/pulsar/install.sh`
2. `install.sh` creates namespace, labels nodes, adds Helm repo, runs `helm upgrade --install` with `--wait --timeout 60m`
3. Post-install verification checks all 4 component types (ZK, BK, Broker, Proxy) are running
4. `setup-complete.sh` → Step 1.5.8.1 calls `init-rag-pulsar.sh` to create tenant `rag-pipeline` and namespaces (`stage`, `data`, `operations`)

#### Standalone Pulsar Install (without full setup)
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
   bash /mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/pulsar/install.sh && \
   bash /mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/pulsar/init-rag-pulsar.sh"
```

#### Verifying Pulsar Health
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
   /home/k8s/kube/kubectl get pods -n apache-pulsar && \
   /home/k8s/kube/kubectl exec -n apache-pulsar pulsar-toolset-0 -- \
     /pulsar/bin/pulsar-admin tenants list"
```

#### Pulsar Initialization (Tenants and Namespaces)
If services fail with `no partitioned metadata for topic` or `Namespace not found`, ensure the RAG tenants and namespaces are provisioned:
1. **Script**: `rag-stack/infrastructure/pulsar/init-rag-pulsar.sh`
2. **Namespaces Created**: `rag-pipeline/stage`, `rag-pipeline/data`, `rag-pipeline/operations`, `rag-pipeline/dlq`.
3. **Run Command**:
   ```bash
   ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
     "bash /mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/pulsar/init-rag-pulsar.sh"
   ```

### 1.5 APM Stack (Monitoring & Observability)

#### Grafana Dashboards
The RAG stack uses the following Grafana dashboards for monitoring:
- **inference-nodes** (`uid: rag-inference`): Real-time monitoring for inference nodes (GPU/CPU).
- **operations-overview** (`uid: rag-operations`): Main dashboard for high-level monitoring.
- **performance-overview** (`uid: rag-performance`): Detailed performance and error metrics per service.
- **rag-logs** (`uid: rag-logs`): Loki-based dashboard for log analysis.

#### Embedded Grafana Configuration
To allow `rag-explorer` to display embedded panels and links:
1. **Anonymous Access**: Must be enabled in `central-grafana` (`Grafana` CR) with `org_role: Admin` (or `Viewer`) and `enabled: true`.
2. **Security**: `allow_embedding` must be set to `true` in the Grafana configuration.
3. **Ingress TLS**: The `central-grafana-ingress` must use a certificate (`grafana-tls`) that includes `grafana.rag.hierocracy.home` in the SAN.
4. **UID/Slug Alignment**: Dashboards must have UIDs and titles (slugs) that match the hardcoded paths in `rag-explorer` (e.g., `/d/rag-inference/inference-nodes`).

#### Custom Metrics
New metrics introduced in Iteration 9 for operational tracking:
- `gateway_prompt_size_bytes`: Histogram of incoming prompt sizes in `llm-gateway`.
- `worker_response_size_bytes`: Histogram of outgoing response sizes in `rag-worker`.

#### APM Stack TLS Configuration
As of version `2.2.11`, the APM stack is configured with TLS for internal communication:
1.  **Loki & Mimir (Gateways)**:
    -   Exposed on port **443** (HTTPS) via their respective gateway services.
    -   Gateways use NGINX with SSL enabled on port **8443**.
    -   Alloy and Grafana connect via `https://loki-gateway.monitoring.svc.cluster.local` and `https://mimir-gateway.monitoring.svc.cluster.local`.
    -   Trust is managed via the `registry-ca-cm` ConfigMap (mounted as `/etc/ssl/certs/ca.crt`).
    -   **Configuration Update (v2.5.5)**: Updated `values.yaml.template` for Loki and Mimir to use the `nginxConfig.file` map structure (required by Loki Helm chart v6.55.0+) instead of a direct string for `gateway.nginxConfig`.
2.  **Tempo**:
    -   **Push API (OTLP)**: Exposed on port **4318** (HTTPS). Alloy pushes traces securely.
    -   **Query API (REST)**: Exposed on port **3200** (HTTP). Grafana queries traces via plain HTTP to avoid handshake issues.
3.  **Grafana**:
    -   The `central-grafana` instance trusts the internal CA by mounting the `registry-ca-cm`.
    -   Datasources for Loki and Prometheus/Mimir use `https` with `tlsSkipVerify: true`.
    -   Datasource for Tempo uses `http://tempo.monitoring.svc.cluster.local:3200`.
4.  **Tempo Metrics Generator**:
    -   **Enabled**: As of version `2.2.13`, Tempo's `metrics_generator` is enabled to support TraceQL features like `rate()`.
    -   **Storage**: Uses `/var/tempo/generator/wal` on the `storage` volume.
    -   **Remote Write**: Pushes generated metrics back to Mimir via `https://mimir-gateway.monitoring.svc.cluster.local/api/v1/push`.

#### Alloy Scraping Strategy (Out-of-Order Prevention)
As of version `2.2.11`, Alloy (DaemonSet) uses **local pod discovery** for cluster-wide services (Pulsar, DCGM) to avoid `err-mimir-sample-out-of-order` errors.
-   **Mechanism**: Uses `discovery.kubernetes` with `role = "pod"`.
-   **Filter**: Relabels targets to `keep` only those where `__meta_kubernetes_pod_node_name` matches the local node (using `sys.env("HOSTNAME")`).
-   **Effect**: Each Alloy instance only scrapes pods on its own node, preventing duplicate series from being pushed to Mimir from multiple nodes.

### 1.6 TLS and Security
1.  **Management Guide**: Refer to [TLS-GUIDE.md](TLS-GUIDE.md) for step-by-step instructions on creating certificates, adding SANs, and managing trust.
2.  **Architecture**: Refer to [TLS-SECURITY.md](TLS-SECURITY.md) for the end-to-end security architecture.
3.  **Trust Distribution**: The Root CA is distributed to all Talos nodes via the `machine.install.extraCerts` configuration in `/mnt/hegemon-share/share/code/kubernetes-setup/configs/talos-registry-patch.yaml`, and managed in-cluster via the `registry-ca-cm` ConfigMap in target namespaces.
4.  **Client Configuration**: Ensure applications use the `SSL_CERT_FILE` environment variable (set to `/etc/ssl/certs/ca-certificates.crt`).
5.  **Verification**: Use `kubectl get certificate -A` to verify certificate status.
6.  **Service TLS**: All RAG services (adapters, gateway, admin-api) now use TLS for their REST APIs (port 8080 or 443).
    -   Certificates and keys are mounted from secrets named `<service>-tls`.
    -   Probes use `scheme: HTTPS`.

### 1.8 Cluster Installation & Build Orchestration
If you need to build the cluster from scratch, use the orchestration script on **hierophant**. This script handles disk formatting, network setup, bootstrap registry creation, and VM building in the correct order.

- **Script Location**: `../kubernetes-setup/new-setup/config-cluster.sh`
- **Execution**: MUST be run on **hierophant**.
```bash
# On hierophant:
cd /mnt/hegemon-share/share/code/kubernetes-setup/new-setup
export FRESH_INSTALL=true # Bypass interactive prompts
bash ./config-cluster.sh
```

- **What it does**:
    1.  Formats NVMe partitions with specific UUIDs.
    2.  Initializes host networking (br-mgmt, br-app, VLAN 20, IPTables).
    3.  Defines Libvirt networks (talos-nat, lb-net).
    4.  Starts and seeds the bootstrap registry (Podman) with Talos installer images.
    5.  Builds Control Plane VMs and waits for maintenance mode.
    6.  Generates and applies Talos configuration (using the registry patch at `/mnt/hegemon-share/share/code/kubernetes-setup/configs/talos-registry-patch.yaml`).
    7.  Bootstraps the Kubernetes control plane.
    8.  Builds all Worker and Inference VMs.
    9.  Applies configuration and labels nodes (GPU Operator, etc.).

- **Monitoring Progress**:
    - The script uses a persistent journal. If interrupted, it will resume from the last successful step.
    - Check the journal with: `cat /home/k8s/talos/config/journal.log` (if configured in `scripts/journal-helper.sh`).

### 2.1 Session Establishment (Operational Context)
Every new session for the **Junie** agent MUST establish the operational context by following these steps:
1.  **Git Initialization**:
    - If the current branch is `main`, pull the latest changes from origin.
    - If on a work branch:
        - Commit all pending changes.
        - Rename the branch to a descriptive name reflecting the changes (e.g., `fix-ui-tls`).
        - Push the branch to origin.
        - Create a merge request and merge the branch into `main`.
        - Switch to `main` and pull latest changes.
    - Create a new session branch named `Work-YYYYMMDD` (e.g., `Work-20260429`).
    - During the session, commit with short, meaningful messages.
2. **File Size Limit**: Do not commit any files larger than 1MB without asking first.
   - **Clean History (Rebase & Squash)**:
   - Mark fixup commits with `git commit --fixup <commit-hash>` when making small changes.
   - Rebase with autosquash: Run `git rebase -i --autosquash main` before pushing.
   - Push safely: Use `git push --force-with-lease origin <branch>`.
   - **Daily Push**: Every day, make a new push to GIT with the current committed code.
   - **Pull Requests**: Create a pull request for each day's branch.
3. **Versioning**: The single source of truth for the project version is the `CURRENT_VERSION` JSON file at the root of the project. 
    - Verify the current project version in `CURRENT_VERSION`.
    - Scripts like `build.sh` and `setup-all.sh` will read from this file by default.
    - `build.sh` performs automatic version incrementing when code changes are detected via hashing.
4. **Changelog**: Add an initialization entry to `/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/ai-changes/changelog.json` with the current datetime and "Environment initialization" description.
5. **Operational Review**: Read `guidelines.md` and `OPERATIONS.md`.

### 2.2 Current Focus (Iteration 7)
As of version 2.10.x, the project is focusing on **Iteration 7: Local Prompt Memory + Recall (Miras/Titans-Inspired)**.
1.  **Memory Data Model**: Implementing structured memory types (`short_term`, `long_term`, `persistent`) in TimescaleDB.
2.  **Memory Controller**: A dedicated service for salience scoring, retention/decay logic, and MemoryPack assembly.
3.  **Pulsar Integration**: Asynchronous memory operations via `rag.memory.*` topics.
4.  **Retrieval Composition**: Context-aware recall in `rag-worker` using strict token budgeting and salience ranking.
5.  **Memory Tracing**: Real-time observability of the memory recall process in the RAG Explorer UI.

### 2.3 Change Logs
- **Location**: `/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/ai-changes/changelog.json`
- **Frequency**: Update at the conclusion of each prompting session when changes are made.
- **Format**: Structured JSON with datetime stamp and brief description (most recent at the top).
- **Git Policy**: The changelog does NOT need to be committed to git.

### 2.4 Journaling and Permissions
To avoid `Permission denied` errors on the shared `/mnt/hegemon-share` mount:
1.  **Log/State Storage**: Redirect any script that writes state files, locks, or persistent journals to local storage on **hierophant**.
2.  **Preferred Paths**: Use `/tmp` (for transient state) or `/home/junie` (for persistent user state).
3.  **Implementation**: Pass environment variables like `JOURNAL_DIR` or use `sh -c` to set context before running the target script.

### 2.5 Messaging & Data Contracts (Protobuf)
As of Iteration 11, the project uses **Protobuf** as the single source of truth for all network-crossing DTOs (Data Transfer Objects) across Pulsar and REST APIs.

#### Contract Management
1.  **Schema Definition**: All shared contracts MUST be defined in `rag-stack/contracts/rag_stack.proto`.
2.  **Code Generation**:
    - **Go**: Generated into `rag-stack/services/common/contracts/rag_stack.pb.go`.
    - **Python**: Generated into `rag-stack/services/rag-ingestion/rag_stack_pb2.py`.
    - Use the provided helper scripts or `protoc` commands to regenerate after any changes.
3.  **Standardization**: Standardize on the `result` field for all final LLM outputs and intermediate chunks.
4.  **Flexible Metadata**: Use `google.protobuf.Struct` for `metadata` fields to maintain JSON-like flexibility while benefiting from typed wrappers.
5.  **Strict Typing**: DO NOT use `map[string]interface{}` for shared contracts in Go. Import and use the generated Protobuf structs instead.
6.  **Pulsar Encoding**: Use JSON-encoded Protobufs for Pulsar messages. This maintains human-readability in logs/tools while ensuring contract compliance in code.
    - Go: `json.Marshal(proto_msg)` and `json.Unmarshal(data, &proto_msg)`.
    - Python: `json_format.MessageToJson(proto_msg)` and `json_format.Parse(data, proto_msg)`.

### 3.1 Cluster-Native Build Pipeline (Kaniko)
All RAG service image builds MUST go through the in-cluster Kaniko build pipeline. Do NOT use `podman build` or `docker build` on the host to build service images except for bootstrapping.

#### How the Build Pipeline Works
1. `build-all-on-cluster.sh` packages the `services/` directory into a tarball.
2. The tarball is uploaded to the Ceph S3 object store.
3. Build tasks (JSON messages) are published to the Pulsar `build-tasks` topic.
4. The `build-orchestrator` launches Kaniko `Job` resources.
5. Kaniko pulls the source, builds the image, and pushes it to the in-cluster registry.

#### Triggering a Build
1.  **Access Hierophant**: Use `./run-on-hierophant.sh` or SSH.
2.  **Versioning**: The version is read from `CURRENT_VERSION` at the project root.
3.  **Command**: Run `rag-stack/build.sh` (defaults to cluster-mode).
4.  **Wait Mode**: Use the `--wait` flag to wait for build completion.

#### Mandatory Pre-Build Checks
Before triggering a build for any Go-based service, you MUST run `go vet` to catch potential formatting errors (e.g., mismatched Printf arguments) or structural issues.
1.  Navigate to the service directory (e.g., `services/db-adapter`).
2.  Run: `go vet ./...`
3.  Fix all reported errors before proceeding with `build.sh`.
5.  **Example Command**:
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
      "cd /mnt/hegemon-share/share/code/complete-build && \
       bash ./rag-stack/build.sh --mode cluster --wait"
    ```

### 3.2 Build Monitoring & Registry Maintenance

#### Monitoring Builds
- **Jobs**: Check Kaniko job status in the `build-pipeline` namespace: `kubectl get jobs -n build-pipeline`
- **Logs**: `kubectl logs -n build-pipeline deploy/build-orchestrator --tail=100`
- **Build Status Dashboard**: SSE-based live updates on port **8080**.

#### Registry Maintenance (Pruning)
To keep the registry clean, use the `registry-prune.sh` script to remove old image versions.
```bash
# On hierophant:
bash scripts/registry-prune.sh
```
After pruning, run garbage collection on the in-cluster registry pod:
```bash
/home/k8s/kube/kubectl exec -n container-registry deployment/registry -- registry garbage-collect /etc/docker/registry/config.yml
```

#### Verifying Images in Registry
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "for svc in rag-worker llm-gateway db-adapter qdrant-adapter \
              rag-ingestion object-store-mgr rag-test-runner \
              rag-admin-api memory-controller; do \
     echo \"\$svc: \$(curl -sk https://registry.hierocracy.home:5000/v2/\$svc/tags/list)\"; \
   done"
```

### 3.3 Host-Based Bootstrap Build
Use this only for bootstrapping or when the cluster-native pipeline is unavailable.
1.  **Script**: `rag-stack/build-and-push.sh`.
2.  **Journaling**: Use `/home/junie/rag-build-journals` or `/tmp/.rag-build`.
3.  **Example Command**:
    ```bash
    ./run-on-hierophant.sh "cd /mnt/hegemon-share/share/code/complete-build/rag-stack && VERSION=X.Y.Z FORCE_BUILD=true ./build-and-push.sh"
    ```

### 3.5 Concurrency and Locking in Build System
As of version `2.10.x`, the build system supports hardened parallel execution to improve speed and prevent race conditions.

#### Build Orchestrator Hardening (Double-Launching Fix)
1.  **Deterministic Job Naming**: The `build-orchestrator` now uses a deterministic naming scheme for Kaniko jobs: `kaniko-build-<service>-<version>`. 
2.  **Duplicate Prevention**: 
    -   **Pulsar Level**: Even if multiple Pulsar messages are sent for the same service/version (e.g., from overlapping `build.sh` runs), Kubernetes will reject the second job creation with an `AlreadyExists` error.
    -   **Pre-check**: The orchestrator checks if a job already exists and is succeeded/active *before* queuing a task, avoiding redundant status events and duplicate work.
3.  **Concurrency**: `MAX_CONCURRENT_BUILDS` is set to **4** (configured in `orchestrator-deployment.yaml`).

#### Build Script Locking (build.sh)
1.  **Global Atomic Lock**: `build.sh` uses a global lock directory `/tmp/rag-stack-build.lock`. This lock is shared across ALL users on **hierophant**, preventing concurrent script executions from interfering with each other's versioning and hashing.
2.  **Version File Lock**: `update_svc_info` uses `flock` on `/tmp/rag-stack-version-shared.lock` to ensure atomic updates to `CURRENT_VERSION`.
3.  **Permissions and Multi-User Support**:
    - Lock files in `/tmp` are created with `666` permissions where possible to allow both `wjones` and `junie` to manage them.
    - If a lock is held by a dead process (checked via PID), it is automatically cleared.
    - The `CURRENT_VERSION` file must have group-write permissions (`chmod 666`) for the `super-user` group.
4.  **Parallel Loops**:
    -   **Skip-and-Deploy**: Services that are already built but need a deployment update are processed in parallel (default 4).
    -   **Service Builds**: New builds are processed in parallel (default 4) using background subshells and `set -m` for job control.

#### Test Data Cleanup
1.  **Automated Cleanup**: A `rag-test-cleanup` job runs before each E2E test. It removes any data with `test-`, `iso-`, or `e2e-` prefixes from TimescaleDB and Qdrant.
2.  **Aggressive Deletion**: The cleanup job is configured with `RETAIN_RUNS=0`, meaning it wipes all matching data to ensure a pristine state for the next run.
3.  **ID-Based Cleanup**: E2E tests (`main.go`, `integration_test.py`) explicitly record and delete the specific `tag_id` and `session_id` they create.
4.  **Database Cascades**: Deleting a session in TimescaleDB automatically cleans up all associated prompts, responses, and session tags via `ON DELETE CASCADE`.

#### Manual Overrides
To force a build or change parallelism:
```bash
# Force rebuild of a specific service
FORCE_BUILD=true bash ./rag-stack/build.sh --service db-adapter
# Change parallelism for this run
PARALLELISM=8 bash ./rag-stack/build.sh
```

## 4. Data & Model Management

### 4.1 Database Migrations & Secrets (TimescaleDB)
Manual schema updates should be applied from **hierophant** using the provided SQL files.
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
   export DB_PASS=\$(/home/k8s/kube/kubectl get secret timescaledb-app -n timescaledb -o jsonpath='{.data.password}' | base64 -d) && \
   /home/k8s/kube/kubectl exec -it -n timescaledb timescaledb-rw-0 -- \
   env PGPASSWORD=\$DB_PASS psql -U app -d app -f /mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/timescaledb/iteration-7-phase1-memory.sql"
```

#### TimescaleDB Secret
The `timescaledb-secret` in rag-system is created dynamically during install by `setup-all.sh`.
It fetches the real password from the `timescaledb-app` secret. **Do NOT use the hardcoded template file**.

### 4.2 Ent ORM Management (Shared)
Centralized in the **common** module.
1.  **Schema Definition**: `rag-stack/services/common/ent/schema/`.
2.  **Code Generation**: `go run -mod=mod entgo.io/ent/cmd/ent generate --feature sql/upsert ./ent/schema`
3.  **Service Integration**: Use client from `app-builds/common/ent`.

### 4.3 Storage and Collection Naming
- **Base Name**: Use `vectors`.
- **Dimension-Based**: Collections are named `vectors-<dim>` (e.g., `vectors-384`).
- **Isolation**: Tag-based filtering uses strict `must` match with UUID `tag_ids`.

### 4.4 LLM Model Management (Ollama)

#### Pre-Pulling and Caching Models
Models are cached at `/mnt/storage/ollama-models/` and pushed to the local registry.
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "cd /mnt/hegemon-share/share/code/complete-build/rag-stack/infrastructure/ollama && \
   bash ./push-models-to-cluster.sh"
```

#### Model Seeding (During Install)
`seed-models.sh` creates temporary seeder pods that pull models from the local registry into the PVCs. 
- **Storage Path**: Models are seeded into the `models/` subdirectory of the PVC (e.g., `/root/.ollama/models/`) to match the default Ollama runtime configuration.
- **Robustness**: If `ollama pull` fails (e.g., due to registry protocol issues like "no Location header"), the script automatically falls back to a `curl`-based manual seed.
- **Automation**: This is automatic if models are in the registry.

### 2026-04-16 - Integration Testing Hardening
- **Reduced Logging Verbosity**: 
  - Suppressed internal Pulsar INFO logs (e.g., `ConnectionPool`, `ClientConnection`) in Python tests by configuring a dedicated logger set to `ERROR` level.
  - Standardized all test output (Go E2E and Python Integration) with UTC timestamps for clear start and end markers.
  - Minimized intermediate progress messages to focus on critical steps and errors.
- **Secret Code Validation**: Updated E2E and isolation tests to include a Unix timestamp in the 'secret code' and verify that retrieved context is within a 60-second window of the generation. Tests will now explicitly FAIL if the timestamp is missing or stale.
- **OpenTelemetry gRPC Migration**: Services now use OTLP gRPC exporters on port 4317 instead of HTTP on 4318 for better performance and reliability.
- **Logging Improvements**: 
  - Reduced verbosity in Pulsar CRUD and Aggregator tests.
  - Test scripts (`run-tests.sh`, `run-e2e-on-hierophant.sh`) no longer wipe the terminal.
  - Integration test logs are preserved in `/tmp/rag-logs/`.
- **Failure Scanning**: `run-tests.sh` now performs a comprehensive scan of the logs for errors, failures, and monitoring issues (e.g., OTEL 400 errors) and provides a summary.
- **Node Affinity**: Test jobs now use `nodeSelector: role: storage-node` to ensure they run on worker nodes.
- **API Paths**: Corrected several API paths in `api_health_test.py` to match the actual service implementations.
- **Database Schema Fix**: Added missing `metadata` column (JSONB) to `memory_items` table in `schema.sql` and migration files to ensure consistency with Ent ORM models.

## 5. RAG Stack Architecture & Services

- **Internal API TLS**: Switched `rag-admin-api` to use plain HTTP (port 8080) for internal communication with Traefik to resolve certificate verification issues (`bad certificate` error) when using mkcert-signed certificates.
- **Node Affinity**: Ensure all non-inference pods use `nodeSelector: role: storage-node` to keep inference nodes available for GPU workloads.
- **UI Timeout Fix (v2.5.0)**: Resolved `TimeoutException` in `rag-explorer` by explicitly canceling stream subscriptions upon receiving the `isLast` flag and suppressing idle timeouts in the `onError` handler. Increased default timeout to 120s.

### 5.1 Service Configuration (Externalized Values)
- **RAG Ingestion**: `QDRANT_COLLECTION`, `INGEST_BATCH_SIZE`, `CHUNK_SIZE`, `CHUNK_OVERLAP`.
- **RAG Worker**: `QDRANT_COLLECTION`, `QDRANT_SEARCH_LIMIT`, `RECURSION_BUDGET`.
- **LLM Gateway**: `REQUEST_TIMEOUT` (Pulsar inference).

### 5.2 Prompt Aggregation (Session Topics)
Migrated to session-specific Pulsar topics to eliminate linear scanning.
- **Session Topics**: `persistent://rag-pipeline/sessions/<correlation_id>`
- **LLM Gateway**: Subscribes to the session topic for streaming.
- **RAG Worker**: Produces `StreamChunk` messages to the session topic.
- **Prompt Aggregator**: Aggregates all chunks from the session topic after completion.
- **Pulsar Namespace**: `rag-pipeline/sessions` (policies: 5m deletion, 30m TTL).

### 5.3 Health and Readiness Checks
All RAG services implement standardized endpoints:
-   `/healthz` (Liveness): Returns `200 OK` if the process is running.
-   `/readyz` (Readiness): Returns `200 OK` only if downstream dependencies are reachable.
-   `/api/health/all` (Admin API): Aggregates results from all services into a single JSON report.

#### Manual Verification
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && \
   /home/k8s/kube/kubectl exec -n rag-system deploy/rag-admin-api -- \
   curl -sk https://localhost:8080/api/health/all"
```

### 5.5 Excluded Services (TEMPORARY)
The following services are intentionally excluded from the standard build and deployment process to optimize cluster resources and development focus.
- **rag-explorer**: Removed from `SERVICES` in `build.sh` and commented out in `setup-all.sh`.
- **Note**: DO NOT add these services back to the build or deployment scripts unless explicitly instructed by the user.

## 6. Frontend Development (RAG Explorer - EXCLUDED)

### 6.1 Features and Routing
The RAG Explorer is the Flutter-based web application for managing the cluster.
- **Session Management**: Friendly names, selective chat.
- **LLM Interaction**: Waiting indicators, streaming chunks.
- **System Logging**: Flyout log panel with real-time feedback and source location propagation.
- **BFF Connectivity**: Proxied via `rag-admin-api` with standardized root-relative paths.

### 6.2 Local Development & Troubleshooting

#### Environment Setup (Fedora)
```bash
bash scripts/setup-flutter-linux.sh
```

#### Running Locally
```bash
cd rag-stack/services/rag-explorer
flutter run -d linux # Desktop app
flutter run -d chrome # Web browser
```

#### Troubleshooting (Flutter)
- **CMake Error**: Run `flutter clean` to resolve stale `CMAKE_INSTALL_PREFIX` issues.
- **Code Generation**: `flutter pub run build_runner build --delete-conflicting-outputs`

### 6.3 Cluster Deployment (EXCLUDED)
1. **Build**: Trigger Kaniko build on hierophant (Manual only).
2. **Deploy**: UI is currently EXCLUDED from `setup-all.sh`.
3. **Verification**: `https://rag-explorer.rag.hierocracy.home`

## 7. Testing & Verification

### 7.0 Pre-Test Verification (CRITICAL)
Before executing any integration or E2E tests, you MUST verify that the cluster state is stable at the pod level. Simply checking that a Deployment is "Ready" or has "Available" replicas is insufficient, as it may be in the middle of a rolling update or have stale replicas from a previous version.

**Verification Steps**:
1.  **Version Check**: Ensure all pods in the `rag-system` namespace are using the target image version (e.g., `2.10.1`).
2.  **Pod Health**: Verify that NO pods are in `Pending`, `ImagePullBackOff`, `CrashLoopBackOff`, or `Error` states.
3.  **Replica Set Cleanliness**: Ensure there are no stale pods from previous ReplicaSets hanging around.
4.  **Command**:
    ```bash
    kubectl get pods -n rag-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
    ```
5.  **Stop Condition**: If any pod is not `Running` (or `Succeeded` for jobs) or is using an incorrect version, STOP and wait for the rollout to complete or fix the underlying issue before proceeding to tests.

### 7.1 Integration Tests (Python)
The integration test suite verifies the functionality of individual components and their interactions.
- **Location**: `rag-stack/tests/`
- **Tests**:
    - `aggregator_test.py`: Verifies basic chunk aggregation flow.
    - `aggregator_failure_test.py`: Verifies aggregation with special characters, embedded JSON, and edge cases (null bytes, quotes, UTF-8).
    - `pulsar_crud_test.py`: Verifies Pulsar topic creation and message processing.
- **Execution**:
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
      "cd /mnt/hegemon-share/share/code/complete-build && \
       bash rag-stack/tests/run-tests.sh"
    ```

### 7.2 End-to-End (E2E) Tests (Go)
The E2E test suite verifies the entire RAG pipeline from file upload to chat response.
- **Location**: `rag-stack/tests/main.go`
- **Execution**:
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
      "cd /mnt/hegemon-share/share/code/complete-build && \
       bash rag-stack/tests/run-e2e-on-hierophant.sh"
    ```
- **Verification**: Checks for specific "secret codes" in the LLM response to ensure successful context retrieval and inference.

### 7.3 Log Scanning (CRITICAL)
Simply having a test Job "Complete" or "Success" is insufficient. A manual or script-based scan of the logs MUST be performed after every test run to identify hidden errors, monitoring failures (e.g., OTLP exporters), or partial data losses.
- **Scripts**: `run-tests.sh` and `run-e2e-on-hierophant.sh` both perform an automatic scan at the end.
- **Manual Scan**: Check the latest logs in `/tmp/rag-logs/` on hierophant. Look for:
  - `[ERROR]`, `[FAIL]`, `[FAILURE]`
  - `Exception:`, `Panic:`, `stale timestamp`
  - `Failed to export` (OpenTelemetry issues)
  - `SyntaxError`, `can't open file`

### 7.4 Cross-Model Verification
Verifies multiple LLM model combinations (e.g., Llama + Granite).
```bash
ssh -i ~/.ssh/id_hierophant_access junie@hierophant \
  "export VERSION=2.6.1 && cd /mnt/hegemon-share/share/code/complete-build/rag-stack/tests && bash ./run-cross-model-tests.sh"
```

### 7.5 DB Adapter Unit Tests (Ent/SQLite)
The `db-adapter` service includes a comprehensive unit test suite using an in-memory SQLite database via the Ent ORM. These tests verify metrics persistence, health calculation, auditing, Virtual FS, and tag merging logic.
- **Location**: `rag-stack/services/db-adapter/cmd/adapter/handlers_test.go`
- **Execution**:
    ```bash
    cd rag-stack/services/db-adapter
    go test -v ./cmd/adapter/...
    ```
- **Coverage**: Includes `handleCompletion`, `handleGetSessionHealth`, `handleGetSessionAudit`, `handleGetSessionMessages`, `handleGetFiles`, and `handleMaintenanceTagMerge`.

## 8. RAG Explorer & Metrics (Iteration 6b)
### 8.1 Model Execution Metrics (3NF)
Model performance is tracked in the `model_execution_metrics` hypertable in TimescaleDB. 
Dimensions:
- `inference_nodes`: Track GPU/CPU stats per node.
- `model_definitions`: Track model family and parameters.

### 8.2 Virtual Filesystem
The S3 browser in RAG Explorer is "virtual" — it queries the database metadata (`code_ingestion` and `code_embedding`) rather than S3 directly for faster filtering and sync status verification.

### 8.3 Tag Maintenance
Tag merging is performed via the `/api/db/maintenance/tags/merge` endpoint. This coordinates a "Clean-and-Reingest" process to ensure data consistency and de-duplication:
1. Identifies all unique S3 file paths associated with the source tags.
2. Atomically deletes existing embeddings for these paths from TimescaleDB and Qdrant.
3. Groups paths by their new combined tag set (current tags minus sources plus target).
4. Triggers the `rag-ingestion` service for each group to re-process the files from S3 with updated tags.
5. Updates session-tag mappings and deletes the source tag entities from the database.

### 8.4 Session-Tag Association
The Chat Panel in RAG Explorer supports associating multiple existing tags with a session to scope the RAG context.
- **Fetch**: Existing tags are retrieved from `GET /api/db/tags` (proxied via `rag-admin-api`).
- **Logic**: Multi-pick selection is handled via a modal dialog with search and "add new" capabilities.
- **Usage**: Selected tags are sent as `tag_names` in the `streamChat` request to the pipeline.

## 9. Cluster Build System

### 9.1 Shared Build State (CURRENT_VERSION)
The `CURRENT_VERSION` file tracks service versions across all environments.
- **Location**: Project root (`/mnt/hegemon-share/share/code/complete-build/CURRENT_VERSION`).
- **Permissions**: Should be `664` or `666` to allow both `wjones` and `junie` to update it.
- **DANGER**: DO NOT use `mv` to update this file. Using `mv` replaces the file and resets permissions to the user's default umask (usually `644`), which breaks the build pipeline for other users. ALWAYS use redirection (e.g., `cat tmp > CURRENT_VERSION` or `jq ... > tmp && cat tmp > CURRENT_VERSION`) to preserve existing permissions.
- **Workaround**: If `Permission denied` occurs on `hierophant`, update the file from the local VM at `/mnt/hegemon-share/share/code/complete-build/CURRENT_VERSION`.
- **Parallel Builds**: `build.sh` supports multiple `--service` arguments to trigger parallel Kaniko builds on the cluster.
### 9.2 Response Aggregation
To prevent duplicate "chunks" in chat history, the `db-adapter` consolidates multiple Pulsar messages for the same prompt into a single database record.
- **Aggregation**: `HandleResponse` uses a transaction to find an existing record by `prompt_id`.
- **Deltas**: Content chunks are appended to the existing record.
- **Final Results**: Aggregated messages from `prompt-aggregator` (with `is_last=true`) overwrite the content to ensure accuracy.
- **Planning Data**: Sub-queries from `rag-worker` are accumulated in the `planning_response` field.
- **History**: `GetMessages` groups any legacy duplicate records by `prompt_id` before returning them to the UI.
