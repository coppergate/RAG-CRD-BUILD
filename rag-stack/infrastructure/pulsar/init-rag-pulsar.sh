#!/bin/bash
# init-rag-pulsar.sh - Provision Pulsar tenants and namespaces for the RAG stack
# Run on hierophant

set -Eeuo pipefail

NAMESPACE="apache-pulsar"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
WAIT_SECONDS="${PULSAR_TOOL_POD_WAIT_SECONDS:-600}"
POLL_SECONDS=10

find_pulsar_admin_pod() {
    local pod=""
    local selectors=(
        "component=toolset"
        "app.kubernetes.io/component=toolset"
        "component=broker"
        "app.kubernetes.io/component=broker"
    )
    local sel
    for sel in "${selectors[@]}"; do
        pod=$($KUBECTL get pods -n "$NAMESPACE" -l "$sel" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [[ -n "$pod" ]]; then
            echo "$pod"
            return 0
        fi
    done

    pod=$($KUBECTL get pods -n "$NAMESPACE" -o name 2>/dev/null | grep -E 'toolset|broker' | head -n1 | cut -d/ -f2 || true)
    if [[ -n "$pod" ]]; then
        echo "$pod"
        return 0
    fi

    return 1
}

echo "--- 1. Locating Pulsar Toolset Pod ---"
# Wait for a pod that can run pulsar-admin (prefer toolset, fallback broker)
echo "Waiting for Pulsar admin-capable pod in $NAMESPACE (timeout=${WAIT_SECONDS}s)..."
TOOLSET_POD=""
elapsed=0
while [[ "$elapsed" -lt "$WAIT_SECONDS" ]]; do
    TOOLSET_POD="$(find_pulsar_admin_pod || true)"
    if [[ -n "$TOOLSET_POD" ]]; then
        break
    fi
    echo "Pulsar admin pod not found yet. Sleeping ${POLL_SECONDS}s..."
    sleep "$POLL_SECONDS"
    elapsed=$((elapsed + POLL_SECONDS))
done

if [[ -z "$TOOLSET_POD" ]]; then
    echo "ERROR: Could not find a toolset/broker pod in namespace $NAMESPACE after ${WAIT_SECONDS}s"
    echo "Current Pulsar pods:"
    $KUBECTL get pods -n "$NAMESPACE" -o wide || true
    echo "Recent events:"
    $KUBECTL get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 60 || true
    exit 1
fi

echo "Using Pulsar admin pod: $TOOLSET_POD"
$KUBECTL wait --for=condition=Ready "pod/$TOOLSET_POD" -n "$NAMESPACE" --timeout=300s

pulsar_admin() {
    $KUBECTL exec -n "$NAMESPACE" "$TOOLSET_POD" -- /pulsar/bin/pulsar-admin "$@"
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
