#!/bin/bash
# rag-stack/build.sh - Unified Build Entry Point (Cluster or Local)
# Supports hashing-based change detection, parallel builds, and multiple engines.
# Run on hierophant.

set -Eeuo pipefail

# --- Configuration & Defaults ---
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$REPO_DIR/.." && pwd)
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

# Options
MODE="${MODE:-cluster}" # cluster | local
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
FORCE_BUILD="${FORCE_BUILD:-false}"
SKIP_UNCHANGED="${SKIP_UNCHANGED:-true}"
PARALLELISM="${PARALLELISM:-4}"
WAIT_FOR_COMPLETION="${WAIT_FOR_COMPLETION:-false}"
JOURNAL_DIR="${JOURNAL_DIR:-$HOME/.complete-build/journal/build-hashing}"

mkdir -p "$JOURNAL_DIR"

SERVICES=("rag-worker" "rag-ingestion" "rag-web-ui" "llm-gateway" "db-adapter" "qdrant-adapter" "object-store-mgr" "rag-test-runner")

# --- Helpers ---
log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }

hash_context() {
    local svc="$1"
    local path=""
    if [[ "$svc" == "rag-test-runner" ]]; then
        path="$REPO_DIR/tests"
    else
        path="$REPO_DIR/services/$svc"
    fi
    # Hash service dir and common dir (excluding VCS/ignored)
    (cd "$REPO_DIR/services" && find common "$svc" -type f \( -name '.git' -prune -o -print \) 2>/dev/null | sort | xargs sha256sum | sha256sum | awk '{print $1}')
}

is_built() {
    local svc="$1"; local ver="$2"; local hash="$3"
    local journal_file="$JOURNAL_DIR/${svc}.${ver}.hash"
    [[ -f "$journal_file" ]] && [[ "$(cat "$journal_file")" == "$hash" ]]
}

mark_built() {
    local svc="$1"; local ver="$2"; local hash="$3"
    echo -n "$hash" > "$JOURNAL_DIR/${svc}.${ver}.hash"
}

# --- Build Logic ---
build_service() {
    local svc="$1"
    local current_hash=$(hash_context "$svc")
    
    if [[ "$FORCE_BUILD" != "true" && "$SKIP_UNCHANGED" == "true" ]]; then
        if is_built "$svc" "$VERSION" "$current_hash"; then
            log "SKIP: $svc unchanged (hash match) for version $VERSION"
            return 0
        fi
    fi

    log "BUILD: $svc version $VERSION (Mode: $MODE)"
    
    if [[ "$MODE" == "cluster" ]]; then
        # Cluster build via Orchestrator/Kaniko
        bash "$REPO_DIR/infrastructure/build-pipeline/trigger-build.sh" "$svc" "$VERSION"
    else
        # Local build via Podman
        local context_dir="$REPO_DIR/services"
        local dockerfile="$REPO_DIR/services/$svc/Dockerfile"
        if [[ "$svc" == "rag-test-runner" ]]; then
            context_dir="$REPO_DIR/tests"
            dockerfile="$REPO_DIR/tests/Dockerfile.test-runner"
        fi
        
        podman build --tls-verify=false \
            -t "$REGISTRY/$svc:$VERSION" -t "$REGISTRY/$svc:latest" \
            -f "$dockerfile" "$context_dir"
        
        podman push "$REGISTRY/$svc:$VERSION" --tls-verify=false
        podman push "$REGISTRY/$svc:latest" --tls-verify=false
    fi

    mark_built "$svc" "$VERSION" "$current_hash"
}

# --- Main Execution ---
main() {
    SELECTED_SERVICE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode) MODE="$2"; shift ;;
            --force) FORCE_BUILD="true" ;;
            --service) SELECTED_SERVICE="$2"; shift ;;
            --wait) WAIT_FOR_COMPLETION="true" ;;
            *) usage ;;
        esac
        shift
    done

    if [[ -n "$SELECTED_SERVICE" ]]; then
        build_service "$SELECTED_SERVICE"
    else
        # Parallel build for all services
        log "Starting parallel build of all services (Parallelism: $PARALLELISM)"
        
        # Export functions and variables for subshells
        export -f log hash_context is_built mark_built build_service
        export REPO_DIR BASE_DIR KUBECTL KUBECONFIG VERSION MODE REGISTRY FORCE_BUILD SKIP_UNCHANGED JOURNAL_DIR
        
        # Determine the absolute path to this script for robust sourcing if needed, 
        # though export -f should suffice for functions.
        local SCRIPT_PATH=$(realpath "${BASH_SOURCE[0]}")
        
        printf "%s\n" "${SERVICES[@]}" | xargs -P "$PARALLELISM" -I{} bash -c "source \"$SCRIPT_PATH\" && build_service {}"
    fi

    if [[ "$WAIT_FOR_COMPLETION" == "true" && "$MODE" == "cluster" ]]; then
        log "Waiting for cluster builds to complete..."
        # Reuse wait logic from verify-registry-tags or similar
        # Simple check: Wait for all jobs in build-pipeline to finish
        $KUBECTL wait --for=condition=complete job -n build-pipeline --all --timeout=600s || true
    fi

    log "Build process finished."
}

usage() {
    echo "Usage: $0 [--mode cluster|local] [--force] [--service name] [--wait]"
    exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
