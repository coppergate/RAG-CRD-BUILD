#!/bin/bash

# Configuration
NAMESPACE="rag-system"
CODE_DIR="/mnt/hegemon-share/share/code/kubernetes-app-setup"
TEST_DIR="${CODE_DIR}/app-builds/RAG/tests"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

echo "--- Preparing RAG Integration Tests ---"

# 1. Recreate the tests ConfigMap
echo "Updating tests ConfigMap..."
$KUBECTL delete configmap rag-integration-tests -n $NAMESPACE --ignore-not-found
$KUBECTL create configmap rag-integration-tests -n $NAMESPACE \
    --from-file="${TEST_DIR}/integration_test.py" \
    --from-file="${TEST_DIR}/context_verification.py"

# 2. Delete existing job
echo "Removing old test job..."
$KUBECTL delete job rag-integration-test -n $NAMESPACE --ignore-not-found

# 3. Apply the job
echo "Launching test job..."
$KUBECTL apply -f "${TEST_DIR}/test-job.yaml"

# 4. Wait for pod and follow logs
echo "Waiting for pod to start..."
sleep 5
POD_NAME=$($KUBECTL get pods -n $NAMESPACE -l job-name=rag-integration-test -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
    echo "Error: Could not find test pod."
    exit 1
fi

echo "Following logs for $POD_NAME..."
$KUBECTL logs -n $NAMESPACE $POD_NAME -f
