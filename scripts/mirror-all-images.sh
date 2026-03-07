#!/bin/bash
# mirror-all-images.sh
# Mirror required install/runtime images into local registry.
# Default mode is DRY RUN. Set APPLY=true to execute copies.

set -Eeuo pipefail

TARGET_REGISTRY="${TARGET_REGISTRY:-registry.hierocracy.home:5000}"
APPLY="${APPLY:-false}"
PARALLELISM="${PARALLELISM:-3}"
SKOPEO_TLS_VERIFY="${SKOPEO_TLS_VERIFY:-false}"

# Curated from install scripts/manifests used in complete-build.
# Keep this list explicit and pinned where possible.
IMAGES=(
  "apachepulsar/pulsar-all:3.0.7"
  "apachepulsar/pulsar-manager:v0.4.0"
  "streamnative/oxia:0.11.9"

  "amazon/aws-cli:latest"
  "busybox:latest"
  "busybox:1.36"
  "gcr.io/kaniko-project/executor:latest"
  "martizih/kaniko:latest"

  "otel/opentelemetry-collector-contrib:latest"
  "qdrant/qdrant:latest"
  "python:3.9-slim"
  "registry:2"
  "ollama/ollama:0.15.6"

  "docker.io/rook/ceph:v1.18.8"
  "quay.io/ceph/ceph:v19.2.3"
  "quay.io/ceph/ceph:v19"
  "quay.io/cephcsi/ceph-csi-operator:v0.4.1"
  "quay.io/cephcsi/cephcsi:v3.15.0"
  "quay.io/csiaddons/k8s-sidecar:v0.5.0"

  "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0"
  "registry.k8s.io/sig-storage/csi-provisioner:v5.2.0"
  "registry.k8s.io/sig-storage/csi-snapshotter:v6.3.0"
  "registry.k8s.io/sig-storage/csi-attacher:v4.8.0"
  "registry.k8s.io/sig-storage/csi-resizer:v1.13.0"

  "quay.io/prometheus-operator/prometheus-operator:v0.80.1"
)

log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || {
    echo "ERROR: required command missing: $c" >&2
    exit 1
  }
}

copy_one() {
  local src="$1"
  local dst="$TARGET_REGISTRY/$src"

  if [[ "$APPLY" != "true" ]]; then
    echo "skopeo copy --all --dest-tls-verify=$SKOPEO_TLS_VERIFY docker://$src docker://$dst"
    return 0
  fi

  log "Mirroring $src -> $dst"
  skopeo copy --all --dest-tls-verify="$SKOPEO_TLS_VERIFY" "docker://$src" "docker://$dst"
}

require_cmd skopeo

# De-duplicate while preserving order
uniq_images=()
declare -A seen
for img in "${IMAGES[@]}"; do
  if [[ -z "${seen[$img]:-}" ]]; then
    uniq_images+=("$img")
    seen[$img]=1
  fi
done

log "Target registry: $TARGET_REGISTRY"
log "Images to mirror: ${#uniq_images[@]}"
log "Mode: $([[ "$APPLY" == "true" ]] && echo APPLY || echo DRY-RUN)"

if [[ "$APPLY" != "true" ]]; then
  for img in "${uniq_images[@]}"; do
    copy_one "$img"
  done
  exit 0
fi

# Parallel execution (safe because each target ref is unique)
printf '%s\n' "${uniq_images[@]}" | xargs -n1 -P "$PARALLELISM" -I{} bash -c '
  set -Eeuo pipefail
  src="$1"
  dst="$2/$1"
  skopeo copy --all --dest-tls-verify="$3" "docker://$src" "docker://$dst"
' _ {} "$TARGET_REGISTRY" "$SKOPEO_TLS_VERIFY"

log "Mirror run complete."
