#!/bin/bash
# ==============================================================================
# render-manifests.sh — reconcile static manifests to config/network.env
#
# Static YAML/JSON manifests are applied verbatim (`kubectl apply -f`, helm
# `--values`), so they cannot read env vars at rest. This script performs an
# IDEMPOTENT in-place substitution of the two network-coupled values that
# appear inside them:
#
#   1. The registry prefix  <host>:5000/<repo>  ->  ${REGISTRY_PREFIX}/<repo>
#   2. The in-cluster registry LoadBalancer IP  ->  ${REGISTRY_LB_IP}
#
# The registry-prefix rule matches any "<host>:5000/" token (trailing slash =
# image reference only, never an endpoint URL), so re-running is a no-op once
# rendered. Safe to run repeatedly; wired into full-install.sh and
# setup-01-basic.sh before the first manifest is applied.
#
# NOTE: talos-registry-patch.json and registries-clean.json are NOT handled
# here — they carry structural registry config (mirror keys, endpoints, embedded
# CA) and are maintained by hand to stay consistent with network.env.
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=../config/network.env
source "$BASE_DIR/config/network.env"

# Manifests carrying the registry prefix and/or the in-cluster registry LB IP.
MANIFESTS=(
  infrastructure/rook-ceph/values.yaml
  infrastructure/rook-ceph/install-values.yaml
  infrastructure/rook-ceph/cluster.yaml
  infrastructure/rook-ceph/operator.yaml
  infrastructure/rook-ceph/toolbox.yaml
  infrastructure/rook-ceph/csi-operator.yaml
  infrastructure/rook-ceph/wipe-disks.yaml
  infrastructure/rook-ceph/wipe-disks-no-gpu.yaml
  infrastructure/registry/registry.yaml
  infrastructure/metrics-server/metrics-server.yaml
  infrastructure/prometheus/prometheus-operator.yaml
  infrastructure/kubernetes-setup/check-lsmod-job.yaml
)

render_one() {
  local rel="$1" f="$BASE_DIR/$1"
  [[ -f "$f" ]] || { echo "  skip (missing): $rel"; return 0; }
  # 1. Registry prefix on image references: any "<host>:5000/" -> REGISTRY_PREFIX/
  sed -i -E "s#[A-Za-z0-9._-]+:${REGISTRY_PORT}/#${REGISTRY_PREFIX}/#g" "$f"
  # 2. In-cluster registry LoadBalancer IP
  sed -i "s#${REGISTRY_LB_IP_LEGACY}#${REGISTRY_LB_IP}#g" "$f"
  echo "  rendered: $rel"
}

echo "Reconciling manifests to config/network.env"
echo "  REGISTRY_PREFIX=${REGISTRY_PREFIX}"
echo "  REGISTRY_LB_IP=${REGISTRY_LB_IP} (was ${REGISTRY_LB_IP_LEGACY})"
for m in "${MANIFESTS[@]}"; do render_one "$m"; done
echo "Done."
