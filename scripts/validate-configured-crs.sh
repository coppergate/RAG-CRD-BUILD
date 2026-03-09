#!/usr/bin/env bash
set -Eeuo pipefail

KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-15}"

pass() { printf "[PASS] %s\n" "$1"; }
fail() { printf "[FAIL] %s\n" "$1"; }
info() { printf "[INFO] %s\n" "$1"; }

rc=0

check_cluster_access() {
  if "$KUBECTL" --request-timeout=10s get namespace default >/dev/null 2>&1; then
    pass "kubectl access OK"
  else
    fail "kubectl access failed (KUBECTL=$KUBECTL KUBECONFIG=$KUBECONFIG)"
    exit 2
  fi
}

check_crd() {
  local crd="$1"
  if "$KUBECTL" get crd "$crd" >/dev/null 2>&1; then
    pass "CRD exists: $crd"
  else
    fail "CRD missing: $crd"
    rc=1
  fi
}

check_phase() {
  local ns="$1"
  local gk="$2"
  local name="$3"
  local expected="$4"
  local label="$5"

  local phase=""
  if ! "$KUBECTL" -n "$ns" get "$gk" "$name" >/dev/null 2>&1; then
    fail "$label missing (${gk}/${name} in $ns)"
    rc=1
    return
  fi

  phase="$("$KUBECTL" -n "$ns" get "$gk" "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" == "$expected" ]]; then
    pass "$label phase=$phase"
  else
    fail "$label phase=${phase:-<empty>} expected=$expected"
    "$KUBECTL" -n "$ns" get "$gk" "$name" -o yaml | sed -n '1,220p' || true
    rc=1
  fi
}

check_condition_ready() {
  local ns="$1"
  local gk="$2"
  local name="$3"
  local label="$4"

  if ! "$KUBECTL" -n "$ns" get "$gk" "$name" >/dev/null 2>&1; then
    fail "$label missing (${gk}/${name} in $ns)"
    rc=1
    return
  fi

  local ready=""
  ready="$("$KUBECTL" -n "$ns" get "$gk" "$name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [[ "$ready" == "True" ]]; then
    pass "$label Ready=True"
    return
  fi

  # Fallback for controllers that expose phase but no Ready condition.
  local phase=""
  phase="$("$KUBECTL" -n "$ns" get "$gk" "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" == "Healthy" || "$phase" == "ready" || "$phase" == "Ready" ]]; then
    pass "$label phase=$phase"
  else
    fail "$label Ready condition/phase not healthy (Ready=${ready:-<empty>} phase=${phase:-<empty>})"
    "$KUBECTL" -n "$ns" get "$gk" "$name" -o yaml | sed -n '1,240p' || true
    rc=1
  fi
}

echo "===================================================="
echo "Validate Configured CRs"
echo "===================================================="
info "KUBECTL=$KUBECTL"
info "KUBECONFIG=$KUBECONFIG"
check_cluster_access

echo
echo "=== CRD checks ==="
check_crd "cephclusters.ceph.rook.io"
check_crd "cephblockpools.ceph.rook.io"
check_crd "cephfilesystems.ceph.rook.io"
check_crd "cephobjectstores.ceph.rook.io"
check_crd "objectbucketclaims.objectbucket.io"
check_crd "clusters.postgresql.cnpg.io"

echo
echo "=== Rook/Ceph CRs ==="
check_phase "rook-ceph" "cephcluster.ceph.rook.io" "rook-ceph" "Ready" "CephCluster/rook-ceph"
check_phase "rook-ceph" "cephblockpool.ceph.rook.io" "ceph-replica-pool" "Ready" "CephBlockPool/ceph-replica-pool"
check_phase "rook-ceph" "cephfilesystem.ceph.rook.io" "ceph-filesystem" "Ready" "CephFilesystem/ceph-filesystem"
check_phase "rook-ceph" "cephobjectstore.ceph.rook.io" "ceph-object-store" "Ready" "CephObjectStore/ceph-object-store"

echo
echo "=== ObjectBucketClaims ==="
check_phase "build-pipeline" "objectbucketclaim.objectbucket.io" "build-pipeline-bucket" "Bound" "OBC/build-pipeline-bucket"
check_phase "rag-system" "objectbucketclaim.objectbucket.io" "rag-codebase-bucket" "Bound" "OBC/rag-codebase-bucket"
check_phase "monitoring" "objectbucketclaim.objectbucket.io" "loki-s3-bucket" "Bound" "OBC/loki-s3-bucket"
check_phase "monitoring" "objectbucketclaim.objectbucket.io" "tempo-s3-bucket" "Bound" "OBC/tempo-s3-bucket"
check_phase "monitoring" "objectbucketclaim.objectbucket.io" "mimir-s3-bucket" "Bound" "OBC/mimir-s3-bucket"
check_phase "monitoring" "objectbucketclaim.objectbucket.io" "mimir-ruler-s3-bucket" "Bound" "OBC/mimir-ruler-s3-bucket"
check_phase "monitoring" "objectbucketclaim.objectbucket.io" "mimir-alertmanager-s3-bucket" "Bound" "OBC/mimir-alertmanager-s3-bucket"

echo
echo "=== CNPG/TimescaleDB CR ==="
check_condition_ready "timescaledb" "cluster.postgresql.cnpg.io" "timescaledb" "CNPG Cluster/timescaledb"

echo
echo "=== Summary ==="
if [[ "$rc" -eq 0 ]]; then
  pass "All configured CR checks passed"
else
  fail "One or more configured CR checks failed"
fi

exit "$rc"
