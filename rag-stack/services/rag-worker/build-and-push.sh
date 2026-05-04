#!/bin/bash
# build-and-push.sh - Build RAG service images and push to local registry

# Default to the externally resolvable registry hostname; allow override via env
REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
SERVICES=("rag-worker" "rag-ingestion" "llm-gateway")

for service in "${SERVICES[@]}"; do
  echo "--- Building $service ---"
  cd "$REPO_DIR/services/$service"
  podman build -t "$REGISTRY/$service:latest" .
  
  echo "--- Pushing $service ---"
  podman push "$REGISTRY/$service:latest" --tls-verify=false
done

echo "--- All images built and pushed ---"
