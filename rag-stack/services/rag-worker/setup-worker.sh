#!/bin/bash

# setup-worker.sh - Automated setup for RAG Worker
# To be executed on host: hierophant

set -e

BASE_DIR="/mnt/hegemon-share/share/code/kubernetes-app-setup/app-builds/rag-worker"
NAMESPACE="rag-system"

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

echo "--- 1. Creating Source ConfigMap ---"
$KUBECTL delete configmap rag-worker-source -n $NAMESPACE --ignore-not-found
$KUBECTL create configmap rag-worker-source -n $NAMESPACE \
  --from-file=main.go=$BASE_DIR/cmd/worker/main.go \
  --from-file=config.go=$BASE_DIR/internal/config/config.go \
  --from-file=ollama_client.go=$BASE_DIR/internal/ollama/client.go \
  --from-file=qdrant_client.go=$BASE_DIR/internal/qdrant/client.go

echo "--- 2. Deploying RAG Worker ---"
$KUBECTL apply -f "$BASE_DIR/k8s/deployment.yaml"

echo "--- Worker Deployment Complete ---"
$KUBECTL get pods -n $NAMESPACE -l app=rag-worker
