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

# Apply unified application schema and privileges so 'app' owns and can access all objects
if ! is_step_done "db-schema"; then
echo "--- 2.1 Applying Unified Application Schema (TimescaleDB) ---"
DB_NAMESPACE="timescaledb"
DB_POD=$($KUBECTL get pods -n $DB_NAMESPACE -l "cnpg.io/cluster=timescaledb,role=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$DB_POD" ]; then
  echo "Waiting for TimescaleDB primary pod..."
  sleep 10
  DB_POD=$($KUBECTL get pods -n $DB_NAMESPACE -l "cnpg.io/cluster=timescaledb,role=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi
if [ -n "$DB_POD" ]; then
  echo "Ensuring role 'app' exists and has create on schema public"
  $KUBECTL exec -i -n $DB_NAMESPACE "$DB_POD" -- \
    sh -lc "psql -U postgres -d postgres -tc \"SELECT 1 FROM pg_roles WHERE rolname='app'\" | grep -q 1 || psql -U postgres -d postgres -c \"CREATE ROLE app LOGIN PASSWORD 'app'\""
  $KUBECTL exec -i -n $DB_NAMESPACE "$DB_POD" -- \
    psql -U postgres -d app -c "GRANT CONNECT ON DATABASE app TO app; GRANT USAGE, CREATE ON SCHEMA public TO app;"

  echo "Applying schema as role 'app' so objects are owned by app"
  $KUBECTL exec -i -n $DB_NAMESPACE "$DB_POD" -- psql -U app -d app < "$REPO_DIR/infrastructure/timescaledb/schema.sql"
  mark_step_done "db-schema"
else
  echo "ERROR: Could not find TimescaleDB primary pod to apply schema."
  exit 1
fi
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

# APM ConfigMap for tests and services to export OTEL traces
if ! is_step_done "apm-config"; then
echo "--- 4.1 Creating/Updating APM ConfigMap for OTLP endpoint ---"
APM_OTLP_ENDPOINT="${APM_OTLP_ENDPOINT:-http://alloy.observability.svc.cluster.local:4318}"
cat <<EOF | $KUBECTL -n $NAMESPACE apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: apm-config
data:
  OTEL_EXPORTER_OTLP_ENDPOINT: "$APM_OTLP_ENDPOINT"
EOF
mark_step_done "apm-config"
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
echo "--- 8. Running Object Store Manager Job (one-shot) ---"
# Remove old Deployment if it exists, then run the Job
$KUBECTL -n $NAMESPACE delete deploy/object-store-mgr --ignore-not-found
$KUBECTL apply -f "$REPO_DIR/services/object-store-mgr/mgr-job.yaml"
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
