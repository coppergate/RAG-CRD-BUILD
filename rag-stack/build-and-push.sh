#!/bin/bash
# build-and-push.sh - Build RAG service images and push to canonical registry (resumable + change-detection)

set -Eeuo pipefail

# Canonical registry reachable from hierophant (resolves to 172.20.1.26)
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
VERSION="${VERSION:-2.4.1}"
TLS_VERIFY="${TLS_VERIFY:-false}"

REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
BUILD_DIR="${BUILD_DIR:-$HOME/build}"
JOURNAL_DIR="${JOURNAL_DIR:-/home/junie/rag-build-journals}"
ONLY="${ONLY:-}"
START_FROM="${START_FROM:-}"
FORCE_BUILD="${FORCE_BUILD:-false}"
SKIP_UNCHANGED="${SKIP_UNCHANGED:-true}"

mkdir -p "$JOURNAL_DIR"

SERVICES=("rag-worker" "rag-ingestion" "rag-web-ui" "llm-gateway" "db-adapter" "qdrant-adapter" "object-store-mgr")

contains() { local n=$#; local value=${!n}; for ((i=1;i<n;i++)); do [[ "${!i}" == "${value}" ]] && return 0; done; return 1; }

service_should_run() {
  local svc="$1"
  if [[ -n "$ONLY" && "$svc" != "$ONLY" ]]; then return 1; fi
  if [[ -n "$START_FROM" ]]; then
    local seen_file="$JOURNAL_DIR/.start_seen"
    if [[ ! -f "$seen_file" ]]; then
      if [[ "$svc" == "$START_FROM" ]]; then echo 1 > "$seen_file"; return 0; else return 1; fi
    fi
  fi
  return 0
}

hash_context() {
  local path="$1"
  # Hash all files under service dir deterministically (excluding VCS/ignored dirs)
  (cd "$path" && find . -type f \( -name '.git' -prune -o -print \) | sort | xargs sha256sum | sha256sum | awk '{print $1}')
}

is_pushed() {
  local svc="$1"; local ver="$2"
  [[ -f "$JOURNAL_DIR/${svc}.${ver}.pushed" ]]
}

mark_pushed() {
  local svc="$1"; local ver="$2"
  : > "$JOURNAL_DIR/${svc}.${ver}.pushed"
}

save_hash() {
  local svc="$1"; local ver="$2"; local hash="$3"
  echo -n "$hash" > "$JOURNAL_DIR/${svc}.${ver}.hash"
}

load_hash() {
  local svc="$1"; local ver="$2"
  if [[ -f "$JOURNAL_DIR/${svc}.${ver}.hash" ]]; then cat "$JOURNAL_DIR/${svc}.${ver}.hash"; fi
}

build_service() {
  local service="$1"
  echo "--- Processing $service ---"

  if [ -d "$BUILD_DIR/$service" ]; then
    echo "--- Building from shadow build directory: $BUILD_DIR/$service ---"
    cd "$BUILD_DIR/$service"
  else
    echo "--- Building from repo directory: $REPO_DIR/services/$service ---"
    cd "$REPO_DIR/services/$service"
  fi

  local_hash=$(hash_context ".")
  prev_hash=$(load_hash "$service" "$VERSION" || true)

  # Determine whether to rebuild
  do_build=false
  if [[ "$FORCE_BUILD" == "true" ]]; then
    do_build=true
  elif [[ "$SKIP_UNCHANGED" == "true" && "$local_hash" == "$prev_hash" ]]; then
    if is_pushed "$service" "$VERSION"; then
      echo "SKIP: $service unchanged and already pushed for $VERSION"
      return 0
    else
      # unchanged but not pushed (previous run may have failed during push) — attempt push without rebuild
      do_build=false
    fi
  else
    do_build=true
  fi

  if [[ "$do_build" == "true" ]]; then
    echo "--- Building $service:$VERSION ---"
    BUILD_TAG="build-$(date +%s)"
    
    # Force rebuild without cache if requested
    NO_CACHE=""
    if [[ "$FORCE_BUILD" == "true" ]]; then
      NO_CACHE="--no-cache"
    fi

    # All services now use the parent 'services' directory as context to include 'common/' 
    # and consistent COPY paths in Dockerfiles.
    podman build --tls-verify="$TLS_VERIFY" $NO_CACHE --tag "$BUILD_TAG" -t "$REGISTRY/$service:$VERSION" -t "$REGISTRY/$service:latest" -f "$REPO_DIR/services/$service/Dockerfile" "$REPO_DIR/services"
  fi

  echo "--- Pushing $service:$VERSION ---"
  podman push "$REGISTRY/$service:$VERSION" --tls-verify="$TLS_VERIFY"
  podman push "$REGISTRY/$service:latest"  --tls-verify="$TLS_VERIFY"

  save_hash "$service" "$VERSION" "$local_hash"
  mark_pushed "$service" "$VERSION"
}

# Check if we should build individual services
if [[ -n "$ONLY" ]]; then
  IFS=',' read -ra ADDR <<< "$ONLY"
  for service in "${ADDR[@]}"; do
    build_service "$service"
  done
  exit 0
fi

echo "--- Building and Pushing RAG Test Runner (resumable) ---"
cd "$REPO_DIR/tests"
TT_HASH=$(hash_context ".")
TT_OLD=$(load_hash "rag-test-runner" "$VERSION" || true)
NEED_BUILD_TEST_RUNNER=false
if [[ "$FORCE_BUILD" == "true" || "$SKIP_UNCHANGED" != "true" ]]; then
  NEED_BUILD_TEST_RUNNER=true
elif [[ "$TT_HASH" != "$TT_OLD" ]]; then
  NEED_BUILD_TEST_RUNNER=true
elif ! is_pushed "rag-test-runner" "$VERSION"; then
  NEED_BUILD_TEST_RUNNER=true
fi
if [[ "$NEED_BUILD_TEST_RUNNER" == "true" ]]; then
  podman build --tls-verify="$TLS_VERIFY" -t "$REGISTRY/rag-test-runner:$VERSION" -t "$REGISTRY/rag-test-runner:latest" -f "$REPO_DIR/tests/Dockerfile.test-runner" "$REPO_DIR/tests"
  podman push "$REGISTRY/rag-test-runner:$VERSION" --tls-verify="$TLS_VERIFY"
  podman push "$REGISTRY/rag-test-runner:latest"  --tls-verify="$TLS_VERIFY"
  save_hash "rag-test-runner" "$VERSION" "$TT_HASH"
  mark_pushed "rag-test-runner" "$VERSION"
else
  echo "SKIP: rag-test-runner unchanged and already pushed for $VERSION"
fi

echo "--- Processing Services in Parallel ---"
PIDS=()
for service in "${SERVICES[@]}"; do
  service_should_run "$service" || { echo "SKIP (filter): $service"; continue; }
  
  (
    build_service "$service"
  ) &
  PIDS+=($!)
done

# Wait for all background builds to complete
for pid in "${PIDS[@]}"; do
  wait "$pid"
done

if [[ "${VERIFY_TAGS:-true}" == "true" ]]; then
  echo "--- Verifying image tags present in registry: $REGISTRY (version $VERSION) ---"
  SCRIPT_DIR="/mnt/hegemon-share/share/code/complete-build/scripts"
  if [[ -x "$SCRIPT_DIR/verify-registry-tags.sh" ]]; then
    (cd "/mnt/hegemon-share/share/code/complete-build" && \
      VERSION="$VERSION" REGISTRY_CANON="$REGISTRY" REGISTRY_ENDPOINTS="$REGISTRY" \
      "$SCRIPT_DIR/verify-registry-tags.sh") || {
        echo "ERROR: Tag verification failed. Review output above." >&2
        exit 2
      }
  else
    echo "WARN: verify-registry-tags.sh not found or not executable; skipping verification"
  fi
fi

echo "--- All images processed for $REGISTRY with version $VERSION ---"
