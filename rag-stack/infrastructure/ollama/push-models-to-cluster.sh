#!/bin/bash
# push-models-to-cluster.sh
# To be executed on host: hierophant
# Runs podman as root (sudo) so it has CAP_CHOWN over the storage root.
set -e

# Keep sudo session alive for the duration of the script
sudo -v
( while true; do sudo -v; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
HIEROPHANT_REGISTRY="${HIEROPHANT_REGISTRY:-10.0.0.1:5000}"
OLLAMA_IMAGE_LOCAL="${REGISTRY}/ollama/ollama:0.15.6"
OLLAMA_IMAGE_UPSTREAM="docker.io/ollama/ollama:0.15.6"
STORAGE_DIR="${OLLAMA_MODEL_STORE:-/mnt/storage/ollama-models}"
REGISTRY_CONFIG_DIR="/mnt/storage/registry-config"

# Ensure directories exist
mkdir -p "$STORAGE_DIR"
mkdir -p "$REGISTRY_CONFIG_DIR"

# 0. Setup TLS trust for the local registry
# We extract the CA from the cluster if missing, and create a combined bundle for the container.
COMBINED_CA="$REGISTRY_CONFIG_DIR/combined-ca-bundle.crt"
LOCAL_CA="$REGISTRY_CONFIG_DIR/ca.crt"

if [ ! -f "$LOCAL_CA" ]; then
    echo "Extracting Registry CA from cluster..."
    export KUBECONFIG=/home/k8s/kube/config/kubeconfig
    /home/k8s/kube/kubectl get secret in-cluster-registry-tls -n container-registry -o jsonpath='{.data.ca\.crt}' | base64 -d > "$LOCAL_CA" || echo "Warning: Could not extract CA from cluster."
fi

if [ -f "$LOCAL_CA" ]; then
    echo "Creating combined CA bundle for container..."
    # Fedora/RHEL path for host CA bundle
    HOST_CA_BUNDLE="/etc/pki/tls/certs/ca-bundle.crt"
    if [ ! -f "$HOST_CA_BUNDLE" ]; then
        # Ubuntu/Debian fallback
        HOST_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
    fi
    cat "$HOST_CA_BUNDLE" "$LOCAL_CA" > "$COMBINED_CA"
fi

# Models to pre-pull (add/remove as needed)
MODELS=("llama3.1" "granite3.1-dense:8b" "qwen2.5:32b" "qwen3:32b" "all-minilm:l6-v2" "nomic-embed-text" "mxbai-embed-large" "llama3.2:3b")

echo "--- Pushing Models to Cluster Registry ($REGISTRY) as OCI artifacts ---"

# ── Pre-pass: serve from hierophant registry if available ─────────────────────
# Models stored by a previous run of extract-registry-to-hierophant.sh are at
# $HIEROPHANT_REGISTRY/ollama/<model>.  We can copy them directly to the cluster
# registry with skopeo, skipping the internet pull entirely.
SKOPEO_CERT_DIR="$(mktemp -d /tmp/skopeo-ollama-certs-XXXXXX)"
trap 'rm -rf "$SKOPEO_CERT_DIR"' EXIT
if [[ -f "$LOCAL_CA" ]]; then
    cp "$LOCAL_CA" "$SKOPEO_CERT_DIR/ca.crt"
fi

needs_pull=()
for MODEL in "${MODELS[@]}"; do
    LOCAL_MODEL_PATH="${REGISTRY}/ollama/${MODEL}"
    HIEROPHANT_PATH="${HIEROPHANT_REGISTRY}/ollama/${MODEL}"

    echo "Checking hierophant for: $MODEL"
    if skopeo inspect \
            --src-cert-dir="$SKOPEO_CERT_DIR" \
            "docker://$HIEROPHANT_PATH" >/dev/null 2>&1; then
        echo "  Found in hierophant — copying directly to cluster registry..."
        if skopeo copy --all \
                --src-cert-dir="$SKOPEO_CERT_DIR" \
                --dest-cert-dir="$SKOPEO_CERT_DIR" \
                "docker://$HIEROPHANT_PATH" \
                "docker://$LOCAL_MODEL_PATH"; then
            echo "  OK: $MODEL (hierophant)"
            continue
        else
            echo "  WARN: hierophant copy failed for $MODEL — will pull from internet"
        fi
    else
        echo "  Not in hierophant"
    fi
    needs_pull+=("$MODEL")
done

if [[ ${#needs_pull[@]} -eq 0 ]]; then
    echo "All models served from hierophant registry. No internet pull needed."
    echo "Models have been pushed to ${REGISTRY}"
    exit 0
fi

echo "${#needs_pull[@]} model(s) need internet pull: ${needs_pull[*]}"

# ── Remaining models: pull from ollama.com via temporary container ─────────────
# Ensure the base Ollama image is available (it might be missing from a fresh cluster registry)
echo "Checking for base Ollama image..."
if ! sudo podman pull "$OLLAMA_IMAGE_LOCAL" 2>/dev/null; then
    echo "  $OLLAMA_IMAGE_LOCAL not in registry. Pulling from $OLLAMA_IMAGE_UPSTREAM..."
    sudo podman pull "$OLLAMA_IMAGE_UPSTREAM"
    sudo podman tag "$OLLAMA_IMAGE_UPSTREAM" "$OLLAMA_IMAGE_LOCAL"
    # We don't necessarily NEED to push it to the registry here, podman will use local if we run it.
    # But it's good practice for other cluster nodes.
    echo "  Pushing base image to local registry..."
    sudo podman push --tls-verify=false "$OLLAMA_IMAGE_LOCAL" || echo "  Warning: Could not push base image, continuing..."
fi

# Start a temporary ollama server to facilitate the pull/push
CONTAINER_NAME="ollama-cluster-sync"
# Use sudo podman on hierophant so storage operations run as root (CAP_CHOWN).
# Mount the local storage to avoid redundant internet downloads.
# Mount the combined CA bundle to trust the local registry while still trusting ollama.com.
# We set OLLAMA_MODELS to a path outside of /root to avoid permission issues with volume mounts.
sudo podman run -d \
  --name "$CONTAINER_NAME" \
  -v "$STORAGE_DIR:/ollama-models:z" \
  -v "$COMBINED_CA:/etc/ssl/certs/ca-certificates.crt:z" \
  -e OLLAMA_MODELS=/ollama-models \
  -e OLLAMA_LLM_LIBRARY=cpu \
  --replace "$OLLAMA_IMAGE_LOCAL"

# Wait for ollama to start
echo "Waiting for Ollama to start in container..."
OLLAMA_STARTED=false
for i in {1..30}; do
  if sudo podman exec "$CONTAINER_NAME" ollama list >/dev/null 2>&1; then
    echo "Ollama is ready."
    OLLAMA_STARTED=true
    break
  fi
  echo "  waiting..."
  sleep 2
done

if [ "$OLLAMA_STARTED" = false ]; then
  echo "ERROR: Ollama failed to start in container."
  sudo podman logs "$CONTAINER_NAME"
  sudo podman rm -f "$CONTAINER_NAME"
  exit 1
fi

for MODEL in "${needs_pull[@]}"; do
    # Ollama OCI reference: <registry>/<namespace>/<repository>:<tag>

    LOCAL_MODEL_PATH="${REGISTRY}/ollama/${MODEL}"

    echo "Processing model: $MODEL -> $LOCAL_MODEL_PATH"

    # Pull model from library.ollama.com
    echo "  Pulling $MODEL from ollama.com..."
    sudo podman exec -e OLLAMA_MODELS=/ollama-models "$CONTAINER_NAME" ollama pull "$MODEL"

    # Tag (copy) for local registry
    echo "  Tagging (copying) $MODEL as $LOCAL_MODEL_PATH..."
    sudo podman exec -e OLLAMA_MODELS=/ollama-models "$CONTAINER_NAME" ollama cp "$MODEL" "$LOCAL_MODEL_PATH"

    # Push to local registry
    echo "  Pushing $LOCAL_MODEL_PATH to cluster registry..."
    sudo podman exec -e OLLAMA_MODELS=/ollama-models "$CONTAINER_NAME" ollama push "$LOCAL_MODEL_PATH"
done

# Cleanup
echo "Cleaning up..."
sudo podman stop "$CONTAINER_NAME"
sudo podman rm "$CONTAINER_NAME"

echo "Models have been pushed to ${REGISTRY}"
