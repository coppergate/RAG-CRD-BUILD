#!/bin/bash
# update-timescaledb-cr.sh - Update TimescaleDB Custom Resources and Secrets
# To be executed on host: hierophant

set -e

NAMESPACE_TS="timescaledb"
NAMESPACE_RAG="rag-system"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Adjust if the script is moved, but based on typical layout:
# rag-stack/infrastructure/timescaledb/update-timescaledb-cr.sh

echo "--- Updating TimescaleDB Cluster CR ---"
$KUBECTL apply -f "$REPO_DIR/cluster.yaml" --server-side --force-conflicts

echo "--- Updating TimescaleDB Connection Secret ---"
$KUBECTL apply -f "$REPO_DIR/timescaledb-secret.yaml"

echo "--- Restarting dependent deployments to pick up changes ---"
for deploy in llm-gateway db-adapter rag-web-ui; do
    if $KUBECTL get deployment "$deploy" -n $NAMESPACE_RAG >/dev/null 2>&1; then
        echo "Restarting $deploy..."
        $KUBECTL rollout restart deployment "$deploy" -n $NAMESPACE_RAG
    else
        echo "Skipping restart for $deploy (not found)"
    fi
done

echo "Update process completed."
echo "Check cluster status: $KUBECTL get cluster -n $NAMESPACE_TS"
