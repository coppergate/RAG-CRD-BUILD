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

# 3. Node size class: hierocracy.home/node-size on worker nodes.
#
# The worker pool is deliberately ASYMMETRIC (see OPERATIONS.md 1.10):
#   worker-0..2   28 GiB /  8 vCPU
#   worker-3      64 GiB / 14 vCPU
# The label exists so memory-resident services (Qdrant above all) can be
# steered to the node that can actually hold them, instead of landing on a
# 28 GiB node by scheduler lottery.
#
# DERIVED from live .status.capacity.memory, not hardcoded to worker-3, and
# deliberately NOT set in the Talos machine config. Same reasoning as the GPU
# UUID labels: capacity is a discovered fact, and Talos re-asserts whatever its
# config says on every apply — so a resized VM would keep a stale size class
# forever. Resize the VM, re-run this script, the label follows.
#
# Threshold rather than "largest node wins": relative ranking would flip the
# label when a node goes NotReady, and would silently promote a small node if
# the big one were removed. A fixed boundary is predictable and auditable.
# Override with NODE_SIZE_LARGE_GIB when the pool changes shape.
NODE_SIZE_LARGE_GIB="${NODE_SIZE_LARGE_GIB:-48}"

if [[ -n "$WORKER_NODES" ]]; then
    echo "--- Applying node size class (large >= ${NODE_SIZE_LARGE_GIB} GiB) ---"
    for node in $WORKER_NODES; do
        # capacity.memory is a Ki quantity, e.g. "65787276Ki"
        mem_ki=$($KUBECTL get node "$node" \
            -o jsonpath='{.status.capacity.memory}' 2>/dev/null | tr -d 'Ki') || mem_ki=""
        if [[ -z "$mem_ki" || ! "$mem_ki" =~ ^[0-9]+$ ]]; then
            echo "  - WARNING: $node reported no usable capacity.memory — skipping size class" >&2
            continue
        fi
        mem_gib=$(( mem_ki / 1048576 ))

        if (( mem_gib >= NODE_SIZE_LARGE_GIB )); then
            size="large"
        else
            size="standard"
        fi

        echo "  - $node: ${mem_gib} GiB -> node-size=${size}"
        $KUBECTL label node "$node" \
            "hierocracy.home/node-size=${size}" \
            "hierocracy.home/node-memory-gib=${mem_gib}" --overwrite
    done

    # Fail loudly if nothing qualified. A manifest that selects node-size=large
    # would otherwise sit Pending with no clue why.
    if ! $KUBECTL get nodes -l hierocracy.home/node-size=large \
            -o name 2>/dev/null | grep -q .; then
        echo "  - WARNING: no worker qualified as node-size=large." >&2
        echo "    Anything with nodeSelector hierocracy.home/node-size=large will stay Pending." >&2
        echo "    Check worker RAM, or lower NODE_SIZE_LARGE_GIB (currently ${NODE_SIZE_LARGE_GIB})." >&2
    fi
fi

echo "Node labeling complete."

# 4. Taint: reserve inference nodes for GPU work only.
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
