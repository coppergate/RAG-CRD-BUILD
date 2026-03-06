#!/bin/bash
# init-rag-pulsar.sh - Provision Pulsar tenants and namespaces for the RAG stack
# Run on hierophant

set -e

NAMESPACE="apache-pulsar"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

echo "--- 1. Locating Pulsar Toolset Pod ---"
# Wait for the toolset pod to be ready
echo "Waiting for Pulsar toolset pod in $NAMESPACE..."
until $KUBECTL get pods -n $NAMESPACE -l component=toolset -o jsonpath='{.items[0].metadata.name}' >/dev/null 2>&1; do
    echo "Pulsar toolset pod not found yet. Sleeping 10s..."
    sleep 10
done

TOOLSET_POD=$($KUBECTL get pods -n $NAMESPACE -l component=toolset -o jsonpath='{.items[0].metadata.name}')
$KUBECTL wait --for=condition=Ready pod/$TOOLSET_POD -n $NAMESPACE --timeout=300s

if [[ -z "$TOOLSET_POD" ]]; then
    echo "ERROR: Pulsar toolset pod not found in namespace $NAMESPACE"
    exit 1
fi

pulsar_admin() {
    $KUBECTL exec -n $NAMESPACE "$TOOLSET_POD" -- /pulsar/bin/pulsar-admin "$@"
}

echo "--- 2. Ensuring 'rag-pipeline' tenant exists ---"
if ! pulsar_admin tenants list | grep -q "^rag-pipeline$"; then
    pulsar_admin tenants create rag-pipeline
    echo "Created tenant: rag-pipeline"
else
    echo "Tenant 'rag-pipeline' already exists"
fi

echo "--- 3. Ensuring namespaces exist ---"
namespaces=("stage" "data" "operations")
for ns in "${namespaces[@]}"; do
    full_ns="rag-pipeline/$ns"
    if ! pulsar_admin namespaces list rag-pipeline | grep -q "^$full_ns$"; then
        pulsar_admin namespaces create "$full_ns"
        echo "Created namespace: $full_ns"
        # Enable topic auto-creation if it was disabled
        pulsar_admin namespaces set-is-allow-auto-update-schema "$full_ns" --enable
    else
        echo "Namespace '$full_ns' already exists"
    fi
done

echo "Pulsar initialization for RAG stack complete."
