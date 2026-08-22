#!/bin/bash
# scripts/setup-node-labels.sh
# Ensure cluster nodes have the correct roles (storage, inference, etc.)
# Always runs unconditionally — kubectl label --overwrite is idempotent and
# nodes may join the cluster after an earlier partial run marked the step done.

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"

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

echo "Node labeling complete."

# 3. Taint: reserve inference nodes for GPU work only.
#
# nodeSelector alone is opt-in — it steers pods that ask for a node but does not
# stop a manifest that forgets 'role: storage-node' from consuming GPU-node
# capacity. The taint turns that convention into a guarantee.
#
# Key choice matters: the NVIDIA GPU operator chart tolerates 'nvidia.com/gpu' in
# its daemonsets.tolerations default, so device-plugin / GFD / DCGM-exporter /
# node-status-exporter / container-toolkit / operator-validator keep scheduling
# with no change to kubernetes-setup/new-setup-external-gpu.
#
# NoSchedule (not NoExecute): NoExecute would evict already-running pods that
# lack the toleration, with no benefit here.
#
# Anything that legitimately needs to run on an inference node must tolerate
# this. Already handled in-repo:
#   - Ceph CSI nodeplugin  — OperatorConfig CR applied by setup-01-basic.sh
#                            (REQUIRED: GPU Ollama pods mount a rook-cephfs PVC)
#   - Grafana Alloy        — infrastructure/APM/alloy/values.yaml
#                            (REQUIRED: otherwise DCGM metrics are silently lost)
#   - GPU Ollama pods      — rag-stack/infrastructure/ollama/values*.yaml
#
# Applied AFTER labeling so a partial run never leaves a tainted node without its
# role= label. Idempotent: --overwrite updates the value if the taint exists.
if [[ -n "$INFERENCE_NODES" ]]; then
    for node in $INFERENCE_NODES; do
        echo "  - Tainting $node with nvidia.com/gpu=present:NoSchedule..."
        $KUBECTL taint node "$node" nvidia.com/gpu=present:NoSchedule --overwrite
    done
    echo "Node tainting complete."
fi
