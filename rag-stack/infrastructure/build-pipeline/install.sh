#!/bin/bash
# install.sh - Build Pipeline Infrastructure (S3 + Pulsar + Kaniko)
# To be executed on host: hierophant

set -e

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="build-pipeline"

source "$REPO_DIR/../../../scripts/journal-helper.sh"
init_journal

if ! is_step_done "build-pipeline-ns"; then
    echo "--- Creating Build Pipeline Namespace ---"
    # Extract the namespace from the manifest and apply it first
    $KUBECTL apply -f "$REPO_DIR/s3-build-storage.yaml" || {
        echo "Retrying namespace creation..."
        sleep 5
        $KUBECTL apply -f "$REPO_DIR/s3-build-storage.yaml"
    }
    mark_step_done "build-pipeline-ns"
fi

if ! is_step_done "build-orchestrator-image"; then
    echo "--- Bootstrapping Build Orchestrator Image (Cluster-Native) ---"
    bash "$REPO_DIR/bootstrap-orchestrator.sh"
    mark_step_done "build-orchestrator-image"
fi

if ! is_step_done "build-orchestrator"; then
    echo "--- Deploying Build Orchestrator ---"
    $KUBECTL apply -f "$REPO_DIR/orchestrator-deployment.yaml"
    mark_step_done "build-orchestrator"
fi

echo "Build Pipeline Infrastructure Setup Complete."
