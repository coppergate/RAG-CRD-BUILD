# Operational Instructions

This document tracks basic tasks and procedures determined during development to ensure efficiency and avoid redundant logic parsing. These instructions are designed for the **Junie** agent to follow directly.

## Parallel Build and Push (Cluster-Native)
To build and push all RAG services in parallel using the cluster-native Kaniko pipeline:
1.  **Access Hierophant**: Use `./run-on-hierophant.sh`.
2.  **Versioning**: Set the `VERSION` environment variable (e.g., `1.6.1`).
3.  **Command**: Run `rag-stack/build-all-on-cluster.sh`.
4.  **Verification**: Monitor build jobs on the cluster.
    ```bash
    ssh -i ~/.ssh/id_hierophant_access junie@hierophant "export KUBECONFIG=/home/k8s/kube/config/kubeconfig && /home/k8s/kube/kubectl get jobs -n rag-system"
    ```
5.  **Example Command**:
    ```bash
    ./run-on-hierophant.sh "cd /mnt/hegemon-share/share/code/complete-build/rag-stack && VERSION=1.6.1 bash ./build-all-on-cluster.sh"
    ```

## Local/Bootstrap Build and Push (Host-Based)
Use this only for bootstrapping or when the cluster-native pipeline is unavailable.
1.  **Script**: `rag-stack/build-and-push.sh`.
2.  **Journaling**: Use a local directory for journaling to avoid shared mount permission issues.
    -   Example: `JOURNAL_DIR=/tmp/.rag-build`
3.  **Force Build**: Use `FORCE_BUILD=true` to ensure fresh builds when code is modified.
4.  **Example Command**:
    ```bash
    ./run-on-hierophant.sh "cd /mnt/hegemon-share/share/code/complete-build/rag-stack && VERSION=1.6.1 FORCE_BUILD=true JOURNAL_DIR=/tmp/.rag-build ./build-and-push.sh"
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
    ./run-on-hierophant.sh "export VERSION=1.6.1 && bash /mnt/hegemon-share/share/code/complete-build/rag-stack/tests/run-e2e-on-hierophant.sh"
    ```

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
