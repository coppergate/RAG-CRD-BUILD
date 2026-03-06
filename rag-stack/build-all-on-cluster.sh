#!/bin/bash
# build-all-on-cluster.sh - Build all RAG images using the cluster-native pipeline
# Run on hierophant

set -Eeuo pipefail

VERSION="${VERSION:-1.5.7}"
WAIT_FOR_COMPLETION="${WAIT_FOR_COMPLETION:-false}"
if [[ "$1" == "--wait" ]]; then
    WAIT_FOR_COMPLETION="true"
fi

BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TRIGGER_SCRIPT="$BASE_DIR/infrastructure/build-pipeline/trigger-build.sh"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="build-pipeline"

services=(
    "db-adapter"
    "llm-gateway"
    "object-store-mgr"
    "qdrant-adapter"
    "rag-worker"
    "rag-web-ui"
    "rag-ingestion"
)
job_names=()

echo "===================================================="
echo "Triggering Cluster-Native Build for all services (v$VERSION)"
echo "===================================================="

for service in "${services[@]}"; do
    echo "Triggering build for $service..."
    bash "$TRIGGER_SCRIPT" "$service" "$VERSION"
    job_names+=("kaniko-build-${service}-${VERSION}")
    # Wait a bit to avoid overwhelming Pulsar or the Orchestrator
    sleep 2
done

if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
    echo ""
    echo "--- Waiting for builds to complete ---"
    for job in "${job_names[@]}"; do
        echo "Waiting for $job..."
        if ! $KUBECTL wait -n "$NAMESPACE" --for=condition=complete "job/$job" --timeout=45m; then
            echo "ERROR: Build job did not complete: $job"
            $KUBECTL get job "$job" -n "$NAMESPACE" -o wide || true
            $KUBECTL logs -n "$NAMESPACE" -l "job-name=$job" --tail=200 || true
            exit 1
        fi
    done
    echo "All builds completed successfully."
else
    echo ""
    echo "All builds triggered. Monitor progress with:"
    echo "kubectl get jobs -n build-pipeline"
fi
