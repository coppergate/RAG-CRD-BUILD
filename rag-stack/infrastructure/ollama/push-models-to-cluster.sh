#!/bin/bash
# push-models-to-cluster.sh
# To be executed on host: hierophant
set -e

REGISTRY="registry.hierocracy.home:5000"
OLLAMA_IMAGE="${REGISTRY}/ollama/ollama:0.15.6"

# 1. Sync Models as OCI artifacts to the in-cluster registry
# We'll use a temporary ollama container to pull from library.ollama.com and push to our local registry.

# The seeder uses:
# ollama-llama3.1
# granite31-8b (mapped to granite3.1-dense:8b)

MODELS=("llama3.1" "granite3.1-dense:8b")

echo "--- Pushing Models to Cluster Registry ($REGISTRY) as OCI artifacts ---"

# Start a temporary ollama server to facilitate the pull/push
CONTAINER_NAME="ollama-cluster-sync"
# Use podman on hierophant. We use --tls-verify=false for the registry push later.
podman run -d --name "$CONTAINER_NAME" -e OLLAMA_LLM_LIBRARY=cpu --replace "$OLLAMA_IMAGE"

# Wait for ollama to start
echo "Waiting for Ollama to start in container..."
for i in {1..10}; do
  if podman exec "$CONTAINER_NAME" ollama list >/dev/null 2>&1; then
    echo "Ollama is ready."
    break
  fi
  echo "  waiting..."
  sleep 2
done

for MODEL in "${MODELS[@]}"; do
    # Ollama OCI reference: <registry>/<namespace>/<repository>:<tag>
    
    LOCAL_MODEL_PATH="${REGISTRY}/ollama/${MODEL}"
    
    echo "Processing model: $MODEL -> $LOCAL_MODEL_PATH"

    # Pull model from library.ollama.com
    echo "  Pulling $MODEL from ollama.com..."
    podman exec "$CONTAINER_NAME" ollama pull "$MODEL"

    # Tag (copy) for local registry
    echo "  Tagging (copying) $MODEL as $LOCAL_MODEL_PATH..."
    podman exec "$CONTAINER_NAME" ollama cp "$MODEL" "$LOCAL_MODEL_PATH"

    # Push to local registry
    echo "  Pushing $LOCAL_MODEL_PATH to cluster registry..."
    # We set OLLAMA_REGISTRY_INSECURE=1 to allow HTTPS with self-signed cert or HTTP
    podman exec -e OLLAMA_REGISTRY_INSECURE=1 "$CONTAINER_NAME" ollama push "$LOCAL_MODEL_PATH" --insecure
done

# Cleanup
echo "Cleaning up..."
podman stop "$CONTAINER_NAME"
podman rm "$CONTAINER_NAME"

echo "Models have been pushed to ${REGISTRY}"
