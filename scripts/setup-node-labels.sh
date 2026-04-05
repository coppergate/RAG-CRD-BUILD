#!/bin/bash
# scripts/setup-node-labels.sh
# Ensure cluster nodes have the correct roles (storage, inference, etc.)
# Idempotent using journal-helper.sh

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"

source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

if ! is_step_done "node-labels-applied"; then
    echo "--- Applying Node Labels ---"
    
    # 1. Role: storage-node (All nodes starting with 'worker')
    WORKER_NODES=$($KUBECTL get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^worker' || echo "")
    if [[ -n "$WORKER_NODES" ]]; then
        for node in $WORKER_NODES; do
            echo "  - Labeling $node as role=storage-node..."
            $KUBECTL label node "$node" role=storage-node --overwrite
        done
    fi

    # 2. Role: inference-node (All nodes starting with 'inference')
    INFERENCE_NODES=$($KUBECTL get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^inference' || echo "")
    if [[ -n "$INFERENCE_NODES" ]]; then
        for node in $INFERENCE_NODES; do
            echo "  - Labeling $node as role=inference-node..."
            $KUBECTL label node "$node" role=inference-node --overwrite
        done
    fi

    mark_step_done "node-labels-applied"
    echo "Node labeling complete."
fi
