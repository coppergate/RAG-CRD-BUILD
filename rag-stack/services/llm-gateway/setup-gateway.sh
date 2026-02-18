#!/bin/bash
# setup-gateway.sh - Create source-code ConfigMap and deploy LLM Gateway
# To be executed on host: hierophant

set -e

NAMESPACE="rag-system"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
BASE_DIR="/mnt/hegemon-share/share/code/kubernetes-app-setup/app-builds/llm-gateway"

echo "--- 1. Creating Source ConfigMap ---"
# We bundle the Go code into a ConfigMap to avoid needing a private registry for this POC
$KUBECTL create configmap llm-gateway-source -n $NAMESPACE \
  --from-file=main.go=$BASE_DIR/cmd/gateway/main.go \
  --from-file=config.go=$BASE_DIR/internal/config/config.go \
  --from-file=openai.go=$BASE_DIR/internal/handlers/openai.go \
  --from-file=client.go=$BASE_DIR/internal/pulsar/client.go \
  --dry-run=client -o yaml | $KUBECTL apply -f -

echo "--- 2. Applying Configuration ---"
$KUBECTL apply -f $BASE_DIR/k8s/configmap.yaml

echo "--- 3. Deploying Gateway ---"
$KUBECTL apply -f $BASE_DIR/k8s/deployment.yaml

echo "--- Deployment Complete ---"
echo "Gateway endpoint: http://gateway.rag.local/v1/chat/completions"
echo "Check pods: $KUBECTL get pods -n $NAMESPACE -l app=llm-gateway"
