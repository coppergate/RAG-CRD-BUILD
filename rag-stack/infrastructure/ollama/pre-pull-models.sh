#!/bin/bash
# pre-pull-models.sh — Download LLM models to /mnt/storage/ollama-models on hierophant
# Run this OUTSIDE of the install process (one-time or when updating models).
# Models are stored locally so they can be pushed to the in-cluster registry
# and seeded into PVCs without internet access during install.
#
# To be executed on host: hierophant
set -euo pipefail

STORAGE_DIR="${OLLAMA_MODEL_STORE:-/mnt/storage/ollama-models}"
REGISTRY="${REGISTRY:-hierophant.hierocracy.home:5000}"
OLLAMA_IMAGE_LOCAL="${REGISTRY}/ollama/ollama:0.15.6"
OLLAMA_IMAGE_UPSTREAM="docker.io/ollama/ollama:0.15.6"

# Models to pre-pull (add/remove as needed)
MODELS=("llama3.1" "granite3.1-dense:8b")

echo "=== Ollama Model Pre-Pull ==="
echo "Storage:  $STORAGE_DIR"
echo "Registry: $REGISTRY"
echo "Models:   ${MODELS[*]}"
echo ""

mkdir -p "$STORAGE_DIR"

# Ensure the base Ollama image is in the local registry
echo "[0/4] Checking for base Ollama image in local registry..."
if ! podman pull "$OLLAMA_IMAGE_LOCAL" 2>/dev/null; then
  echo "  Base image $OLLAMA_IMAGE_LOCAL not found in local registry."
  echo "  Attempting to pull from upstream $OLLAMA_IMAGE_UPSTREAM..."
  podman pull "$OLLAMA_IMAGE_UPSTREAM"
  echo "  Tagging $OLLAMA_IMAGE_UPSTREAM -> $OLLAMA_IMAGE_LOCAL"
  podman tag "$OLLAMA_IMAGE_UPSTREAM" "$OLLAMA_IMAGE_LOCAL"
  echo "  Pushing $OLLAMA_IMAGE_LOCAL to local registry..."
  podman push "$OLLAMA_IMAGE_LOCAL"
  echo "  ✓ Base image pushed to local registry."
else
  echo "  ✓ Base image found in local registry."
fi

# Start a temporary ollama server with model storage on /mnt/storage
CONTAINER_NAME="ollama-pre-pull"
echo "[1/4] Starting temporary Ollama container..."
podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
podman run -d \
  --name "$CONTAINER_NAME" \
  --replace \
  -v "$STORAGE_DIR:/root/.ollama/models:z" \
  -e OLLAMA_LLM_LIBRARY=cpu \
  "$OLLAMA_IMAGE_LOCAL"

echo "[2/4] Waiting for Ollama to start..."
for i in $(seq 1 30); do
  if podman exec "$CONTAINER_NAME" ollama list >/dev/null 2>&1; then
    echo "  Ollama ready after ${i}s"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Ollama did not start within 30s"
    podman logs "$CONTAINER_NAME"
    podman rm -f "$CONTAINER_NAME"
    exit 1
  fi
  sleep 1
done

echo "[3/4] Pulling models..."
for MODEL in "${MODELS[@]}"; do
  echo "  Pulling $MODEL..."
  podman exec "$CONTAINER_NAME" ollama pull "$MODEL"
  echo "  ✓ $MODEL"
done

echo "[4/4] Pushing models to local registry as OCI artifacts..."
for MODEL in "${MODELS[@]}"; do
  LOCAL_REF="${REGISTRY}/ollama/${MODEL}"
  echo "  Copying $MODEL -> $LOCAL_REF"
  podman exec "$CONTAINER_NAME" ollama cp "$MODEL" "$LOCAL_REF"
  echo "  Pushing $LOCAL_REF..."
  podman exec -e OLLAMA_REGISTRY_INSECURE=1 "$CONTAINER_NAME" ollama push "$LOCAL_REF" --insecure
  echo "  ✓ $LOCAL_REF"
done

# Cleanup
podman stop "$CONTAINER_NAME"
podman rm "$CONTAINER_NAME"

echo ""
echo "=== Pre-Pull Complete ==="
echo "Models stored at: $STORAGE_DIR"
echo "Models pushed to: $REGISTRY"
du -sh "$STORAGE_DIR"
echo ""
echo "During install, ollama pods will pull from the local registry (fast, in-cluster)."
echo "If the registry already has models, the install seed step will be near-instant."
