#!/bin/bash
# build-all-images.sh - Build and push all RAG service images with versioning

REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
VERSION="${VERSION:-1.0.0}"
REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
SERVICES=("rag-worker" "rag-ingestion" "rag-web-ui" "llm-gateway" "db-adapter" "qdrant-adapter" "object-store-mgr")

echo "--- Building and Pushing RAG Test Runner ---"
podman build -t "$REGISTRY/rag-test-runner:$VERSION" -t "$REGISTRY/rag-test-runner:latest" \
  -f "$REPO_DIR/tests/Dockerfile.test-runner" "$REPO_DIR/tests"
podman push "$REGISTRY/rag-test-runner:$VERSION" --tls-verify=false || true
podman push "$REGISTRY/rag-test-runner:latest" --tls-verify=false || true

for service in "${SERVICES[@]}"; do
  echo "--- Building $service:$VERSION ---"
  cd "$REPO_DIR/services/$service"
  
  # Build with debug trace
  BUILD_TAG="build-$(date +%s)"
  podman build --tag "$BUILD_TAG" -t "$REGISTRY/$service:$VERSION" -t "$REGISTRY/$service:latest" .
  
  # Try to extract trace.json if it exists (it's in the builder stage, so this might be tricky with multi-stage)
  # Instead, let's just push for now. If build is slow, the podman output shows it.
  
  echo "--- Pushing $service:$VERSION ---"
  podman push "$REGISTRY/$service:$VERSION" --tls-verify=false || true
  podman push "$REGISTRY/$service:latest" --tls-verify=false || true
done

echo "--- All images built and pushed with version $VERSION ---"
