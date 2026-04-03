#!/bin/bash

# setup-all.sh - Orchestrate the entire RAG stack deployment
# To be executed on host: hierophant

set -Eeuo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export REPO_DIR
NAMESPACE="rag-system"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
VERSION="${VERSION:-2.4.2}"
REGISTRY="${REGISTRY:-registry.container-registry.svc.cluster.local:5000}"

source "${BASE_DIR:-$REPO_DIR/..}/scripts/journal-helper.sh"
init_journal

apply_manifest() {
  local manifest="$1"
  sed -e "s#__VERSION__#${VERSION}#g" -e "s#registry.hierocracy.home:5000#${REGISTRY}#g" "$manifest" | "$KUBECTL" apply -f -
}

if ! is_step_done "namespace"; then
echo "--- 1. Creating Namespace ---"
$KUBECTL apply -f "$REPO_DIR/namespace.yaml"
mark_step_done "namespace"
fi

if ! is_step_done "rag-system-tls"; then
echo "--- 1.1 Applying RAG System TLS Certificates ---"
$KUBECTL apply -f "$REPO_DIR/infrastructure/rag-system-tls.yaml"
echo "Waiting for RAG System certificates to be issued..."
$KUBECTL wait --for=condition=Ready certificate/llm-gateway-cert -n $NAMESPACE --timeout=60s
$KUBECTL wait --for=condition=Ready certificate/rag-ingestion-cert -n $NAMESPACE --timeout=60s
$KUBECTL wait --for=condition=Ready certificate/rag-web-ui-cert -n $NAMESPACE --timeout=60s
$KUBECTL wait --for=condition=Ready certificate/db-adapter-cert -n $NAMESPACE --timeout=60s
$KUBECTL wait --for=condition=Ready certificate/qdrant-adapter-cert -n $NAMESPACE --timeout=60s
$KUBECTL wait --for=condition=Ready certificate/rag-admin-api-cert -n $NAMESPACE --timeout=60s
$KUBECTL wait --for=condition=Ready certificate/object-store-mgr-cert -n $NAMESPACE --timeout=60s
$KUBECTL wait --for=condition=Ready certificate/memory-controller-cert -n $NAMESPACE --timeout=60s
$KUBECTL wait --for=condition=Ready certificate/rag-worker-cert -n $NAMESPACE --timeout=60s
$KUBECTL wait --for=condition=Ready certificate/rag-explorer-cert -n $NAMESPACE --timeout=60s
mark_step_done "rag-system-tls"
fi

# Inject Registry & Pulsar CA ConfigMap into rag-system
echo "--- Injecting Combined Registry & Pulsar CA into $NAMESPACE ---"
mkdir -p "$SAFE_TMP_DIR"
COMBINED_CA="$SAFE_TMP_DIR/combined-ca.crt"
rm -f "$COMBINED_CA"
touch "$COMBINED_CA"

# 1. Extract Registry CA
if $KUBECTL get secret in-cluster-registry-tls -n container-registry >/dev/null 2>&1; then
    echo "Extracting Registry CA from container-registry/in-cluster-registry-tls..."
    $KUBECTL get secret in-cluster-registry-tls -n container-registry -o jsonpath='{.data.ca\.crt}' | base64 --decode >> "$COMBINED_CA"
else
    echo "Fallback: Extracting Registry CA from Talos registry patch..."
    CA_B64=$(grep "ca: " "$REPO_DIR/../infrastructure/registry/talos-registry-patch.yaml" | head -n 1 | awk '{print $2}')
    if [ -n "$CA_B64" ]; then
        echo "$CA_B64" | base64 -d >> "$COMBINED_CA"
    fi
fi

# 2. Extract Pulsar CA
if $KUBECTL get secret pulsar-ca-tls -n apache-pulsar >/dev/null 2>&1; then
    echo "Extracting Pulsar CA from apache-pulsar/pulsar-ca-tls..."
    echo "" >> "$COMBINED_CA" # Ensure newline
    $KUBECTL get secret pulsar-ca-tls -n apache-pulsar -o jsonpath='{.data.ca\.crt}' | base64 --decode >> "$COMBINED_CA"
fi

if [ -s "$COMBINED_CA" ]; then
    $KUBECTL create configmap registry-ca-cm -n $NAMESPACE --from-file=ca.crt="$COMBINED_CA" --dry-run=client -o yaml | $KUBECTL apply -f -
    # Also create 'registry-ca' for legacy compatibility
    $KUBECTL create configmap registry-ca -n $NAMESPACE --from-file=ca.crt="$COMBINED_CA" --dry-run=client -o yaml | $KUBECTL apply -f -
else
    echo "WARNING: Could not find any CA to inject into $NAMESPACE."
fi
rm -f "$COMBINED_CA"
mark_step_done "registry-ca"

# if ! is_step_done "ollama"; then
# echo "--- 1.5. Deploying LLM: Ollama ---"
# bash "$REPO_DIR/infrastructure/ollama/ollama.sh"
# mark_step_done "ollama"
# fi

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
DB_POD=""
echo "Waiting for TimescaleDB primary pod..."
for _ in $(seq 1 60); do
  DB_POD=$($KUBECTL get pods -n "$DB_NAMESPACE" -l "cnpg.io/cluster=timescaledb,role=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$DB_POD" ]]; then
    break
  fi
  sleep 5
done

echo "-- got pod ${DB_POD:-<none>}"

if [ -n "$DB_POD" ]; then
  echo "Waiting for PostgreSQL readiness in pod $DB_POD..."
  READY=0
  for _ in $(seq 1 60); do
    if $KUBECTL exec -n "$DB_NAMESPACE" "$DB_POD" -- sh -lc 'pg_isready -U postgres -d postgres >/dev/null 2>&1' >/dev/null 2>&1; then
      READY=1
      break
    fi
    sleep 5
  done

  if [[ "$READY" -ne 1 ]]; then
    echo "ERROR: PostgreSQL in $DB_POD did not become ready in time."
    $KUBECTL -n "$DB_NAMESPACE" logs "$DB_POD" --tail=200 || true
    exit 1
  fi

  run_psql_with_retry() {
    local cmd="$1"
    local attempts=0
    until $KUBECTL exec -i -n "$DB_NAMESPACE" "$DB_POD" -- sh -lc "$cmd"; do
      attempts=$((attempts + 1))
      if [[ "$attempts" -ge 12 ]]; then
        return 1
      fi
      sleep 5
    done
  }

  echo "Ensuring role 'app' exists and has create on schema public"
  run_psql_with_retry "psql -U postgres -d postgres -tc \"SELECT 1 FROM pg_roles WHERE rolname='app'\" | grep -q 1 || psql -U postgres -d postgres -c \"CREATE ROLE app LOGIN PASSWORD 'app'\""
  run_psql_with_retry "psql -U postgres -d app -c \"GRANT CONNECT ON DATABASE app TO app; GRANT USAGE, CREATE ON SCHEMA public TO app;\""

  echo "Applying schema as role 'app' so objects are owned by app"
  if ! (echo "SET ROLE app;"; cat "$REPO_DIR/infrastructure/timescaledb/schema.sql") | \
    $KUBECTL exec -i -n "$DB_NAMESPACE" "$DB_POD" -- psql -U postgres -d app; then
    echo "ERROR: failed applying schema to TimescaleDB."
    exit 1
  fi
  mark_step_done "db-schema"
else
  echo "ERROR: Could not find TimescaleDB primary pod to apply schema."
  exit 1
fi
fi

echo "--- 3. Verifying Pulsar Prerequisite ---"
# Pulsar infrastructure is installed by setup-complete.sh (Step 1.5.8).
# setup-all.sh only deploys RAG services and assumes infrastructure is ready.
# Verify Pulsar is running before deploying services that depend on it.
PULSAR_NS="apache-pulsar"
PULSAR_READY=false
echo "Checking for running Pulsar broker pods in namespace $PULSAR_NS..."
BROKER_READY=$($KUBECTL get pods -n "$PULSAR_NS" -l "component=broker" -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$BROKER_READY" ]]; then
    echo "Pulsar brokers running: $BROKER_READY"
    PULSAR_READY=true
fi

if [[ "$PULSAR_READY" != "true" ]]; then
    echo ""
    echo "ERROR: Apache Pulsar is not running in namespace '$PULSAR_NS'."
    echo "Pulsar must be installed BEFORE deploying RAG services."
    echo ""
    echo "To install Pulsar, either:"
    echo "  1. Run the full setup:  ./setup-complete.sh"
    echo "  2. Install Pulsar only: bash rag-stack/infrastructure/pulsar/install.sh"
    echo ""
    echo "Current pods in $PULSAR_NS:"
    $KUBECTL get pods -n "$PULSAR_NS" 2>&1 || echo "  (namespace does not exist)"
    exit 1
fi

# Ensure tenants/namespaces are initialized (idempotent — safe to re-run)
# if ! is_step_done "pulsar-init"; then
# echo "--- 3.1 Initializing Pulsar Tenants and Namespaces ---"
# bash "$REPO_DIR/infrastructure/pulsar/init-rag-pulsar.sh"
# mark_step_done "pulsar-init"
# fi

if ! is_step_done "qdrant"; then
echo "--- 4. Deploying Vector Database: Qdrant ---"
$KUBECTL apply -f "$REPO_DIR/infrastructure/qdrant/qdrant-tls.yaml"
$KUBECTL apply -f "$REPO_DIR/infrastructure/qdrant/qdrant-config.yaml"
$KUBECTL apply -f "$REPO_DIR/infrastructure/qdrant/qdrant-pvc.yaml"
echo "Waiting for Qdrant certificate..."
$KUBECTL wait --for=condition=Ready certificate/qdrant-cert -n $NAMESPACE --timeout=60s
apply_manifest "$REPO_DIR/infrastructure/qdrant/qdrant-deploy.yaml"
$KUBECTL apply -f "$REPO_DIR/infrastructure/qdrant/qdrant-service.yaml"
mark_step_done "qdrant"
fi

  # APM ConfigMap for tests and services to export OTEL traces
  if ! is_step_done "apm-config"; then
  echo "--- 4.1 Creating/Updating APM ConfigMap for OTLP endpoint ---"
  APM_OTLP_ENDPOINT="${APM_OTLP_ENDPOINT:-http://otel-collector.monitoring.svc.cluster.local:4318}"
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

if ! is_step_done "timescaledb-secret"; then
echo "--- 5.5 Creating TimescaleDB connection secret (dynamic password) ---"
# Fetch the real 'app' user password from the CloudNativePG-managed secret
REAL_PW=$($KUBECTL get secret timescaledb-app -n timescaledb \
  -o jsonpath='{.data.password}' | base64 -d)
if [ -z "$REAL_PW" ]; then
  echo "ERROR: Could not fetch timescaledb-app password from timescaledb namespace."
  exit 1
fi
DB_URL="postgres://app:${REAL_PW}@timescaledb-rw.timescaledb.svc.cluster.local:5432/app?sslmode=require"
$KUBECTL create secret generic timescaledb-secret -n $NAMESPACE \
  --from-literal=url="${DB_URL}" \
  --dry-run=client -o yaml | $KUBECTL apply -f -
mark_step_done "timescaledb-secret"
fi

if ! is_step_done "llm-gateway"; then
echo "--- 6. Deploying LLM Gateway (Go) ---"
$KUBECTL apply -f "$REPO_DIR/services/llm-gateway/k8s/configmap.yaml"
apply_manifest "$REPO_DIR/services/llm-gateway/k8s/deployment.yaml"
mark_step_done "llm-gateway"
fi

if ! is_step_done "rag-worker"; then
echo "--- 7. Deploying RAG Worker (Go) ---"
apply_manifest "$REPO_DIR/services/rag-worker/k8s/deployment.yaml"
mark_step_done "rag-worker"
fi

if ! is_step_done "object-store-mgr"; then
echo "--- 8. Deploying Object Store Manager (Go) ---"
apply_manifest "$REPO_DIR/services/object-store-mgr/mgr-deployment.yaml"
$KUBECTL apply -f "$REPO_DIR/services/object-store-mgr/mgr-service.yaml"
mark_step_done "object-store-mgr"
fi

if ! is_step_done "memory-controller"; then
echo "--- 8.5 Deploying Memory Controller (Go) ---"
apply_manifest "$REPO_DIR/services/memory-controller/k8s/deployment.yaml"
mark_step_done "memory-controller"
fi

if ! is_step_done "rag-explorer"; then
echo "--- 8.6 Deploying RAG Explorer (Flutter Web) ---"
apply_manifest "$REPO_DIR/services/rag-explorer/k8s/deployment.yaml"
mark_step_done "rag-explorer"
fi

if ! is_step_done "rag-web-ui"; then
echo "--- 9. Deploying RAG Web UI (Go) ---"
apply_manifest "$REPO_DIR/services/rag-web-ui/ui-deployment.yaml"
mark_step_done "rag-web-ui"
fi

if ! is_step_done "db-adapter"; then
echo "--- 10. Deploying DB Adapter (Go) ---"
apply_manifest "$REPO_DIR/services/db-adapter/k8s/deployment.yaml"
$KUBECTL apply -f "$REPO_DIR/services/db-adapter/k8s/service.yaml"
mark_step_done "db-adapter"
fi

if ! is_step_done "rag-admin-api"; then
echo "--- 10.5 Deploying RAG Admin API (Go BFF) ---"
apply_manifest "$REPO_DIR/services/rag-admin-api/k8s/deployment.yaml"
mark_step_done "rag-admin-api"
fi

if ! is_step_done "qdrant-adapter"; then
echo "--- 11. Deploying Qdrant Adapter (Go) ---"
apply_manifest "$REPO_DIR/services/qdrant-adapter/k8s/deployment.yaml"
$KUBECTL apply -f "$REPO_DIR/services/qdrant-adapter/k8s/service.yaml"
mark_step_done "qdrant-adapter"
fi

if ! is_step_done "rag-ingestion-service"; then
echo "--- 11.5. Deploying RAG Ingestion Service (Python) ---"
apply_manifest "$REPO_DIR/services/rag-ingestion/k8s/deployment.yaml"
mark_step_done "rag-ingestion-service"
fi

if ! is_step_done "ingestion-job"; then
echo "--- 12. Preparing Ingestion Pipeline ---"
$KUBECTL apply -f "$REPO_DIR/ingestion/ingest-job-s3.yaml"
mark_step_done "ingestion-job"
fi

if ! is_step_done "k8s-resilience"; then
echo "--- 13. Applying Kubernetes Resilience Primitives ---"
RESILIENCE_DIR="$REPO_DIR/services/k8s-resilience"
echo "  Applying PodDisruptionBudgets..."
$KUBECTL apply -f "$RESILIENCE_DIR/pod-disruption-budgets.yaml"
echo "  Applying HorizontalPodAutoscalers..."
$KUBECTL apply -f "$RESILIENCE_DIR/horizontal-pod-autoscalers.yaml"
echo "  Applying NetworkPolicies..."
$KUBECTL apply -f "$RESILIENCE_DIR/network-policies.yaml"
mark_step_done "k8s-resilience"
fi

clear_journal

echo "--- All Components Deployed ---"
echo "Check status: $KUBECTL get pods -n $NAMESPACE"
