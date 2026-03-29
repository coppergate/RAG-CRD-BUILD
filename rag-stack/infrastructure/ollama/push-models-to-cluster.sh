#!/bin/bash
# push-models-to-cluster.sh
# To be executed on host: hierophant
set -e

REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
OLLAMA_IMAGE_LOCAL="${REGISTRY}/ollama/ollama:0.15.6"
OLLAMA_IMAGE_UPSTREAM="docker.io/ollama/ollama:0.15.6"
STORAGE_DIR="${OLLAMA_MODEL_STORE:-/mnt/storage/ollama-models}"

# Ensure storage directory exists for caching
mkdir -p "$STORAGE_DIR"

# Models to pre-pull (add/remove as needed)
MODELS=("llama3.1" "granite3.1-dense:8b")

# 1. Sync Models as OCI artifacts to the in-cluster registry
# We'll use a temporary ollama container to pull from library.ollama.com and push to our local registry.
# Using a local volume mount ensures we don't re-download from the internet if already cached.

echo "--- Pushing Models to Cluster Registry ($REGISTRY) as OCI artifacts ---"

# Ensure the base Ollama image is available (it might be missing from a fresh cluster registry)
echo "Checking for base Ollama image..."
if ! podman pull "$OLLAMA_IMAGE_LOCAL" 2>/dev/null; then
    echo "  $OLLAMA_IMAGE_LOCAL not in registry. Pulling from $OLLAMA_IMAGE_UPSTREAM..."
    podman pull "$OLLAMA_IMAGE_UPSTREAM"
    podman tag "$OLLAMA_IMAGE_UPSTREAM" "$OLLAMA_IMAGE_LOCAL"
    # We don't necessarily NEED to push it to the registry here, podman will use local if we run it.
    # But it's good practice for other cluster nodes.
    echo "  Pushing base image to local registry..."
    podman push "$OLLAMA_IMAGE_LOCAL" || echo "  Warning: Could not push base image, continuing..."
fi

# Start a temporary ollama server to facilitate the pull/push
CONTAINER_NAME="ollama-cluster-sync"
# Use podman on hierophant. We use --tls-verify=false for the registry push later.
# Mount the local storage to avoid redundant internet downloads.
# We set OLLAMA_MODELS to a path outside of /root to avoid permission issues with volume mounts.
podman run -d \
  --name "$CONTAINER_NAME" \
  -v "$STORAGE_DIR:/ollama-models:z" \
  -e OLLAMA_MODELS=/ollama-models \
  -e OLLAMA_LLM_LIBRARY=cpu \
  --replace "$OLLAMA_IMAGE_LOCAL"

# Wait for ollama to start
echo "Waiting for Ollama to start in container..."
OLLAMA_STARTED=false
for i in {1..30}; do
  if podman exec "$CONTAINER_NAME" ollama list >/dev/null 2>&1; then
    echo "Ollama is ready."
    OLLAMA_STARTED=true
    break
  fi
  echo "  waiting..."
  sleep 2
done

if [ "$OLLAMA_STARTED" = false ]; then
  echo "ERROR: Ollama failed to start in container."
  podman logs "$CONTAINER_NAME"
  podman rm -f "$CONTAINER_NAME"
  exit 1
fi

for MODEL in "${MODELS[@]}"; do
    # Ollama OCI reference: <registry>/<namespace>/<repository>:<tag>
    
    LOCAL_MODEL_PATH="${REGISTRY}/ollama/${MODEL}"
    
    echo "Processing model: $MODEL -> $LOCAL_MODEL_PATH"

    # Pull model from library.ollama.com
    echo "  Pulling $MODEL from ollama.com..."
    podman exec -e OLLAMA_MODELS=/ollama-models "$CONTAINER_NAME" ollama pull "$MODEL"

    # Tag (copy) for local registry
    echo "  Tagging (copying) $MODEL as $LOCAL_MODEL_PATH..."
    podman exec -e OLLAMA_MODELS=/ollama-models "$CONTAINER_NAME" ollama cp "$MODEL" "$LOCAL_MODEL_PATH"

    # Push to local registry
    echo "  Pushing $LOCAL_MODEL_PATH to cluster registry..."
    # We set OLLAMA_REGISTRY_INSECURE=1 to allow HTTPS with self-signed cert or HTTP
    podman exec -e OLLAMA_REGISTRY_INSECURE=1 -e OLLAMA_MODELS=/ollama-models "$CONTAINER_NAME" ollama push "$LOCAL_MODEL_PATH" --insecure
done

# Cleanup
echo "Cleaning up..."
podman stop "$CONTAINER_NAME"
podman rm "$CONTAINER_NAME"

echo "Models have been pushed to ${REGISTRY}"
