#!/bin/bash
# manual-seed-granite.sh — Download Ollama models using curl directly into PVC
# To be executed inside a seeder pod with PVC mounted at /ollama-models
set -euo pipefail

MODEL="granite3.1-dense:8b"
# The ollama/ollama runtime image AND every ollama/* model artifact live in the
# upstream mirror on hierophant. The in-cluster registry holds only locally
# built services, so this used to fail twice over: the seeder image was "not
# found", and the model blob fetches curled a registry that never had them.
#
# $REGISTRY is also used as a PATH COMPONENT inside Ollama's model store
# (manifests/$REGISTRY/$REPO). That is safe to change: the seeder also writes
# each manifest to manifests/registry.ollama.ai/library/<model>, which is the
# path consumers resolve by short name, so model lookup does not depend on this.
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../../../config/network.env" ]]; then
    # shellcheck source=../../../config/network.env
    source "$(dirname "${BASH_SOURCE[0]}")/../../../config/network.env"
fi
REGISTRY="${REGISTRY_PREFIX:-hierophant.hierocracy.home:5000}"
REPO="ollama/granite3.1-dense"
TAG="8b"
MODELS_DIR="./ollama-models"
MANIFEST_PATH="${MODELS_DIR}/manifests/${REGISTRY}/${REPO}/${TAG}"
BLOBS_DIR="${MODELS_DIR}/blobs"

echo "=== Manual Seeding: ${REGISTRY}/${REPO}:${TAG} ==="
mkdir -p "$(dirname "$MANIFEST_PATH")"
mkdir -p "${BLOBS_DIR}"

# 1. Fetch Manifest
echo "Fetching manifest..."
curl -v -sk "https://${REGISTRY}/v2/${REPO}/manifests/${TAG}" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  -o "${MANIFEST_PATH}"

# 2. Parse Layers from Manifest
echo "Parsing layers..."
LAYERS=$(cat "${MANIFEST_PATH}" | grep -o 'sha256:[a-f0-9]*')

# 3. Download Blobs
for LAYER in $LAYERS; do
  BLOB_FILE="${BLOBS_DIR}/${LAYER//:/-}"
  if [ -f "$BLOB_FILE" ] && [ -s "$BLOB_FILE" ]; then
    echo "  Blob $LAYER already exists. Skipping."
    continue
  fi
  echo "  Downloading blob $LAYER..."
  # Use -L to follow redirects and -C - to resume if needed
  curl -skL "https://${REGISTRY}/v2/${REPO}/blobs/${LAYER}" \
    -o "${BLOB_FILE}"
done

# 4. Create short-name manifest (copy)
SHORT_MANIFEST_PATH="${MODELS_DIR}/manifests/registry.ollama.ai/library/granite3.1-dense/8b"
mkdir -p "$(dirname "$SHORT_MANIFEST_PATH")"
cp "${MANIFEST_PATH}" "${SHORT_MANIFEST_PATH}"

echo "SUCCESS: Seeding complete for ${MODEL}"
echo "Manifest: ${MANIFEST_PATH}"
echo "Blobs: ${BLOBS_DIR}"
