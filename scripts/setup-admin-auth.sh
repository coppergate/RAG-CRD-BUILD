#!/bin/bash
# Helper script to create the rag-admin-api authentication secret on hierophant.
# This script should be run on the hierophant host.

NAMESPACE="rag-system"
SECRET_NAME="rag-admin-api-auth"

# Generate a random 32-character hex API key
API_KEY=$(openssl rand -hex 32)

echo "Creating secret ${SECRET_NAME} in namespace ${NAMESPACE}..."

kubectl create secret generic ${SECRET_NAME} \
  --from-literal=api-key="${API_KEY}" \
  -n ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

echo "--------------------------------------------------"
echo "API Key generated: ${API_KEY}"
echo "--------------------------------------------------"
echo "IMPORTANT: Copy this key and add it to your Flutter app's environment configuration."
echo "The rag-admin-api will now require this key in the Authorization header (Bearer <key>)."
echo "--------------------------------------------------"
