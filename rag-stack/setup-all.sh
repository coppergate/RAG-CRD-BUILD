#!/bin/bash

# setup-all.sh - Orchestrate the entire RAG stack deployment
# To be executed on host: hierophant

set -e

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export REPO_DIR
NAMESPACE="rag-system"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

source "${BASE_DIR:-$REPO_DIR/..}/scripts/journal-helper.sh"
init_journal

if ! is_step_done "namespace"; then
echo "--- 1. Creating Namespace ---"
$KUBECTL apply -f "$REPO_DIR/namespace.yaml"
mark_step_done "namespace"
fi

if ! is_step_done "ollama"; then
echo "--- 1.5. Deploying LLM: Ollama ---"
bash "$REPO_DIR/infrastructure/ollama/ollama.sh"
mark_step_done "ollama"
fi

if ! is_step_done "timescaledb"; then
echo "--- 2. Deploying Infrastructure: TimescaleDB ---"
$REPO_DIR/infrastructure/timescaledb/install.sh
$KUBECTL apply -f "$REPO_DIR/infrastructure/timescaledb/timescaledb-lb-service.yaml"
mark_step_done "timescaledb"
fi

if ! is_step_done "pulsar"; then
echo "--- 3. Deploying Infrastructure: Apache Pulsar ---"
$REPO_DIR/infrastructure/pulsar/install.sh
mark_step_done "pulsar"
fi

if ! is_step_done "qdrant"; then
echo "--- 4. Deploying Vector Database: Qdrant ---"
$KUBECTL apply -f "$REPO_DIR/infrastructure/qdrant/qdrant-pvc.yaml"
$KUBECTL apply -f "$REPO_DIR/infrastructure/qdrant/qdrant-deploy.yaml"
$KUBECTL apply -f "$REPO_DIR/infrastructure/qdrant/qdrant-service.yaml"
mark_step_done "qdrant"
fi

if ! is_step_done "s3-obc"; then
echo "--- 5. Provisioning S3 Object Store (Rook-Ceph) ---"
$KUBECTL apply -f "$REPO_DIR/infrastructure/obc.yaml"

echo "Waiting for S3 credentials..."
until $KUBECTL get secret rag-codebase-bucket -n $NAMESPACE >/dev/null 2>&1; do
  sleep 5
done
mark_step_done "s3-obc"
fi

if ! is_step_done "llm-gateway"; then
echo "--- 6. Deploying LLM Gateway (Go) ---"
$KUBECTL apply -f "$REPO_DIR/infrastructure/timescaledb/timescaledb-secret.yaml"
$KUBECTL apply -f "$REPO_DIR/services/llm-gateway/k8s/configmap.yaml"
$KUBECTL apply -f "$REPO_DIR/services/llm-gateway/k8s/deployment.yaml"
mark_step_done "llm-gateway"
fi

if ! is_step_done "rag-worker"; then
echo "--- 7. Deploying RAG Worker (Go) ---"
$KUBECTL apply -f "$REPO_DIR/services/rag-worker/k8s/deployment.yaml"
mark_step_done "rag-worker"
fi

if ! is_step_done "object-store-mgr"; then
echo "--- 8. Deploying Object Store Manager (Go) ---"
$KUBECTL apply -f "$REPO_DIR/services/object-store-mgr/mgr-deployment.yaml"
mark_step_done "object-store-mgr"
fi

if ! is_step_done "rag-web-ui"; then
echo "--- 9. Deploying RAG Web UI (Go) ---"
$KUBECTL apply -f "$REPO_DIR/services/rag-web-ui/ui-deployment.yaml"
mark_step_done "rag-web-ui"
fi

if ! is_step_done "db-adapter"; then
echo "--- 10. Deploying DB Adapter (Go) ---"
$KUBECTL apply -f "$REPO_DIR/services/db-adapter/k8s/deployment.yaml"
mark_step_done "db-adapter"
fi

if ! is_step_done "qdrant-adapter"; then
echo "--- 11. Deploying Qdrant Adapter (Go) ---"
$KUBECTL apply -f "$REPO_DIR/services/qdrant-adapter/k8s/deployment.yaml"
mark_step_done "qdrant-adapter"
fi

if ! is_step_done "ingestion-job"; then
echo "--- 12. Preparing Ingestion Pipeline ---"
$KUBECTL apply -f "$REPO_DIR/ingestion/ingest-job-s3.yaml"
mark_step_done "ingestion-job"
fi

clear_journal

echo "--- All Components Deployed ---"
echo "Check status: $KUBECTL get pods -n $NAMESPACE"
