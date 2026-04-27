#!/bin/bash
set -e

# Configuration
NAMESPACE="rag-system"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
VERSION="${VERSION:-2.0.4}"

MODEL_LLAMA="llama3.1:latest"
MODEL_GRANITE="granite3.1-dense:8b"

run_scenario() {
    local p_model=$1
    local e_model=$2
    echo "========================================================================"
    echo " SCENARIO: Planner=$p_model | Executor=$e_model"
    echo "========================================================================"

    echo "Updating rag-worker deployment..."
    $KUBECTL set env deployment/rag-worker -n $NAMESPACE \
        PLANNER_MODEL="$p_model" \
        EXECUTOR_MODEL="$e_model"

    echo "Waiting for rollout..."
    $KUBECTL rollout status deployment/rag-worker -n $NAMESPACE --timeout=300s

    echo "Running integration tests..."
    # We use bash ./run-tests.sh which already handles ConfigMap and Job
    VERSION=$VERSION bash ./run-tests.sh

    # Check if the job succeeded
    echo "Verifying test job result..."
    # The run-tests.sh follows logs, but we need to check the final status
    # Wait for completion again just to be sure and check exit code
    $KUBECTL wait --for=condition=complete job/rag-integration-test -n $NAMESPACE --timeout=600s
}

echo "--- Starting Cross-Model Verification ---"

# Scenario A: Llama (Planner) + Granite (Executor)
run_scenario "$MODEL_LLAMA" "$MODEL_GRANITE"

# Scenario B: Granite (Planner) + Llama (Executor)
run_scenario "$MODEL_GRANITE" "$MODEL_LLAMA"

echo "========================================================================"
echo " CROSS-MODEL VERIFICATION COMPLETE"
echo "========================================================================"
