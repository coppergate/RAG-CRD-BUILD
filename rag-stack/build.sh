#!/bin/bash
# rag-stack/build.sh - Unified Build Entry Point (Cluster or Local)
# Supports per-service versioning, change detection, and parallel builds.
# To be executed on host: hierophant

set -Eeuo pipefail
set -m # Enable job control for reliable parallel build tracking

# --- Configuration & Defaults ---
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$REPO_DIR/.." && pwd)
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"

# Build settings
MODE="${MODE:-cluster}"
VERSION_FILE="${VERSION_FILE:-$BASE_DIR/CURRENT_VERSION}"
JOURNAL_DIR="${JOURNAL_DIR:-/tmp/.build_journal_junie}"
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
FORCE_BUILD="${FORCE_BUILD:-false}"
WAIT_FOR_COMPLETION="${WAIT_FOR_COMPLETION:-false}"
OVERRIDE_VERSION="${OVERRIDE_VERSION:-}"
PARALLELISM="${PARALLELISM:-4}"

# --- Locking Configuration ---
LOCK_FILE="/tmp/rag-stack-build.lock"
LOCK_LEDGER="/tmp/rag-stack-build-ledger.json"
LOCK_HEARTBEAT="/tmp/rag-stack-build-heartbeat"
mkdir -p "$JOURNAL_DIR"

acquire_lock() {
    local timeout_seconds=900 # 15 minutes
    local elapsed=0
    local wait_step=10
    
    # We use a non-inherited FD for the lock check
    log "Attempting to acquire build lock..."
    
    # We'll use a simpler loop that doesn't keep the FD open until we actually get the lock
    while true; do
        if exec 200>"$LOCK_FILE" && flock -x -n 200; then
             # Lock acquired!
             break
        fi
        
        if [[ $elapsed -ge $timeout_seconds ]]; then
            log "ERROR: Could not acquire build lock after ${timeout_seconds}s."
            if [[ -f "$LOCK_LEDGER" ]]; then
                log "Current lock owner details: $(cat "$LOCK_LEDGER")"
            fi
            exit 1
        fi
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log "Waiting for build lock... (elapsed: ${elapsed}s)"
            if [[ -f "$LOCK_LEDGER" ]]; then
                local owner_info=$(jq -r '.user + "@" + .host + " (PID " + (.pid|tostring) + ") started at " + .start' "$LOCK_LEDGER" 2>/dev/null || cat "$LOCK_LEDGER")
                log "Current Owner: $owner_info"
            fi
        fi
        
        sleep "$wait_step"
        elapsed=$((elapsed + wait_step))
    done
    
    # Write to ledger
    local start_time=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    echo "{\"pid\": $$, \"user\": \"$(id -un)\", \"host\": \"${HOSTNAME:-unknown}\", \"start\": \"$start_time\"}" > "$LOCK_LEDGER"
    
    # Start heartbeat in background (make sure it DOES NOT inherit FD 200)
    ( 
        while [[ -f "$LOCK_LEDGER" ]]; do 
            date -u +'%Y-%m-%dT%H:%M:%SZ' > "$LOCK_HEARTBEAT"
            sleep 15
        done 
    ) 200>&- &
    HB_PID=$!
    
    log "Build lock acquired (Start: $start_time)."
}

release_lock() {
    # Stop heartbeat
    if [[ -n "${HB_PID:-}" ]]; then
        kill "$HB_PID" 2>/dev/null || true
    fi
    
    # Clean up ledger
    rm -f "$LOCK_LEDGER" "$LOCK_HEARTBEAT"
    
    # Release flock (Closing FD 200)
    exec 200>&-
    log "Build lock released."
}
trap release_lock EXIT

SERVICES=(
    "rag-worker" 
    "rag-ingestion" 
    "llm-gateway" 
    "db-adapter" 
    "qdrant-adapter" 
    "object-store-mgr" 
    "rag-test-runner"
    "rag-admin-api"
    "memory-controller"
    "prompt-aggregator"
)

# Infrastructure services are only built if explicitly requested or if they have changed.
# They are excluded from the default "build all" to avoid unnecessary overhead.
INFRA_SERVICES=(
    "build-orchestrator"
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
    local lockfile="/tmp/rag-stack-version-shared.lock"
    
    # Ensure lock file is accessible to the group
    (umask 000; touch "$lockfile" 2>/dev/null || true)
    chmod 666 "$lockfile" 2>/dev/null || true

    exec 200>"$lockfile"
    if ! flock -x -w 10 200; then
        log "ERROR: Failed to acquire lock on $lockfile after 10s"
        rm -f "$tmp"
        exit 1
    fi

    if [[ ! -f "$VERSION_FILE" ]]; then echo "{}" > "$VERSION_FILE"; fi
    if jq ".\"$svc\".version = \"$ver\" | .\"$svc\".last_build = $build_time" "$VERSION_FILE" > "$tmp" 2>/dev/null; then
        cat "$tmp" > "$VERSION_FILE" || log "WARN: Failed to update $VERSION_FILE (Permissions?)"
    else
        log "WARN: Failed to generate updated version JSON"
    fi
    
    flock -u 200
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
    
    if [[ "$svc" == "build-orchestrator" ]]; then
        # Exclude RAG-specific contracts from orchestrator hash to prevent unnecessary rebuilds
        # when only application data contracts change.
        (cd "$REPO_DIR/services" && find common "$svc" -type f \( -name '.git' -prune -o -path 'common/contracts' -prune -o -print \) 2>/dev/null | sort | xargs sha256sum | sha256sum | awk '{print $1}')
    else
        # Hash service dir and common dir
        (cd "$REPO_DIR/services" && find common "$svc" -type f \( -name '.git' -prune -o -print \) 2>/dev/null | sort | xargs sha256sum | sha256sum | awk '{print $1}')
    fi
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
        "object-store-mgr") manifest="$REPO_DIR/services/object-store-mgr/mgr-deployment.yaml" ;;
        "build-orchestrator") manifest="$REPO_DIR/infrastructure/build-pipeline/orchestrator-deployment.yaml" ;;
        "rag-test-runner") manifest="" ;; # No deployment for test-runner
        *) manifest="$REPO_DIR/services/$svc/k8s/deployment.yaml" ;;
    esac

    if [[ -n "$manifest" && -f "$manifest" ]]; then
        # Replace __VERSION__ and apply
        # We handle both the external and internal registry names for substitution
        sed -e "s#__VERSION__#${ver}#g" \
            -e "s#registry.hierocracy.home:5000#${REGISTRY}#g" \
            -e "s#registry.container-registry.svc.cluster.local:5000#${REGISTRY}#g" \
            "$manifest" | "$KUBECTL" apply -f -
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
             # In cluster mode, we defer the update until the build is complete
             # to avoid ImagePullBackOff on pods.
             update_svc_info "$svc" "$ver" "\"$(date -u +'%Y-%m-%dT%H:%M:%SZ') (triggered)\""
        fi
    else
        log "SKIP: $svc unchanged and already built"
    fi
}

# --- Main Execution ---
main() {
    SELECTED_SERVICES=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode) MODE="$2"; shift ;;
            --force) FORCE_BUILD="true" ;;
            --version) OVERRIDE_VERSION="$2"; shift; FORCE_BUILD="true" ;;
            --service) SELECTED_SERVICES+=("$2"); shift ;;
            --wait) WAIT_FOR_COMPLETION="true" ;;
            *) usage ;;
        esac
        shift
    done

	acquire_lock
	cleanup_old_jobs

	if [[ ${#SELECTED_SERVICES[@]} -gt 0 ]]; then
		log "Building selected services: ${SELECTED_SERVICES[*]} (Parallelism: $PARALLELISM)"
		for svc in "${SELECTED_SERVICES[@]}"; do
			build_service "$svc" &
			while [[ $(jobs -r | wc -l) -ge $PARALLELISM ]]; do sleep 1; done
		done
		wait
	else
		log "Pre-build check and versioning..."
		SERVICES_TO_BUILD=()
		SERVICES_TO_DEPLOY=()
		ORCHESTRATOR_NEEDS_BUILD=false

		for svc in "${SERVICES[@]}"; do
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
				local target_ver="$ver"
				[[ -n "$OVERRIDE_VERSION" ]] && target_ver="$OVERRIDE_VERSION"
				if ! is_unchanged "$svc" "$current_hash" && [[ -z "$OVERRIDE_VERSION" ]]; then
					target_ver=$(increment_version "$ver")
				fi

				if [[ "$FORCE_BUILD" != "true" ]] && image_exists "$svc" "$target_ver"; then
					# Already built, but needs deployment update
					SERVICES_TO_DEPLOY+=("$svc")
				else
					if [[ "$svc" == "build-orchestrator" ]]; then
						ORCHESTRATOR_NEEDS_BUILD=true
					else
						SERVICES_TO_BUILD+=("$svc")
					fi
				fi
			fi
		done

		# 1. Sequential build-orchestrator (Critical)
		if [[ "$ORCHESTRATOR_NEEDS_BUILD" == "true" ]]; then
			log "CRITICAL: build-orchestrator needs update. Building it first to avoid conflicts."
			build_service "build-orchestrator"
			if [[ "$MODE" == "cluster" ]]; then
				local bver=$(get_svc_version "build-orchestrator")
				local bver_safe="${bver//./-}"
				log "Waiting for build-orchestrator Kaniko job..."
				"$KUBECTL" wait --for=condition=complete job -n build-pipeline -l "app=kaniko-build,service=build-orchestrator,version=$bver_safe" --timeout=600s || true
				
				# Verify success before deploying
				if "$KUBECTL" get job -n build-pipeline -l "app=kaniko-build,service=build-orchestrator,version=$bver_safe" -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null | grep 1 >/dev/null; then
					deploy_update "build-orchestrator" "$bver"
					update_svc_info "build-orchestrator" "$bver" "\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\""
				else
					log "ERROR: build-orchestrator build failed. Cannot update deployment."
				fi

				log "Waiting for build-orchestrator rollout..."
				"$KUBECTL" rollout status deployment/build-orchestrator -n build-pipeline --timeout=300s || true
				sleep 10 # Allow new orchestrator to stabilize
			fi
		fi

		# 2. Parallel Skip-and-Deploy (Fast)
		if [[ ${#SERVICES_TO_DEPLOY[@]} -gt 0 ]]; then
			log "Starting parallel deployment update for existing images: ${SERVICES_TO_DEPLOY[*]} (Parallelism: $PARALLELISM)"
			for svc in "${SERVICES_TO_DEPLOY[@]}"; do
				build_service "$svc" 200>&- &
				while [[ $(jobs -r | wc -l) -ge $PARALLELISM ]]; do sleep 1; done
			done
			wait
		fi

		# 3. Parallel Build (Slow)
		if [[ ${#SERVICES_TO_BUILD[@]} -gt 0 ]]; then
			if [[ "$MODE" == "cluster" ]]; then
				log "Preparing shared source context for ${#SERVICES_TO_BUILD[@]} services..."
				local UPLOAD_OUT=$(bash "$REPO_DIR/infrastructure/build-pipeline/trigger-build.sh" --upload-only 2>&1)
				export SOURCE_URL=$(echo "$UPLOAD_OUT" | grep "SOURCE_URL=" | cut -d= -f2-)
				export SOURCE_TARBALL=$(echo "$UPLOAD_OUT" | grep "SOURCE_TARBALL=" | cut -d= -f2-)
				log "Shared Context: $SOURCE_TARBALL"
			fi

			log "Starting parallel build of remaining services: ${SERVICES_TO_BUILD[*]:-none} (Parallelism: $PARALLELISM)"
			for svc in "${SERVICES_TO_BUILD[@]}"; do
				# Explicitly close lock FD in background processes to prevent lock inheritance
				build_service "$svc" 200>&- &
				while [[ $(jobs -r | wc -l) -ge $PARALLELISM ]]; do sleep 1; done
			done
			wait
		fi
	fi

    if [[ "$WAIT_FOR_COMPLETION" == "true" && "$MODE" == "cluster" ]]; then
        log "Waiting for cluster builds to complete..."
        # Wait for all jobs with the app=kaniko-build label
        "$KUBECTL" wait --for=condition=complete job -n build-pipeline -l app=kaniko-build --timeout=900s || true
        # After wait, we update timestamps and DEPLOY all services that were successfully built
        for svc in "${SERVICES[@]}" "${INFRA_SERVICES[@]}"; do
             local ver=$(get_svc_version "$svc")
             local last=$(get_svc_last_build "$svc")
             if [[ "$last" == "null" || "$last" == *"(triggered)"* ]]; then
                  local ver_safe="${ver//./-}"
                  if "$KUBECTL" get job -n build-pipeline -l "app=kaniko-build,service=$svc,version=$ver_safe" -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null | grep 1 >/dev/null; then
                       deploy_update "$svc" "$ver"
                       update_svc_info "$svc" "$ver" "\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\""
                  else
                       # Only log error if a job actually exists (it might have been skipped if hash matched)
                       if "$KUBECTL" get job -n build-pipeline -l "app=kaniko-build,service=$svc,version=$ver_safe" 2>/dev/null | grep "$svc" >/dev/null; then
                           log "ERROR: Build for $svc version $ver did not succeed. Skipping deploy update."
                       fi
                  fi
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