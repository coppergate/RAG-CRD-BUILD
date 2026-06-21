#!/bin/bash
# rag-stack/build.sh - Unified Build Entry Point (Cluster or Local)
# Supports per-service versioning, change detection, and parallel builds.
# To be executed on host: hierophant

set -Eeuo pipefail
set -m # Enable job control for reliable parallel build tracking

# --- Configuration & Defaults ---
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$REPO_DIR/.." && pwd)
CURRENT_VERSION_FILE="$BASE_DIR/CURRENT_VERSION"
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"

# Build settings
MODE="${MODE:-cluster}"
# Try to resolve build-orchestrator.hierocracy.home, fallback to LoadBalancer IP if needed
DEFAULT_METADATA_URL="http://build-orchestrator.hierocracy.home/api/build"
if ! host build-orchestrator.hierocracy.home >/dev/null 2>&1; then
    LB_IP=$($KUBECTL get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "172.20.1.16")
    DEFAULT_METADATA_URL="http://${LB_IP}/api/build"
    # We'll need to pass the Host header in curl calls if using IP
    CURL_H_HEADER="Host: build-orchestrator.hierocracy.home"
fi
BUILD_METADATA_URL="${BUILD_METADATA_URL:-$DEFAULT_METADATA_URL}"
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
FORCE_BUILD="${FORCE_BUILD:-false}"
WAIT_FOR_COMPLETION="${WAIT_FOR_COMPLETION:-false}"
OVERRIDE_VERSION="${OVERRIDE_VERSION:-}"
PARALLELISM="${PARALLELISM:-4}"

# --- Locking Configuration ---
acquire_lock() {
    local svc="$1"
    local timeout_seconds=900 # 15 minutes
    local elapsed=0
    local wait_step=10
    local h_args=()
    [[ -n "${CURL_H_HEADER:-}" ]] && h_args=(-H "$CURL_H_HEADER")
    
    log "Attempting to acquire build lock for $svc..."
    
    while true; do
        local response=$(curl -s "${h_args[@]}" -X POST "$BUILD_METADATA_URL/locks/acquire" \
            -d "{\"service_name\": \"$svc\", \"owner\": \"$(id -un)\", \"host\": \"${HOSTNAME:-unknown}\", \"pid\": $$}")
        
        local status=$?
        if [[ $status -eq 0 ]] && [[ -z $(echo "$response" | grep "service_name") ]]; then
             # Lock acquired! (Empty response with success status)
             break
        fi
        
        if [[ $elapsed -ge $timeout_seconds ]]; then
            log "ERROR: Could not acquire build lock for $svc after ${timeout_seconds}s."
            log "Current lock owner details: $response"
            exit 1
        fi
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log "Waiting for build lock for $svc... (elapsed: ${elapsed}s)"
            log "Conflict info: $response"
        fi
        
        sleep "$wait_step"
        elapsed=$((elapsed + wait_step))
    done
    
    # Start heartbeat in background
    ( 
        while true; do 
            curl -s "${h_args[@]}" -X POST "$BUILD_METADATA_URL/locks/heartbeat/$svc" >/dev/null
            sleep 15
        done 
    ) &
    HB_PIDS["$svc"]=$!
    
    log "Build lock acquired for $svc."
}

release_lock() {
    local svc="$1"
    local h_args=()
    [[ -n "${CURL_H_HEADER:-}" ]] && h_args=(-H "$CURL_H_HEADER")

    # Stop heartbeat
    if [[ -n "${HB_PIDS[$svc]:-}" ]]; then
        kill "${HB_PIDS[$svc]}" 2>/dev/null || true
    fi
    
    curl -s "${h_args[@]}" -X POST "$BUILD_METADATA_URL/locks/release/$svc" >/dev/null
    log "Build lock released for $svc."
}

# For backward compatibility if needed, but we prefer per-service
declare -A HB_PIDS
# trap 'for svc in "${!HB_PIDS[@]}"; do release_lock "$svc"; done' EXIT
# Actually, the trap in build_service will handle it better for parallel builds.

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
    "embed-gateway"
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
    local h_args=()
    [[ -n "${CURL_H_HEADER:-}" ]] && h_args=(-H "$CURL_H_HEADER")
    curl -s "${h_args[@]}" "$BUILD_METADATA_URL/versions/$svc" | jq -r ".version // \"1.0.0\""
}

get_svc_last_build() {
    local svc="$1"
    local h_args=()
    [[ -n "${CURL_H_HEADER:-}" ]] && h_args=(-H "$CURL_H_HEADER")
    curl -s "${h_args[@]}" "$BUILD_METADATA_URL/versions/$svc" | jq -r ".last_build // empty"
}

update_svc_info() {
    local svc="$1"; local ver="$2"
    local h_args=()
    [[ -n "${CURL_H_HEADER:-}" ]] && h_args=(-H "$CURL_H_HEADER")
    curl -s "${h_args[@]}" -X POST "$BUILD_METADATA_URL/versions/$svc" -d "{\"version\": \"$ver\"}" >/dev/null
}

sync_current_version_file() {
    if [[ ! -f "$CURRENT_VERSION_FILE" ]]; then
        return 0
    fi

    local tmp_file
    tmp_file="$(mktemp "${SAFE_TMP_DIR:-/tmp}/current-version.XXXXXX")"
    local h_args=()
    [[ -n "${CURL_H_HEADER:-}" ]] && h_args=(-H "$CURL_H_HEADER")

    if curl -s "${h_args[@]}" "$BUILD_METADATA_URL/versions" \
        | jq 'sort_by(.service_name) | map({key: .service_name, value: {version: .version, last_build: .last_build}}) | from_entries' \
        > "$tmp_file"; then
        mv "$tmp_file" "$CURRENT_VERSION_FILE"
        chmod 664 "$CURRENT_VERSION_FILE"
    else
        rm -f "$tmp_file"
        log "WARN: Could not sync CURRENT_VERSION from build metadata."
    fi
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
    local h_args=()
    [[ -n "${CURL_H_HEADER:-}" ]] && h_args=(-H "$CURL_H_HEADER")
    local last_hash=$(curl -s "${h_args[@]}" "$BUILD_METADATA_URL/journals/$svc" | jq -r ".last_hash // empty")
    [[ -n "$last_hash" ]] && [[ "$last_hash" == "$hash" ]]
}

mark_unchanged() {
    local svc="$1"; local hash="$2"
    local h_args=()
    [[ -n "${CURL_H_HEADER:-}" ]] && h_args=(-H "$CURL_H_HEADER")
    curl -s "${h_args[@]}" -X POST "$BUILD_METADATA_URL/journals/$svc" -d "{\"last_hash\": \"$hash\"}" >/dev/null
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
        # Extract namespace from manifest and skip if it doesn't exist yet (fresh cluster).
        # setup-all.sh will do the initial deployment; deploy_update only rolls running deployments.
        local ns
        ns=$(grep -m1 'namespace:' "$manifest" | awk '{print $2}' || true)
        if [[ -n "$ns" ]] && ! "$KUBECTL" get namespace "$ns" >/dev/null 2>&1; then
            log "SKIP deploy update for $svc: namespace $ns does not exist yet"
            return 0
        fi
        # Replace __VERSION__ and apply
        # We handle both the external and internal registry names for substitution
        sed -e "s|__VERSION__|${ver}|g" \
            -e "s|registry.hierocracy.home:5000|${REGISTRY}|g" \
            -e "s|registry.container-registry.svc.cluster.local:5000|${REGISTRY}|g" \
            "$manifest" | "$KUBECTL" apply -f -
    elif [[ -n "$manifest" ]]; then
        log "WARN: Manifest not found for $svc at $manifest"
    fi

    # Apply service manifest if one exists alongside the deployment (idempotent).
    # Services are not versioned and can be lost during cluster recovery without
    # being recreated by build.sh — this ensures they are always reconciled.
    local svc_manifest=""
    case "$svc" in
        "object-store-mgr") svc_manifest="$REPO_DIR/services/object-store-mgr/mgr-service.yaml" ;;
        "build-orchestrator"|"rag-test-runner") svc_manifest="" ;;
        *) svc_manifest="$REPO_DIR/services/$svc/k8s/service.yaml" ;;
    esac
    if [[ -n "$svc_manifest" && -f "$svc_manifest" ]]; then
        "$KUBECTL" apply -f "$svc_manifest"
    fi
}

build_service() {
    local svc="$1"
    acquire_lock "$svc"
    
    # Internal trap to release lock on exit
    trap "release_lock '$svc'" EXIT
    
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
        update_svc_info "$svc" "$ver"
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
            update_svc_info "$svc" "$ver"
            deploy_update "$svc" "$ver"
            return 0
        fi

        log "BUILD: $svc version $ver (Mode: $MODE)"
        if [[ "$MODE" == "cluster" ]]; then
            bash "$REPO_DIR/infrastructure/build-pipeline/trigger-build.sh" "$svc" "$ver"
            # Record this service as triggered so --wait can find it reliably.
            # The API cannot store a custom last_build sentinel (it always writes time.Now()),
            # so we use a temp file owned by the main process instead.
            echo "$svc $ver" >> "${TRIGGERED_FILE:-/dev/null}"
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
            update_svc_info "$svc" "$ver"
            deploy_update "$svc" "$ver"
            sync_current_version_file
        fi
        # In cluster mode, deploy is deferred to the --wait phase after the Kaniko
        # job completes, to avoid ImagePullBackOff on pods.
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

    # Temp file for tracking which services had Kaniko builds triggered this run.
    # Subshells write "svc ver" lines here; the --wait section reads it.
    # Exported so parallel build_service subshells can append to it.
    TRIGGERED_FILE=$(mktemp /tmp/build-triggered.XXXXXX)
    export TRIGGERED_FILE
    trap "rm -f '$TRIGGERED_FILE'" EXIT

	cleanup_old_jobs

	if [[ ${#SELECTED_SERVICES[@]} -gt 0 ]]; then
		log "Building selected services: ${SELECTED_SERVICES[*]} (Parallelism: $PARALLELISM)"
		local pids=()
		for svc in "${SELECTED_SERVICES[@]}"; do
			build_service "$svc" 200>&- &
			pids+=($!)
			while [[ $(jobs -r | wc -l) -ge $PARALLELISM ]]; do sleep 1; done
		done
		for pid in "${pids[@]}"; do wait "$pid"; done
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
			elif [[ "$last_build" == "null" || -z "$last_build" || "$last_build" == *"(triggered)"* ]]; then
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
				if ! "$KUBECTL" wait --for=condition=complete job -n build-pipeline -l "app=kaniko-build,service=build-orchestrator,version=$bver_safe" --timeout=600s; then
                    log "ERROR: build-orchestrator Kaniko job did not complete in time."
                    exit 1
                fi
				
				# Verify success before deploying
				if "$KUBECTL" get job -n build-pipeline -l "app=kaniko-build,service=build-orchestrator,version=$bver_safe" -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null | grep 1 >/dev/null; then
					deploy_update "build-orchestrator" "$bver"
					update_svc_info "build-orchestrator" "$bver"
				else
					log "ERROR: build-orchestrator build failed. Cannot update deployment."
                    exit 1
				fi

				log "Waiting for build-orchestrator rollout..."
				if ! "$KUBECTL" rollout status deployment/build-orchestrator -n build-pipeline --timeout=300s; then
                    log "ERROR: build-orchestrator rollout failed."
                    exit 1
                fi
				sleep 10 # Allow new orchestrator to stabilize
			fi
		fi

		# 2. Parallel Skip-and-Deploy (Fast)
		if [[ ${#SERVICES_TO_DEPLOY[@]} -gt 0 ]]; then
			log "Starting parallel deployment update for existing images: ${SERVICES_TO_DEPLOY[*]} (Parallelism: $PARALLELISM)"
			local dpids=()
			for svc in "${SERVICES_TO_DEPLOY[@]}"; do
				build_service "$svc" 200>&- &
				dpids+=($!)
				while [[ $(jobs -r | wc -l) -ge $PARALLELISM ]]; do sleep 1; done
			done
			for pid in "${dpids[@]}"; do wait "$pid"; done
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
			local bpids=()
			for svc in "${SERVICES_TO_BUILD[@]}"; do
				# Explicitly close lock FD in background processes to prevent lock inheritance
				build_service "$svc" 200>&- &
				bpids+=($!)
				while [[ $(jobs -r | wc -l) -ge $PARALLELISM ]]; do sleep 1; done
			done
			for pid in "${bpids[@]}"; do wait "$pid"; done
		fi
	fi

    if [[ "$WAIT_FOR_COMPLETION" == "true" && "$MODE" == "cluster" ]]; then
        log "Waiting for cluster builds to complete (timeout: 1800s)..."
        local deadline=$((SECONDS + 1800))

        # Read the list of "svc ver" pairs written by build_service() subshells.
        # This is reliable because the API cannot store a custom last_build value
        # (it always writes time.Now()), so a temp file is the only safe IPC channel.
        local triggered_svcs=()
        local triggered_vers=()
        if [[ -s "${TRIGGERED_FILE:-}" ]]; then
            while IFS=" " read -r t_svc t_ver; do
                [[ -n "$t_svc" ]] && triggered_svcs+=("$t_svc") && triggered_vers+=("$t_ver")
            done < "$TRIGGERED_FILE"
        fi

        if [[ ${#triggered_svcs[@]} -eq 0 ]]; then
            log "No cluster builds were triggered this run; nothing to wait for."
        else
            log "Triggered Kaniko builds: ${triggered_svcs[*]}"

            # Phase 1: Poll until each triggered service's Kaniko job EXISTS in k8s.
            # The build-orchestrator creates jobs asynchronously after receiving Pulsar
            # messages, so jobs may not yet exist when this wait block runs.
            local JOB_APPEAR_TIMEOUT=300
            for i in "${!triggered_svcs[@]}"; do
                local svc="${triggered_svcs[$i]}"
                local ver="${triggered_vers[$i]}"
                local ver_safe="${ver//./-}"
                local job_label="app=kaniko-build,service=$svc,version=$ver_safe"
                log "Waiting for Kaniko job to be created: $svc $ver..."
                local job_start=$SECONDS
                while ! "$KUBECTL" get job -n build-pipeline \
                    -l "$job_label" --no-headers 2>/dev/null | grep -q .; do
                    if [[ $((SECONDS - job_start)) -ge $JOB_APPEAR_TIMEOUT ]]; then
                        log "TIMEOUT (${JOB_APPEAR_TIMEOUT}s): Kaniko job for $svc $ver never appeared in cluster."
                        break
                    fi
                    if [[ $SECONDS -ge $deadline ]]; then
                        log "DEADLINE REACHED waiting for Kaniko job to appear: $svc $ver"
                        break
                    fi
                    sleep 5
                done
                log "Kaniko job present: $svc $ver"
            done

            # Phase 2: All triggered jobs now exist; wait for them all to complete.
            local remaining=$(( deadline - SECONDS ))
            if [[ $remaining -le 0 ]]; then
                log "WARN: Overall deadline exhausted during job-appearance polling."
            else
                if ! "$KUBECTL" wait --for=condition=complete job \
                    -n build-pipeline -l app=kaniko-build \
                    --timeout="${remaining}s"; then
                    log "WARN: Some build jobs did not complete successfully or timed out."
                fi
            fi

            # Phase 3: Deploy all services whose Kaniko job succeeded.
            for i in "${!triggered_svcs[@]}"; do
                local svc="${triggered_svcs[$i]}"
                local ver="${triggered_vers[$i]}"
                local ver_safe="${ver//./-}"
                local job_label="app=kaniko-build,service=$svc,version=$ver_safe"
                if "$KUBECTL" get job -n build-pipeline \
                    -l "$job_label" \
                    -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null | grep -q 1; then
                    deploy_update "$svc" "$ver"
                    update_svc_info "$svc" "$ver"
                else
                    log "ERROR: Build for $svc version $ver did not succeed. Skipping deploy update."
                fi
            done
        fi

        sync_current_version_file
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
