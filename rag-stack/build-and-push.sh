#!/bin/bash
# build-and-push.sh - Build RAG service images and push to local registry

REGISTRY="registry.container-registry.svc.cluster.local:5000"
REPO_DIR="/mnt/hegemon-share/share/code/complete-build/rag-stack"
BUILD_DIR="/home/junie/build"
SERVICES=("rag-worker" "rag-ingestion" "rag-web-ui" "llm-gateway" "db-adapter" "qdrant-adapter" "object-store-mgr")

echo "--- Building and Pushing RAG Test Runner ---"
podman build -t "$REGISTRY/rag-test-runner:latest" -f "$REPO_DIR/tests/Dockerfile.test-runner" "$REPO_DIR/tests"
podman push "$REGISTRY/rag-test-runner:latest" --tls-verify=false

for service in "${SERVICES[@]}"; do
  echo "--- Processing $service ---"
  
  if [ -d "$BUILD_DIR/$service" ]; then
    echo "--- Building from shadow build directory: $BUILD_DIR/$service ---"
    cd "$BUILD_DIR/$service"
  else
    echo "--- Building from repo directory: $REPO_DIR/services/$service ---"
    cd "$REPO_DIR/services/$service"
  fi

  echo "--- Building $service ---"
  podman build -t "$REGISTRY/$service:latest" .
  
  echo "--- Pushing $service ---"
  podman push "$REGISTRY/$service:latest" --tls-verify=false
done

echo "--- All images built and pushed ---"
