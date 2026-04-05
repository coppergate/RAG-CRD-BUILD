#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"

# Source of truth for versioning
if [[ -z "${VERSION:-}" ]]; then
    if [[ -f "$BASE_DIR/CURRENT_VERSION" ]]; then
        VERSION=$(cat "$BASE_DIR/CURRENT_VERSION" | tr -d '[:space:]')
    else
        VERSION="2.4.9"
    fi
fi
export VERSION

SHOW_INVENTORY="${SHOW_INVENTORY:-true}"

pass() { printf "[PASS] %s\n" "$1"; }
fail() { printf "[FAIL] %s\n" "$1"; }
info() { printf "[INFO] %s\n" "$1"; }

rc=0

section() {
  echo
  echo "===================================================="
  echo "$1"
  echo "===================================================="
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || {
    fail "required command missing: $c"
    exit 2
  }
}

check_manifest_exists() {
  local file="$1"
  local label="$2"
  if "$KUBECTL" get -f "$file" >/dev/null 2>&1; then
    pass "$label present ($file)"
  else
    fail "$label missing/invalid ($file)"
    "$KUBECTL" get -f "$file" || true
    rc=1
  fi
}

check_manifest_exists_templated() {
  local file="$1"
  local label="$2"
  if sed "s#__VERSION__#${VERSION}#g" "$file" | "$KUBECTL" get -f - >/dev/null 2>&1; then
    pass "$label present ($file, VERSION=$VERSION)"
  else
    fail "$label missing/invalid ($file, VERSION=$VERSION)"
    sed "s#__VERSION__#${VERSION}#g" "$file" | "$KUBECTL" get -f - || true
    rc=1
  fi
}

check_helm_release() {
  local ns="$1"
  local release="$2"
  if helm -n "$ns" status "$release" >/dev/null 2>&1; then
    pass "helm release $release in namespace $ns"
  else
    fail "helm release missing: $release in namespace $ns"
    rc=1
  fi
}

check_resource() {
  local ns="$1"
  local kind="$2"
  local name="$3"
  local label="$4"
  if "$KUBECTL" -n "$ns" get "$kind" "$name" >/dev/null 2>&1; then
    pass "$label present ($kind/$name in $ns)"
  else
    fail "$label missing ($kind/$name in $ns)"
    rc=1
  fi
}

check_headlamp_required() {
  local ns="headlamp"
  local helm_ok=0
  local deploy_ok=0

  if helm -n "$ns" status headlamp >/dev/null 2>&1; then
    helm_ok=1
  fi
  if "$KUBECTL" -n "$ns" get deployment headlamp >/dev/null 2>&1; then
    deploy_ok=1
  fi

  if [[ "$helm_ok" -eq 1 || "$deploy_ok" -eq 1 ]]; then
    pass "headlamp application deployed (helm release and/or deployment exists)"
  else
    fail "headlamp application missing (no helm release and no deployment/headlamp)"
    rc=1
  fi

  check_resource "$ns" "service" "headlamp-lb" "headlamp load balancer service"
  check_resource "$ns" "serviceaccount" "headlamp-admin" "headlamp admin serviceaccount"
  check_resource "$ns" "secret" "headlamp-admin-token" "headlamp admin token secret"
}

check_namespace() {
  local ns="$1"
  if "$KUBECTL" get namespace "$ns" >/dev/null 2>&1; then
    pass "namespace exists: $ns"
  else
    fail "namespace missing: $ns"
    rc=1
  fi
}

dump_namespace_inventory() {
  local ns="$1"
  echo
  echo "--- Namespace Inventory: $ns ---"
  "$KUBECTL" get all -n "$ns" || true
  "$KUBECTL" get pvc -n "$ns" 2>/dev/null || true
  "$KUBECTL" get cm -n "$ns" 2>/dev/null || true
  "$KUBECTL" get secret -n "$ns" 2>/dev/null || true
  "$KUBECTL" get ingress -n "$ns" 2>/dev/null || true
  "$KUBECTL" get obc -n "$ns" 2>/dev/null || true
  "$KUBECTL" get cephcluster,cephblockpool,cephfilesystem,cephobjectstore -n "$ns" 2>/dev/null || true
  "$KUBECTL" get cluster.postgresql.cnpg.io -n "$ns" 2>/dev/null || true
}

require_cmd "$KUBECTL"
require_cmd helm

section "Cluster Access"
if "$KUBECTL" --request-timeout=10s get namespace default >/dev/null 2>&1; then
  pass "kubectl access OK"
else
  fail "kubectl access failed (KUBECTL=$KUBECTL KUBECONFIG=$KUBECONFIG)"
  exit 2
fi

section "Namespace Checks"
for ns in \
  rook-ceph monitoring container-registry apache-pulsar build-pipeline \
  rag-system llms-ollama timescaledb gpu-operator headlamp purelb cert-manager
do
  check_namespace "$ns"
done

section "Manifest Resource Presence Checks"
# Core infra
check_manifest_exists "$BASE_DIR/infrastructure/registry/registry.yaml" "container registry resources"
check_manifest_exists "$BASE_DIR/infrastructure/rook-ceph/cluster.yaml" "rook ceph cluster CR"
check_manifest_exists "$BASE_DIR/infrastructure/rook-ceph/filesystem.yaml" "rook ceph filesystem CR"
check_manifest_exists "$BASE_DIR/infrastructure/rook-ceph/object.yaml" "rook ceph object-store CR"
check_manifest_exists "$BASE_DIR/infrastructure/rook-ceph/pool.yaml" "rook ceph blockpool CR"
check_manifest_exists "$BASE_DIR/infrastructure/rook-ceph/storageclass.yaml" "rook ceph storage classes"

# APM + OBC
check_manifest_exists "$BASE_DIR/infrastructure/APM/common/s3-storage.yaml" "APM OBC resources"
check_manifest_exists "$BASE_DIR/infrastructure/APM/otel-collector/otel-collector.yaml" "otel collector resources"
check_manifest_exists "$BASE_DIR/infrastructure/APM/grafana/operator-manifests.yaml" "grafana operator manifests"

# TimescaleDB/CNPG
check_manifest_exists "$BASE_DIR/rag-stack/infrastructure/timescaledb/cnpg-1.25.0.yaml" "cnpg operator resources"
check_manifest_exists "$BASE_DIR/rag-stack/infrastructure/timescaledb/cluster.yaml" "timescaledb cluster CR"
check_manifest_exists "$BASE_DIR/rag-stack/infrastructure/timescaledb/timescaledb-lb-service.yaml" "timescaledb lb service"

# RAG infra/resources
check_manifest_exists "$BASE_DIR/rag-stack/infrastructure/obc.yaml" "rag codebase OBC"
check_manifest_exists "$BASE_DIR/rag-stack/infrastructure/qdrant/qdrant-pvc.yaml" "qdrant pvc"
check_manifest_exists "$BASE_DIR/rag-stack/infrastructure/qdrant/qdrant-deploy.yaml" "qdrant deployment"
check_manifest_exists "$BASE_DIR/rag-stack/infrastructure/qdrant/qdrant-service.yaml" "qdrant service"
check_manifest_exists "$BASE_DIR/rag-stack/ingestion/ingest-job-s3.yaml" "rag ingestion job/configmap"

# Build pipeline infra
check_manifest_exists "$BASE_DIR/rag-stack/infrastructure/build-pipeline/s3-build-storage.yaml" "build-pipeline OBC"
check_manifest_exists "$BASE_DIR/rag-stack/infrastructure/build-pipeline/orchestrator-deployment.yaml" "build-orchestrator deployment"

# Service manifests (__VERSION__ templates)
check_manifest_exists_templated "$BASE_DIR/rag-stack/services/llm-gateway/k8s/deployment.yaml" "llm-gateway deployment"
check_manifest_exists_templated "$BASE_DIR/rag-stack/services/rag-worker/k8s/deployment.yaml" "rag-worker deployment"
check_manifest_exists_templated "$BASE_DIR/rag-stack/services/rag-web-ui/ui-deployment.yaml" "rag-web-ui deployment"
check_manifest_exists_templated "$BASE_DIR/rag-stack/services/db-adapter/k8s/deployment.yaml" "db-adapter deployment"
check_manifest_exists_templated "$BASE_DIR/rag-stack/services/qdrant-adapter/k8s/deployment.yaml" "qdrant-adapter deployment"
check_manifest_exists_templated "$BASE_DIR/rag-stack/services/rag-ingestion/k8s/deployment.yaml" "rag-ingestion deployment/service"
check_manifest_exists_templated "$BASE_DIR/rag-stack/services/object-store-mgr/mgr-job.yaml" "object-store-mgr job"

section "Helm Release Checks"
check_helm_release "default" "k8tz"
check_helm_release "purelb" "purelb"
check_helm_release "kube-system" "kube-state-metrics"
check_helm_release "monitoring" "loki"
check_helm_release "monitoring" "tempo"
check_helm_release "monitoring" "mimir"
check_helm_release "monitoring" "grafana-operator"
check_helm_release "monitoring" "alloy"
check_helm_release "gpu-operator" "gpu-operator"
check_helm_release "llms-ollama" "ollama-llama3"
check_helm_release "llms-ollama" "ollama-granite31-8b"

section "Required Headlamp Checks"
check_headlamp_required

section "Custom Resource Health Checks"
if "$BASE_DIR/scripts/validate-configured-crs.sh"; then
  pass "configured CR health checks passed"
else
  fail "configured CR health checks reported failures"
  rc=1
fi

if [[ "$SHOW_INVENTORY" == "true" ]]; then
  section "Full Namespace Inventory"
  for ns in \
    rook-ceph monitoring container-registry apache-pulsar build-pipeline \
    rag-system llms-ollama timescaledb gpu-operator headlamp purelb cert-manager
  do
    dump_namespace_inventory "$ns"
  done
fi

section "Summary"
if [[ "$rc" -eq 0 ]]; then
  pass "All configured entities validated"
else
  fail "One or more entity checks failed"
fi

exit "$rc"
