# Operational Instructions

This document tracks basic tasks and procedures determined during development to ensure efficiency and avoid redundant logic parsing. These instructions are designed for the **Junie** agent to follow directly.

## Parallel Build and Push (Cluster-Native)
To build and push all RAG services in parallel using the cluster-native Kaniko pipeline:
1.  **Access Hierophant**: Use `./run-on-hierophant.sh`.
2.  **Versioning**: Set the `VERSION` environment variable (e.g., `X.Y.Z`).
3.  **Command**: Run `rag-stack/build-all-on-cluster.sh`.
4.  **Verification**: Monitor build jobs on the cluster.
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && /home/k8s/kube/kubectl get jobs -n rag-system"
    ```
5.  **Example Command**:
    ```bash
    ./run-on-hierophant.sh "cd /mnt/hegemon-share/share/code/complete-build/rag-stack && VERSION=X.Y.Z bash ./build-all-on-cluster.sh"
    ```

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

## TLS and Security
1.  **Architecture**: Refer to [TLS-SECURITY.md](TLS-SECURITY.md) for the end-to-end security architecture.
2.  **Trust Distribution**: The combined CA certificate is managed via the `registry-ca-cm` ConfigMap in target namespaces.
3.  **Client Configuration**: Ensure applications use the `SSL_CERT_FILE` environment variable (set to `/etc/ssl/certs/ca-certificates.crt`) for CA trust.
4.  **Verification**: Use `kubectl get certificate -A` to verify certificate status.

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

## Ent ORM Management (db-adapter)
The `db-adapter` service uses the **Ent ORM** for type-safe database access.
1.  **Schema Definition**: Schemas are located in `rag-stack/services/db-adapter/internal/ent/schema/`.
2.  **Code Generation**: If schemas are modified, regenerate the Ent client:
    -   **Command**: 
        ```bash
        cd rag-stack/services/db-adapter && go run -mod=mod entgo.io/ent/cmd/ent generate ./internal/ent/schema
        ```
3.  **Database Migration**: The service relies on the existing TimescaleDB schema. Ensure that Ent schemas match the database structure defined in `rag-stack/infrastructure/timescaledb/`.

## Headlamp Access
To get the login token for Headlamp:
1.  **Command**: Run the following on **hierophant**:
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && /home/k8s/kube/kubectl get secret headlamp-admin-token -n headlamp -o jsonpath='{.data.token}' | base64 -d"
    ```
2.  **Usage**: Copy the decrypted token and paste it into the Headlamp login page.
3.  **Role**: This token belongs to the `headlamp-admin` ServiceAccount and has `cluster-admin` privileges.
