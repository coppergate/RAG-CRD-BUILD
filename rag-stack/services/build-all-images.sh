#!/bin/bash
# build-all-images.sh - Build and push all RAG service images with versioning

REGISTRY_IP="172.20.1.26:5000"
REGISTRY_DNS="registry.container-registry.svc.cluster.local:5000"
VERSION="1.0.0"
REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
SERVICES=("rag-worker" "rag-ingestion" "rag-web-ui" "llm-gateway" "db-adapter" "qdrant-adapter" "object-store-mgr")

echo "--- Building and Pushing RAG Test Runner ---"
podman build -t "$REGISTRY_IP/rag-test-runner:latest" -t "$REGISTRY_IP/rag-test-runner:$VERSION" -f "$REPO_DIR/tests/Dockerfile.test-runner" "$REPO_DIR/tests"
podman push "$REGISTRY_IP/rag-test-runner:latest" --tls-verify=false
podman push "$REGISTRY_IP/rag-test-runner:$VERSION" --tls-verify=false

for service in "${SERVICES[@]}"; do
  echo "--- Building $service:$VERSION ---"
  cd "$REPO_DIR/services/$service"
  
  # Build with debug trace
  BUILD_TAG="build-$(date +%s)"
  podman build --tag "$BUILD_TAG" -t "$REGISTRY_IP/$service:$VERSION" -t "$REGISTRY_IP/$service:latest" .
  
  # Try to extract trace.json if it exists (it's in the builder stage, so this might be tricky with multi-stage)
  # Instead, let's just push for now. If build is slow, the podman output shows it.
  
  echo "--- Pushing $service:$VERSION ---"
  podman push "$REGISTRY_IP/$service:$VERSION" --tls-verify=false
  podman push "$REGISTRY_IP/$service:latest" --tls-verify=false
done

echo "--- All images built and pushed with version $VERSION ---"
