#!/bin/bash
# install.sh - Build Pipeline Infrastructure (S3 + Pulsar + Kaniko)
# To be executed on host: hierophant

set -Eeuo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="build-pipeline"

source "$REPO_DIR/../../../scripts/journal-helper.sh"
init_journal

should_run_step() {
    local step_name="$1"
    local verify_cmd="$2"
    if ! is_step_done "$step_name"; then
        return 0
    fi
    if ! eval "$verify_cmd" >/dev/null 2>&1; then
        echo "Journal has '$step_name' but live verification failed. Re-running step..."
        return 0
    fi
    return 1
}

if should_run_step "build-pipeline-ns" "$KUBECTL get namespace $NAMESPACE"; then
    echo "--- Creating Build Pipeline Namespace ---"
    # Extract the namespace from the manifest and apply it first
    $KUBECTL apply -f "$REPO_DIR/s3-build-storage.yaml" || {
        echo "Retrying namespace creation..."
        sleep 5
        $KUBECTL apply -f "$REPO_DIR/s3-build-storage.yaml"
    }
    mark_step_done "build-pipeline-ns"
fi

if should_run_step "build-orchestrator-image" "$KUBECTL get namespace $NAMESPACE"; then
    echo "--- Bootstrapping Build Orchestrator Image (Cluster-Native) ---"
    bash "$REPO_DIR/bootstrap-orchestrator.sh"
    mark_step_done "build-orchestrator-image"
fi

if should_run_step "build-orchestrator" "$KUBECTL get deployment build-orchestrator -n $NAMESPACE"; then
    echo "--- Deploying Build Orchestrator ---"
    $KUBECTL apply -f "$REPO_DIR/orchestrator-deployment.yaml"
    mark_step_done "build-orchestrator"
fi

echo "Build Pipeline Infrastructure Setup Complete."
