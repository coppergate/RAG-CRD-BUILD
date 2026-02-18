#!/bin/bash
# update-to-iteration-4.sh - Safely migrate the RAG stack to Iteration 4
# To be executed on host: hierophant

set -e

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NAMESPACE="rag-system"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

echo "--- 1. Updating TimescaleDB Cluster & Secret ---"
bash "$REPO_DIR/infrastructure/timescaledb/update-timescaledb-cr.sh"
$KUBECTL apply -f "$REPO_DIR/infrastructure/timescaledb/timescaledb-lb-service.yaml"

echo "--- 2. Applying Database Schema (Iteration 4) ---"
# We need to find the primary pod to run the schema
TS_POD=$($KUBECTL get pods -n timescaledb -l "cnpg.io/cluster=timescaledb,role=primary" -o jsonpath='{.items[0].metadata.name}')
if [ -z "$TS_POD" ]; then
    echo "Waiting for TimescaleDB primary pod..."
    sleep 10
    TS_POD=$($KUBECTL get pods -n timescaledb -l "cnpg.io/cluster=timescaledb,role=primary" -o jsonpath='{.items[0].metadata.name}')
fi

if [ -n "$TS_POD" ]; then
    echo "Applying schema to $TS_POD..."
    $KUBECTL exec -i -n timescaledb "$TS_POD" -- psql -U app app < "$REPO_DIR/infrastructure/timescaledb/iteration-4-schema.sql"
else
    echo "ERROR: Could not find TimescaleDB primary pod. Please ensure the cluster is running."
    exit 1
fi

echo "--- 3. Updating ConfigMaps and Deployments ---"

# LLM Gateway
echo "Updating LLM Gateway..."
$KUBECTL apply -f "$REPO_DIR/services/llm-gateway/k8s/configmap.yaml"
$KUBECTL create configmap llm-gateway-source -n $NAMESPACE \
  --from-file=main.go="$REPO_DIR/services/llm-gateway/cmd/gateway/main.go" \
  --from-file=config.go="$REPO_DIR/services/llm-gateway/internal/config/config.go" \
  --from-file=openai.go="$REPO_DIR/services/llm-gateway/internal/handlers/openai.go" \
  --from-file=client.go="$REPO_DIR/services/llm-gateway/internal/pulsar/client.go" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL apply -f "$REPO_DIR/services/llm-gateway/k8s/deployment.yaml"

# RAG Worker
echo "Updating RAG Worker..."
$KUBECTL create configmap rag-worker-source -n $NAMESPACE \
  --from-file=main.go="$REPO_DIR/services/rag-worker/cmd/worker/main.go" \
  --from-file=config.go="$REPO_DIR/services/rag-worker/internal/config/config.go" \
  --from-file=ollama_client.go="$REPO_DIR/services/rag-worker/internal/ollama/client.go" \
  --from-file=qdrant_client.go="$REPO_DIR/services/rag-worker/internal/qdrant/client.go" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL apply -f "$REPO_DIR/services/rag-worker/k8s/deployment.yaml"

# Object Store Manager
echo "Updating Object Store Manager..."
$KUBECTL create configmap rag-s3-mgr-source -n $NAMESPACE \
  --from-file=main.go="$REPO_DIR/services/object-store-mgr/cmd/manager/main.go" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL apply -f "$REPO_DIR/services/object-store-mgr/mgr-deployment.yaml"

# RAG Web UI
echo "Updating RAG Web UI..."
$KUBECTL create configmap rag-web-ui-source -n $NAMESPACE \
  --from-file=main.go="$REPO_DIR/services/rag-web-ui/cmd/ui/main.go" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL apply -f "$REPO_DIR/services/rag-web-ui/ui-deployment.yaml"

# DB Adapter (New Service)
echo "Deploying DB Adapter..."
$KUBECTL create configmap db-adapter-source -n $NAMESPACE \
  --from-file=main.go="$REPO_DIR/services/db-adapter/cmd/adapter/main.go" \
  --from-file=config.go="$REPO_DIR/services/db-adapter/internal/config/config.go" \
  --from-file=go.mod="$REPO_DIR/services/db-adapter/go.mod" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL apply -f "$REPO_DIR/services/db-adapter/k8s/deployment.yaml"

echo "--- 4. Finalizing Rollout ---"
$KUBECTL rollout status deployment/llm-gateway -n $NAMESPACE
$KUBECTL rollout status deployment/rag-worker -n $NAMESPACE
$KUBECTL rollout status deployment/rag-web-ui -n $NAMESPACE
$KUBECTL rollout status deployment/db-adapter -n $NAMESPACE

echo "--- Migration to Iteration 4 Complete ---"
