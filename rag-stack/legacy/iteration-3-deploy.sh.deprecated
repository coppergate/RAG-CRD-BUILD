#!/bin/bash
# iteration-3-deploy.sh - Deploy Iteration 3 components (Schema & Services)
# To be executed on host: hierophant

set -e

REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="rag-system"
DB_NAMESPACE="timescaledb"

echo "--- 1. Applying Database Schema Updates (Iteration 3) ---"
# We use the primary pod of the timescaledb cluster to apply the schema
DB_POD=$($KUBECTL get pods -n $DB_NAMESPACE -l "cnpg.io/cluster=timescaledb,role=primary" -o name | head -n 1)

if [ -z "$DB_POD" ]; then
    echo "Error: Could not find primary TimescaleDB pod."
    exit 1
fi

echo "Found primary DB pod: $DB_POD"

# Apply schema as role 'app' to database
# We ensure the 'app' database exists as the services are configured to use it
(echo "SET ROLE app;"; cat "$REPO_DIR/infrastructure/timescaledb/schema.sql") | \
  $KUBECTL exec -i -n $DB_NAMESPACE "$DB_POD" -- psql -U postgres -d app

echo "--- 2. Redeploying Updated Services ---"

echo "Deploying LLM Gateway..."
$KUBECTL apply -f "$REPO_DIR/infrastructure/timescaledb/timescaledb-secret.yaml"
$KUBECTL apply -f "$REPO_DIR/services/llm-gateway/k8s/configmap.yaml"
$KUBECTL apply -f "$REPO_DIR/services/llm-gateway/k8s/deployment.yaml"
$KUBECTL rollout restart deployment/llm-gateway -n $NAMESPACE

echo "Deploying RAG Worker..."
$KUBECTL apply -f "$REPO_DIR/services/rag-worker/k8s/deployment.yaml"
$KUBECTL rollout restart deployment/rag-worker -n $NAMESPACE

echo "Deploying RAG Ingestion Service..."
$KUBECTL apply -f "$REPO_DIR/services/rag-ingestion/k8s/deployment.yaml"
$KUBECTL rollout restart deployment/rag-ingestion-service -n $NAMESPACE

echo "Deploying RAG Web UI..."
$KUBECTL apply -f "$REPO_DIR/services/rag-web-ui/ui-deployment.yaml"
$KUBECTL rollout restart deployment/rag-web-ui -n $NAMESPACE
$KUBECTL rollout status deployment/rag-web-ui -n $NAMESPACE

echo "--- Iteration 3 Deployment Completed ---"
echo "Check status: $KUBECTL get pods -n $NAMESPACE"
