#!/bin/bash
# push-ollama-to-registry.sh
# To be executed on host: hierophant
set -e

REGISTRY="registry.container-registry.svc.cluster.local:5000"
OLLAMA_IMAGE="${REGISTRY}/ollama/ollama"

## 1. Pull and Push Ollama Image
echo "--- 1. Syncing Ollama Image ---"
SYNC_OLLAMA_IMAGE="docker.io/ollama/ollama:0.15.6"
TARGET_IMAGE="${REGISTRY}/ollama/ollama:0.15.6"
podman pull "$SYNC_OLLAMA_IMAGE"
podman tag "$SYNC_OLLAMA_IMAGE" "$TARGET_IMAGE"
podman push "$TARGET_IMAGE" --tls-verify=false
echo "Sync'd image $TARGET_IMAGE"

# Also push latest
podman tag "$SYNC_OLLAMA_IMAGE" "${REGISTRY}/ollama/ollama:latest"
podman push "${REGISTRY}/ollama/ollama:latest" --tls-verify=false
# 2. Push Models as OCI artifacts to the local registry
# Ollama supports pushing models to OCI registries.
# We'll use a temporary ollama container to pull from library.ollama.com and push to our local registry.

MODELS=("codellama" "llama3.1" "mistral" "granite3.1-dense:8b")

echo "--- 2. Pushing Models to Local Registry as OCI artifacts ---"

# Start a temporary ollama server to facilitate the pull/push
CONTAINER_NAME="ollama-registry-sync"
podman run -d --name "$CONTAINER_NAME" -e OLLAMA_LLM_LIBRARY=cpu --replace $OLLAMA_IMAGE

# Wait for ollama to start
echo "Waiting for Ollama to start..."
sleep 5

for MODEL in "${MODELS[@]}"; do
    # Ollama OCI reference: <registry>/<namespace>/<repository>:<tag>
    # Note: OLLAMA_REGISTRY_INSECURE=1 might be needed if the registry is HTTP
    
    LOCAL_MODEL_PATH="${REGISTRY}/ollama/${MODEL}"
    
    echo "Processing model: $MODEL -> $LOCAL_MODEL_PATH"

    # Pull model from library.ollama.com
    echo "Pulling $MODEL..."
    podman exec "$CONTAINER_NAME" ollama pull "$MODEL"

    # Tag (copy) for local registry
    echo "Copying $MODEL to $LOCAL_MODEL_PATH..."
    podman exec "$CONTAINER_NAME" ollama cp "$MODEL" "$LOCAL_MODEL_PATH"

    # Push to local registry
    # We set OLLAMA_REGISTRY_INSECURE=1 to allow HTTP registry
    echo "Pushing $LOCAL_MODEL_PATH..."
    podman exec -e OLLAMA_REGISTRY_INSECURE=1 "$CONTAINER_NAME" ollama push "$LOCAL_MODEL_PATH" --insecure
done

# Cleanup
echo "Cleaning up..."
podman stop "$CONTAINER_NAME"
podman rm "$CONTAINER_NAME"

echo "Ollama base image and models (as OCI artifacts) have been pushed to ${REGISTRY}"
