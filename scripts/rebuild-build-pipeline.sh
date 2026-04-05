#!/bin/bash
# rebuild-build-pipeline.sh
# Full teardown and rebuild for build-pipeline infra and Kaniko-built service images.
# Intended to run on hierophant.

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"
NS="${NS:-build-pipeline}"

# Source of truth for versioning
if [[ -z "${VERSION:-}" ]]; then
    if [[ -f "$BASE_DIR/CURRENT_VERSION" ]]; then
        VERSION=$(cat "$BASE_DIR/CURRENT_VERSION" | tr -d '[:space:]')
    else
        VERSION="2.4.9"
    fi
fi
export VERSION

WAIT_ALL="${WAIT_ALL:-true}"
CLEAR_PULSAR_BACKLOG="${CLEAR_PULSAR_BACKLOG:-true}"
ORCHESTRATOR_TAG="${ORCHESTRATOR_TAG:-latest}"

log() {
  printf "[%s] %s\n" "$(date +'%F %T')" "$*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "required command missing: $c"
}

main() {
  require_cmd "$KUBECTL"

  log "Base dir: $BASE_DIR"
  log "Namespace: $NS"
  log "Version: $VERSION"
  log "Orchestrator tag: $ORCHESTRATOR_TAG"
  log "KUBECTL: $KUBECTL"
  log "KUBECONFIG: $KUBECONFIG"

  log "Step 1/6: Deleting namespace $NS (if present)"
  "$KUBECTL" delete namespace "$NS" --ignore-not-found=true || true
  "$KUBECTL" wait --for=delete "namespace/$NS" --timeout=300s || true

  log "Step 2/6: Clearing local journals"
  rm -rf "$HOME/.complete-build/journal/"* || true

  if [[ "$CLEAR_PULSAR_BACKLOG" == "true" ]]; then
    log "Step 3/6: Clearing build-tasks backlog in Pulsar"
    if [[ -x "$BASE_DIR/rag-stack/infrastructure/build-pipeline/clear-build-task-backlog.sh" ]]; then
      "$BASE_DIR/rag-stack/infrastructure/build-pipeline/clear-build-task-backlog.sh" || true
    else
      log "Backlog clear script not found; skipping"
    fi
  else
    log "Step 3/6: Skipping Pulsar backlog clear (CLEAR_PULSAR_BACKLOG=false)"
  fi

  log "Step 4/6: Reinstalling build-pipeline infrastructure"
  FRESH_INSTALL=true ORCHESTRATOR_TAG="$ORCHESTRATOR_TAG" bash "$BASE_DIR/rag-stack/infrastructure/build-pipeline/install.sh"

  log "Step 5/6: Verifying orchestrator rollout"
  "$KUBECTL" -n "$NS" get deploy,pods -o wide || true
  "$KUBECTL" -n "$NS" rollout status deploy/build-orchestrator --timeout=300s

  if [[ "$WAIT_ALL" == "true" ]]; then
    log "Step 6/6: Building all services and waiting for registry artifacts"
    bash "$BASE_DIR/rag-stack/build.sh" --mode cluster --wait
  else
    log "Step 6/6: Triggering all services without wait"
    bash "$BASE_DIR/rag-stack/build.sh" --mode cluster
  fi

  log "Rebuild complete."
}

main "$@"
