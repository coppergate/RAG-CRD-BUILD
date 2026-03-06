#!/bin/bash
# build-all-images.sh - Build and push all RAG service images in PARALLEL
# Usage: VERSION=1.5.3 [MAX_PARALLEL=4] ./build-all-images.sh

set -euo pipefail

REGISTRY="${REGISTRY:-172.20.1.26:5000}"
VERSION="${VERSION:-1.5.3}"
REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
OUT_DIR="/mnt/hegemon-share/share/code/complete-build/ai-changes/build-output"
MAX_PARALLEL="${MAX_PARALLEL:-1}"
CPU_LIMIT="${CPU_LIMIT:-4}"
MEMORY_LIMIT="${MEMORY_LIMIT:-4g}"

mkdir -p "$OUT_DIR"
REPORT_FILE="$OUT_DIR/build-report-${VERSION}.txt"
TEMP_REPORT_DIR=$(mktemp -d -p "$OUT_DIR" .tmp_reports_XXXXXX)

echo "Build Report - $(date)" > "$REPORT_FILE"
echo "------------------------------------" >> "$REPORT_FILE"

# Function to build and push a single service/component
process_component() {
  local component=$1
  local context_path=$2
  local dockerfile=$3
  local label=$4
  local log_prefix=$5
  
  local build_log="$OUT_DIR/${log_prefix}-build.log"
  local push_log="$OUT_DIR/${log_prefix}-push.log"
  local temp_report="$TEMP_REPORT_DIR/${log_prefix}.txt"

  echo "[$(date +%T)] STARTING: $label"
  local start=$(date +%s)

  # 1. Build
  if podman build --cpu-shares 1024 --memory "$MEMORY_LIMIT" -t "$REGISTRY/$component:$VERSION" -t "$REGISTRY/$component:latest" \
     -f "$dockerfile" "$context_path" > "$build_log" 2>&1; then
    
    # 2. Push
    if podman push "$REGISTRY/$component:$VERSION" --tls-verify=false > "$push_log" 2>&1; then
      podman push "$REGISTRY/$component:latest" --tls-verify=false > /dev/null 2>&1 || true
      local end=$(date +%s)
      local duration=$((end - start))
      echo "[$(date +%T)] FINISHED: $label (Duration: ${duration}s)"
      echo "$label: ${duration}s (SUCCESS)" > "$temp_report"
    else
      local end=$(date +%s)
      local duration=$((end - start))
      echo "[$(date +%T)] PUSH FAILED: $label (Duration: ${duration}s). See $push_log"
      echo "$label: FAILED (Push) (${duration}s)" > "$temp_report"
    fi
  else
    local end=$(date +%s)
    local duration=$((end - start))
    echo "[$(date +%T)] BUILD FAILED: $label (Duration: ${duration}s). See $build_log"
    echo "$label: FAILED (Build) (${duration}s)" > "$temp_report"
  fi
}

echo "--- Initializing Parallel Build (Max Parallel: $MAX_PARALLEL) ---"

# Build list of tasks
# Format: component|context_path|dockerfile|label|log_prefix
TASKS=(
  "rag-test-runner|$REPO_DIR/tests|$REPO_DIR/tests/Dockerfile.test-runner|Test Runner|test-runner"
  "rag-worker|$REPO_DIR/services|$REPO_DIR/services/rag-worker/Dockerfile|rag-worker|rag-worker"
  "rag-ingestion|$REPO_DIR/services/rag-ingestion|$REPO_DIR/services/rag-ingestion/Dockerfile|rag-ingestion|rag-ingestion"
  "rag-web-ui|$REPO_DIR/services|$REPO_DIR/services/rag-web-ui/Dockerfile|rag-web-ui|rag-web-ui"
  "llm-gateway|$REPO_DIR/services|$REPO_DIR/services/llm-gateway/Dockerfile|llm-gateway|llm-gateway"
  "db-adapter|$REPO_DIR/services|$REPO_DIR/services/db-adapter/Dockerfile|db-adapter|db-adapter"
  "qdrant-adapter|$REPO_DIR/services|$REPO_DIR/services/qdrant-adapter/Dockerfile|qdrant-adapter|qdrant-adapter"
  "object-store-mgr|$REPO_DIR/services|$REPO_DIR/services/object-store-mgr/Dockerfile|object-store-mgr|object-store-mgr"
)

# Launch tasks with a simple semaphore to control parallelization
for task in "${TASKS[@]}"; do
  (
    IFS='|' read -r component context_path dockerfile label log_prefix <<< "$task"
    process_component "$component" "$context_path" "$dockerfile" "$label" "$log_prefix"
  ) &
  
  # Limit number of parallel background jobs
  while [ "$(jobs -r | wc -l)" -ge "$MAX_PARALLEL" ]; do
    sleep 1
  done
done

# Wait for all jobs to complete
echo "[$(date +%T)] All tasks launched. Waiting for completion..."
wait

# Consolidate reports
echo "Consolidating report..."
for f in "$TEMP_REPORT_DIR"/*.txt; do
  [ -e "$f" ] && cat "$f" >> "$REPORT_FILE"
done
rm -rf "$TEMP_REPORT_DIR"

echo ""
echo "--- Parallel Build Summary ---"
cat "$REPORT_FILE"
echo "------------------------------------"
echo "All images processed. Logs available in $OUT_DIR"
