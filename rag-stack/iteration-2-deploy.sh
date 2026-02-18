#!/bin/bash
# iteration-2-deploy.sh - Deploy Iteration 2 components (Schema & Services)
# To be executed on host: hierophant

set -e

REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="rag-system"
DB_NAMESPACE="timescaledb"

echo "--- 1. Applying Database Schema Updates (Iteration 2) ---"
# We use the primary pod of the timescaledb cluster to apply the schema
DB_POD=$($KUBECTL get pods -n $DB_NAMESPACE -l "cnpg.io/cluster=timescaledb,role=primary" -o name | head -n 1)

if [ -z "$DB_POD" ]; then
    echo "Error: Could not find primary TimescaleDB pod."
    exit 1
fi

echo "Found primary DB pod: $DB_POD"

# Apply schema to database
# We ensure the 'app' database exists as the services are configured to use it
$KUBECTL exec -i -n $DB_NAMESPACE "$DB_POD" -- psql -U postgres -d app < "$REPO_DIR/infrastructure/timescaledb/schema.sql"

echo "--- 2. Redeploying Updated Services ---"

echo "Deploying LLM Gateway..."
$KUBECTL apply -f "$REPO_DIR/infrastructure/timescaledb/timescaledb-secret.yaml"
$KUBECTL apply -f "$REPO_DIR/services/llm-gateway/k8s/configmap.yaml"
$KUBECTL create configmap llm-gateway-source -n $NAMESPACE \
  --from-file=main.go="$REPO_DIR/services/llm-gateway/cmd/gateway/main.go" \
  --from-file=config.go="$REPO_DIR/services/llm-gateway/internal/config/config.go" \
  --from-file=openai.go="$REPO_DIR/services/llm-gateway/internal/handlers/openai.go" \
  --from-file=client.go="$REPO_DIR/services/llm-gateway/internal/pulsar/client.go" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL apply -f "$REPO_DIR/services/llm-gateway/k8s/deployment.yaml"
$KUBECTL rollout restart deployment/llm-gateway -n $NAMESPACE

echo "Deploying RAG Worker..."
$KUBECTL create configmap rag-worker-source -n $NAMESPACE \
  --from-file=main.go="$REPO_DIR/services/rag-worker/cmd/worker/main.go" \
  --from-file=config.go="$REPO_DIR/services/rag-worker/internal/config/config.go" \
  --from-file=ollama_client.go="$REPO_DIR/services/rag-worker/internal/ollama/client.go" \
  --from-file=qdrant_client.go="$REPO_DIR/services/rag-worker/internal/qdrant/client.go" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL apply -f "$REPO_DIR/services/rag-worker/k8s/deployment.yaml"
$KUBECTL rollout restart deployment/rag-worker -n $NAMESPACE

echo "Deploying RAG Web UI..."
$KUBECTL create configmap rag-web-ui-source -n $NAMESPACE \
  --from-file=main.go="$REPO_DIR/services/rag-web-ui/cmd/ui/main.go" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL apply -f "$REPO_DIR/services/rag-web-ui/ui-deployment.yaml"
$KUBECTL rollout restart deployment/rag-web-ui -n $NAMESPACE
$KUBECTL rollout status deployment/rag-web-ui -n $NAMESPACE

echo "Updating Ingestion Job..."
$KUBECTL apply -f "$REPO_DIR/ingestion/ingest-job-s3.yaml"

echo "--- Iteration 2 Deployment Completed ---"
echo "Check status: $KUBECTL get pods -n $NAMESPACE"
