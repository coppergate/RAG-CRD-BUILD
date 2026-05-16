#!/usr/bin/env bash
# update-rag-system-images.sh - Update rag-system deployment images to a target version.
#
# Usage:
#   ./scripts/update-rag-system-images.sh [version]
#
# Defaults to 2.4.11 when no version is supplied.

set -Eeuo pipefail

KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"

NAMESPACE="${NAMESPACE:-rag-system}"
VERSION="${1:-${VERSION:-2.4.11}}"
REGISTRY="${REGISTRY:-registry.container-registry.svc.cluster.local:5000}"
ROLL_OUT="${ROLL_OUT:-true}"

declare -A DEPLOYMENT_NAMES=(
  [llm-gateway]="llm-gateway"
  [rag-ingestion]="rag-ingestion-service"
  [rag-worker]="rag-worker"
  [db-adapter]="db-adapter"
  [qdrant-adapter]="qdrant-adapter"
  [object-store-mgr]="object-store-mgr"
  [memory-controller]="memory-controller"
  [prompt-aggregator]="prompt-aggregator"
  [rag-admin-api]="rag-admin-api"
  [rag-explorer]="rag-explorer"
)

declare -A CONTAINER_NAMES=(
  [llm-gateway]="gateway"
  [rag-ingestion]="ingestor"
  [rag-worker]="worker"
  [db-adapter]="adapter"
  [qdrant-adapter]="qdrant-adapter"
  [object-store-mgr]="manager"
  [memory-controller]="controller"
  [prompt-aggregator]="aggregator"
  [rag-admin-api]="admin-api"
  [rag-explorer]="ui"
)

SERVICES=(
  llm-gateway
  rag-ingestion
  rag-worker
  db-adapter
  qdrant-adapter
  object-store-mgr
  memory-controller
  prompt-aggregator
  rag-admin-api
  rag-explorer
)

log() {
  printf "[%s] %s\n" "$(date +'%F %T')" "$*"
}

update_one() {
  local service="$1"
  local deployment="${DEPLOYMENT_NAMES[$service]}"
  local container="${CONTAINER_NAMES[$service]}"
  local image="${REGISTRY}/${service}:${VERSION}"

  if ! "$KUBECTL" get deployment "$deployment" -n "$NAMESPACE" >/dev/null 2>&1; then
    log "SKIP: deployment/$deployment not found in namespace $NAMESPACE"
    return 0
  fi

  log "Updating deployment/$deployment container/$container -> $image"
  "$KUBECTL" -n "$NAMESPACE" set image "deployment/$deployment" "${container}=${image}"

  if [[ "$ROLL_OUT" == "true" ]]; then
    log "Waiting for rollout of deployment/$deployment"
    "$KUBECTL" -n "$NAMESPACE" rollout status "deployment/$deployment" --timeout=300s
  fi
}

main() {
  if [[ ! -x "$KUBECTL" ]]; then
    echo "ERROR: kubectl not found or not executable at $KUBECTL" >&2
    exit 1
  fi

  log "Namespace: $NAMESPACE"
  log "Registry:  $REGISTRY"
  log "Version:   $VERSION"
  echo

  for service in "${SERVICES[@]}"; do
    update_one "$service"
  done

  echo
  log "RAG system image update complete."
}

main "$@"
