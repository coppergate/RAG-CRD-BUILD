#!/bin/bash
# check-apm-obc-readiness.sh
# Diagnose why APM OBC buckets stay Pending

set -Eeuo pipefail

KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"
MON_NS="${MON_NS:-monitoring}"
ROOK_NS="${ROOK_NS:-rook-ceph}"
BUCKETS=(
  "loki-s3-bucket"
  "tempo-s3-bucket"
  "mimir-s3-bucket"
  "mimir-ruler-s3-bucket"
  "mimir-alertmanager-s3-bucket"
)

pass() { printf "[PASS] %s\n" "$1"; }
fail() { printf "[FAIL] %s\n" "$1"; }
info() { printf "[INFO] %s\n" "$1"; }

section() {
  echo
  echo "===================================================="
  echo "$1"
  echo "===================================================="
}

rc=0

section "Cluster Access"
if "$KUBECTL" --request-timeout=10s get namespace default >/dev/null 2>&1; then
  pass "kubectl can reach cluster"
else
  fail "kubectl cannot reach cluster (KUBECTL=$KUBECTL KUBECONFIG=$KUBECONFIG)"
  exit 2
fi

section "OBC CRD + StorageClass"
if "$KUBECTL" get crd objectbucketclaims.objectbucket.io >/dev/null 2>&1; then
  pass "ObjectBucketClaim CRD exists"
else
  fail "Missing CRD objectbucketclaims.objectbucket.io"
  rc=1
fi

if "$KUBECTL" get storageclass rook-ceph-bucket >/dev/null 2>&1; then
  pass "StorageClass rook-ceph-bucket exists"
  "$KUBECTL" get storageclass rook-ceph-bucket -o wide || true
else
  fail "Missing StorageClass rook-ceph-bucket"
  rc=1
fi

section "Rook Object Store"
if "$KUBECTL" get cephobjectstore.ceph.rook.io ceph-object-store -n "$ROOK_NS" >/dev/null 2>&1; then
  pass "CephObjectStore ceph-object-store exists"
  "$KUBECTL" get cephobjectstore.ceph.rook.io ceph-object-store -n "$ROOK_NS" -o wide || true
else
  fail "CephObjectStore ceph-object-store missing in namespace $ROOK_NS"
  rc=1
fi

if "$KUBECTL" get deploy -n "$ROOK_NS" | grep -q 'rook-ceph-rgw'; then
  pass "RGW deployment exists"
  "$KUBECTL" get deploy -n "$ROOK_NS" | grep 'rook-ceph-rgw' || true
else
  fail "No rook-ceph-rgw deployment found in $ROOK_NS"
  rc=1
fi

section "Monitoring OBC Status"
if "$KUBECTL" get obc -n "$MON_NS" >/dev/null 2>&1; then
  "$KUBECTL" get obc -n "$MON_NS" -o wide || true
else
  info "No OBC resources found in $MON_NS"
fi

for b in "${BUCKETS[@]}"; do
  echo
  echo "--- Bucket: $b ---"
  if "$KUBECTL" get obc "$b" -n "$MON_NS" >/dev/null 2>&1; then
    phase="$("$KUBECTL" get obc "$b" -n "$MON_NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    secret_ref="$("$KUBECTL" get obc "$b" -n "$MON_NS" -o jsonpath='{.spec.additionalConfig.bucketName}' 2>/dev/null || true)"
    echo "phase=${phase:-unknown}"
    [[ -n "$secret_ref" ]] && echo "bucketName=${secret_ref}"

    if "$KUBECTL" get secret "$b" -n "$MON_NS" >/dev/null 2>&1; then
      pass "Secret $b exists"
    else
      fail "Secret $b missing"
      rc=1
      "$KUBECTL" describe obc "$b" -n "$MON_NS" || true
    fi
  else
    fail "OBC $b missing in $MON_NS"
    rc=1
  fi
done

section "Recent Events"
"$KUBECTL" get events -n "$MON_NS" --sort-by=.lastTimestamp | tail -n 80 || true

section "Rook Pods Snapshot"
"$KUBECTL" get pods -n "$ROOK_NS" | grep -E 'rook-ceph-operator|rgw|bucket|provisioner' || true

section "Result"
if [[ "$rc" -eq 0 ]]; then
  pass "APM bucket prerequisites look healthy"
else
  fail "One or more prerequisites failed; see output above"
fi

exit "$rc"
