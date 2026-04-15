#!/bin/bash
# rag-stack/build.sh - Unified Build Entry Point (Cluster or Local)
# Supports per-service versioning, change detection, and parallel builds.
# To be executed on host: hierophant

set -Eeuo pipefail

# --- Configuration & Defaults ---
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$REPO_DIR/.." && pwd)
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"

LOCKFILE="/tmp/rag-stack-build-${USER:-shared}.lock"

VERSION_FILE="$BASE_DIR/CURRENT_VERSION"
MODE="${MODE:-cluster}" # cluster | local
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
# If VERSION is provided on command line, it overrides the version for ALL services (or selected service) and forces a rebuild.
OVERRIDE_VERSION="${VERSION:-}"
FORCE_BUILD="${FORCE_BUILD:-false}"
SKIP_UNCHANGED="${SKIP_UNCHANGED:-true}"
PARALLELISM="${PARALLELISM:-4}"
WAIT_FOR_COMPLETION="${WAIT_FOR_COMPLETION:-false}"
JOURNAL_DIR="${JOURNAL_DIR:-$HOME/.complete-build/journal/build-hashing}"

mkdir -p "$JOURNAL_DIR"

acquire_lock() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log "ERROR: Another build process (PID $pid) is already running."
            exit 1
        fi
    fi
    echo $$ > "$LOCKFILE" || { log "ERROR: Failed to write to lockfile $LOCKFILE"; exit 1; }
}

release_lock() {
    rm -f "$LOCKFILE"
}
trap release_lock EXIT

SERVICES=(
    "rag-worker" 
    "rag-ingestion" 
    "rag-web-ui" 
    "llm-gateway" 
    "db-adapter" 
    "qdrant-adapter" 
    "object-store-mgr" 
    "rag-test-runner"
    "rag-admin-api"
    "memory-controller"
    "build-orchestrator"
    "prompt-aggregator"
)

log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }

# --- Versioning Helpers ---
get_svc_version() {
    local svc="$1"
    jq -r ".\"$svc\".version // \"1.0.0\"" "$VERSION_FILE"
}

get_svc_last_build() {
    local svc="$1"
    jq -r ".\"$svc\".last_build // empty" "$VERSION_FILE"
}

update_svc_info() {
    local svc="$1"; local ver="$2"; local build_time="$3"
    local tmp=$(mktemp)
    local lockfile="/tmp/rag-stack-version-${USER:-shared}.lock"
    
    (
        flock -x 200
        if [[ ! -f "$VERSION_FILE" ]]; then echo "{}" > "$VERSION_FILE"; fi
        jq ".\"$svc\".version = \"$ver\" | .\"$svc\".last_build = $build_time" "$VERSION_FILE" > "$tmp" && cat "$tmp" > "$VERSION_FILE"
    ) 200>"$lockfile" || { log "ERROR: Failed to acquire lock on $lockfile"; rm -f "$tmp"; exit 1; }
    rm -f "$tmp"
}

cleanup_old_jobs() {
    if [[ "$MODE" == "cluster" ]]; then
        log "Cleaning up old completed/failed build jobs..."
        "$KUBECTL" get jobs -n build-pipeline -o json | \
            jq -r '.items[] | select(.status.succeeded > 0 or .status.failed > 0) | .metadata.name' | \
            xargs -r "$KUBECTL" delete job -n build-pipeline
    fi
}

increment_version() {
    local version=$1
    # Check if version has at least two dots
    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local build="${BASH_REMATCH[3]}"
        build=$((build + 1))
        echo "$major.$minor.$build"
    else
        # Fallback for non-semver
        echo "$version.1"
    fi
}

# --- Build Logic ---
image_exists() {
    local svc="$1"; local ver="$2"
    if [[ "$FORCE_BUILD" == "true" ]]; then return 1; fi
    if command -v skopeo >/dev/null 2>&1; then
        if skopeo inspect "docker://$REGISTRY/$svc:$ver" --tls-verify=false >/dev/null 2>&1; then 
            return 0 
        fi
    fi
    return 1
}

hash_context() {
    local svc="$1"
    local context_path="$REPO_DIR/services/$svc"
    [[ "$svc" == "rag-test-runner" ]] && context_path="$REPO_DIR/tests"
    # Hash service dir and common dir (excluding VCS/ignored)
    (cd "$REPO_DIR/services" && find common "$svc" -type f \( -name '.git' -prune -o -print \) 2>/dev/null | sort | xargs sha256sum | sha256sum | awk '{print $1}')
}

is_unchanged() {
    local svc="$1"; local hash="$2"
    local journal_file="$JOURNAL_DIR/${svc}.last_hash"
    [[ -f "$journal_file" ]] && [[ "$(cat "$journal_file")" == "$hash" ]]
}

mark_unchanged() {
    local svc="$1"; local hash="$2"
    echo -n "$hash" > "$JOURNAL_DIR/${svc}.last_hash"
}

deploy_update() {
    local svc="$1"; local ver="$2"
    log "DEPLOY UPDATE: $svc -> $ver"
    local manifest=""
    case "$svc" in
        "rag-web-ui") manifest="$REPO_DIR/services/rag-web-ui/ui-deployment.yaml" ;;
        "object-store-mgr") manifest="$REPO_DIR/services/object-store-mgr/mgr-deployment.yaml" ;;
        "build-orchestrator") manifest="$REPO_DIR/infrastructure/build-pipeline/orchestrator-deployment.yaml" ;;
        "rag-test-runner") manifest="" ;; # No deployment for test-runner
        *) manifest="$REPO_DIR/services/$svc/k8s/deployment.yaml" ;;
    esac

    if [[ -n "$manifest" && -f "$manifest" ]]; then
        # Replace __VERSION__ and apply
        sed -e "s#__VERSION__#${ver}#g" -e "s#registry.hierocracy.home:5000#${REGISTRY}#g" "$manifest" | "$KUBECTL" apply -f -
    elif [[ -n "$manifest" ]]; then
        log "WARN: Manifest not found for $svc at $manifest"
    fi
}

build_service() {
    local svc="$1"
    local ver=$(get_svc_version "$svc")
    local last_build=$(get_svc_last_build "$svc")
    local current_hash=$(hash_context "$svc")
    
    local needs_build=false
    
    # 1. Version override or Force Build
    if [[ -n "$OVERRIDE_VERSION" ]]; then
        ver="$OVERRIDE_VERSION"
        needs_build=true
    elif [[ "$FORCE_BUILD" == "true" ]]; then
        needs_build=true
    # 2. Change detection
    elif ! is_unchanged "$svc" "$current_hash"; then
        log "CHANGE DETECTED: $svc (hashing context updated)"
        ver=$(increment_version "$ver")
        # Mark as needing build by setting last_build=null
        update_svc_info "$svc" "$ver" "null"
        mark_unchanged "$svc" "$current_hash"
        needs_build=true
    # 3. Previous build failed or not completed
    elif [[ "$last_build" == "null" || -z "$last_build" || "$last_build" == *"(triggered)"* ]]; then
        # Check if a build job is already running to avoid redundant triggers
        local ver_safe="${ver//./-}"
        if [[ "$MODE" == "cluster" ]]; then
            # Look for ANY job (running, completed, or failed) to avoid duplicates if it's still present in the system
            # We specifically avoid re-triggering if a job exists and it's not successful.
            if "$KUBECTL" get job -n build-pipeline -l "app=kaniko-build,service=$svc,version=$ver_safe" 2>/dev/null | grep -E '0/1|1/1' >/dev/null 2>&1; then
                log "STILL BUILDING: $svc version $ver (job exists in cluster)"
                needs_build=false
            else
                log "RESUMING: $svc (last build was not recorded as successful and no active job found)"
                needs_build=true
            fi
        else
            log "RESUMING: $svc (last build was not recorded as successful)"
            needs_build=true
        fi
    fi

    if [[ "$needs_build" == "true" ]]; then
        # 4. Registry check (only skip if image is already there and we are not forcing)
        if [[ "$FORCE_BUILD" != "true" ]] && image_exists "$svc" "$ver"; then
            log "SKIP: $svc:$ver already exists in registry"
            update_svc_info "$svc" "$ver" "\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\""
            deploy_update "$svc" "$ver"
            return 0
        fi

        log "BUILD: $svc version $ver (Mode: $MODE)"
        if [[ "$MODE" == "cluster" ]]; then
            bash "$REPO_DIR/infrastructure/build-pipeline/trigger-build.sh" "$svc" "$ver"
        else
            # Local build logic
            local context_dir="$REPO_DIR/services"
            local dockerfile="$REPO_DIR/services/$svc/Dockerfile"
            if [[ "$svc" == "rag-test-runner" ]]; then
                context_dir="$REPO_DIR/tests"
                dockerfile="$REPO_DIR/tests/Dockerfile.test-runner"
            fi
            podman build --tls-verify=false \
                -t "$REGISTRY/$svc:$ver" -t "$REGISTRY/$svc:latest" \
                -f "$dockerfile" "$context_dir"
            podman push "$REGISTRY/$svc:$ver" --tls-verify=false
            podman push "$REGISTRY/$svc:latest" --tls-verify=false
        fi
        
        # In cluster mode, we can't be 100% sure it built successfully here yet unless we wait,
        # but the user said "when new versions are built update any deploy manifests".
        # If we wait, we can set the timestamp. If we don't, we might set it too early.
        # However, for now, we'll follow the flow.
        
        if [[ "$MODE" == "local" ]]; then
            update_svc_info "$svc" "$ver" "\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\""
            deploy_update "$svc" "$ver"
        else
             # In cluster mode, we might want to defer the update if WAIT_FOR_COMPLETION is false.
             # But the user wants it built then updated.
             # We'll update manifest now and let k8s retry pulling until image is ready.
             deploy_update "$svc" "$ver"
             # We'll set the timestamp if we are in non-waiting mode, 
             # or handle it in the main wait loop.
             if [[ "$WAIT_FOR_COMPLETION" != "true" ]]; then
                 update_svc_info "$svc" "$ver" "\"$(date -u +'%Y-%m-%dT%H:%M:%SZ') (triggered)\""
             fi
        fi
    else
        log "SKIP: $svc unchanged and already built"
    fi
}

# --- Main Execution ---
main() {
    SELECTED_SERVICE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode) MODE="$2"; shift ;;
            --force) FORCE_BUILD="true" ;;
            --version) OVERRIDE_VERSION="$2"; shift; FORCE_BUILD="true" ;;
            --service) SELECTED_SERVICE="$2"; shift ;;
            --wait) WAIT_FOR_COMPLETION="true" ;;
            *) usage ;;
        esac
        shift
    done

    cleanup_old_jobs
    acquire_lock

    if [[ -n "$SELECTED_SERVICE" ]]; then
        build_service "$SELECTED_SERVICE"
    else
        log "Starting parallel build of all services (Parallelism: $PARALLELISM)"
        
        # Export functions and variables for subshells
        # NOTE: update_svc_info and mark_unchanged modify files, so we should be careful in parallel.
        # Actually, if we do the versioning/hash check sequentially first, then parallelize the builds, it's safer.
        
        log "Pre-build check and versioning..."
        SERVICES_TO_BUILD=()
        for svc in "${SERVICES[@]}"; do
             # Check if we need build (we reuse the logic but don't trigger yet)
             local ver=$(get_svc_version "$svc")
             local last_build=$(get_svc_last_build "$svc")
             local current_hash=$(hash_context "$svc")
             local needs_build=false
             
             if [[ -n "$OVERRIDE_VERSION" ]] || [[ "$FORCE_BUILD" == "true" ]]; then
                 needs_build=true
             elif ! is_unchanged "$svc" "$current_hash"; then
                 needs_build=true
             elif [[ "$last_build" == "null" || -z "$last_build" ]]; then
                 needs_build=true
             fi

             if [[ "$needs_build" == "true" ]]; then
                 # Check registry before confirming build
                 local target_ver="$ver"
                 [[ -n "$OVERRIDE_VERSION" ]] && target_ver="$OVERRIDE_VERSION"
                 if ! is_unchanged "$svc" "$current_hash" && [[ -z "$OVERRIDE_VERSION" ]]; then
                     target_ver=$(increment_version "$ver")
                 fi

                 if [[ "$FORCE_BUILD" != "true" ]] && image_exists "$svc" "$target_ver"; then
                     # Service already exists in registry, skip build but update version/deploy
                     build_service "$svc"
                 else
                     SERVICES_TO_BUILD+=("$svc")
                 fi
             fi
        done

        if [[ ${#SERVICES_TO_BUILD[@]} -gt 0 && "$MODE" == "cluster" ]]; then
            log "Preparing shared source context for ${#SERVICES_TO_BUILD[@]} services..."
            # Capture both stdout (URLs) and stderr (logging)
            local UPLOAD_OUT=$(bash "$REPO_DIR/infrastructure/build-pipeline/trigger-build.sh" --upload-only 2>&1)
            export SOURCE_URL=$(echo "$UPLOAD_OUT" | grep "SOURCE_URL=" | cut -d= -f2-)
            export SOURCE_TARBALL=$(echo "$UPLOAD_OUT" | grep "SOURCE_TARBALL=" | cut -d= -f2-)
            log "Shared Context: $SOURCE_TARBALL"
        fi

        log "Building services: ${SERVICES_TO_BUILD[*]:-none}"
        for svc in "${SERVICES_TO_BUILD[@]}"; do
             build_service "$svc" &
             # Manage parallelism (simple implementation)
             while [[ $(jobs -r | wc -l) -ge $PARALLELISM ]]; do sleep 1; done
        done
        wait
    fi

    if [[ "$WAIT_FOR_COMPLETION" == "true" && "$MODE" == "cluster" ]]; then
        log "Waiting for cluster builds to complete..."
        # Wait for all jobs with the app=kaniko-build label
        "$KUBECTL" wait --for=condition=complete job -n build-pipeline -l app=kaniko-build --timeout=900s || true
        # After wait, we update timestamps for all services that were built
        for svc in "${SERVICES[@]}"; do
             local ver=$(get_svc_version "$svc")
             local last=$(get_svc_last_build "$svc")
             if [[ "$last" == "null" || "$last" == *"(triggered)"* ]]; then
                  update_svc_info "$svc" "$ver" "\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\""
             fi
        done
    fi

    log "Build process finished."
}

usage() {
    echo "Usage: $0 [--mode cluster|local] [--force] [--version ver] [--service name] [--wait]"
    exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi