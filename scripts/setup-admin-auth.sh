#!/bin/bash
# setup-admin-auth.sh - Helper script to create the rag-admin-api-auth secret on hierophant.

# Load environment if available or use defaults
KUBECONFIG=${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}
KUBECTL=${KUBECTL:-/home/k8s/kube/kubectl}
NAMESPACE=${NAMESPACE:-rag-system}
SECRET_NAME="rag-admin-api-auth"

# Generate a random 32-character API key if not provided
API_KEY=${1:-$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)}

echo "Creating/Updating admin API key secret..."
$KUBECTL create secret generic $SECRET_NAME \
    --namespace $NAMESPACE \
    --from-literal=api-key="$API_KEY" \
    --dry-run=client -o yaml | $KUBECTL apply -f -

echo "--------------------------------------------------"
echo "Admin API Key: $API_KEY"
echo "--------------------------------------------------"
echo "Store this key securely. Use it in the 'X-API-Key' header for requests to rag-admin-api."
