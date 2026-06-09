#!/bin/bash
set -e

# Configuration
NAMESPACE="rag-system"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
VERSION="${VERSION:-2.0.4}"

MODEL_LLAMA="llama3.1:latest"
MODEL_GRANITE="granite3.1-dense:8b"
MODEL_CPU="llama3.2:3b"

# 2 embedding models × 4 heterogeneous planner/executor pairs = 8 scenarios
declare -a EMBEDDING_MODELS=("all-minilm:l6-v2" "nomic-embed-text")
declare -A VECTOR_SIZES=(["all-minilm:l6-v2"]="384" ["nomic-embed-text"]="768")

run_scenario() {
    local embed=$1
    local p_model=$2
    local e_model=$3
    local vsize="${VECTOR_SIZES[$embed]}"
    echo "========================================================================"
    echo " SCENARIO: Embedding=$embed | Planner=$p_model | Executor=$e_model"
    echo "========================================================================"

    echo "Updating rag-worker deployment..."
    $KUBECTL set env deployment/rag-worker -n $NAMESPACE \
        PLANNER_MODEL="$p_model" \
        EXECUTOR_MODEL="$e_model" \
        EMBEDDING_MODEL="$embed" \
        VECTOR_SIZE="$vsize"

    echo "Waiting for rollout..."
    $KUBECTL rollout status deployment/rag-worker -n $NAMESPACE --timeout=300s

    echo "Running integration tests..."
    PLANNER_MODEL="$p_model" EXECUTOR_MODEL="$e_model" \
    EMBEDDING_MODEL="$embed" VECTOR_SIZE="$vsize" \
        VERSION=$VERSION bash ./run-tests.sh

    echo "Verifying test job result..."
    $KUBECTL wait --for=condition=complete job/rag-integration-test -n $NAMESPACE --timeout=600s
}

echo "--- Starting Cross-Model Verification (8 scenarios) ---"

for EMBED in "${EMBEDDING_MODELS[@]}"; do
    run_scenario "$EMBED" "$MODEL_LLAMA"   "$MODEL_GRANITE"
    run_scenario "$EMBED" "$MODEL_GRANITE" "$MODEL_LLAMA"
    run_scenario "$EMBED" "$MODEL_CPU"     "$MODEL_LLAMA"
    run_scenario "$EMBED" "$MODEL_CPU"     "$MODEL_GRANITE"
done

echo "========================================================================"
echo " CROSS-MODEL VERIFICATION COMPLETE"
echo "========================================================================"
