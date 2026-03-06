#!/bin/bash
## setup-complete.sh - Master Orchestration Script
## To be executed on host: hierophant
## Usage: FRESH_INSTALL=true [FORCE_REINIT=true] [REPO_DIR=<path>] ./setup-complete.sh
## Purpose: 
#     End-to-end bootstrap: 
#       basic infra (Rook-Ceph/Traefik), 
#       APM (LGTM+Alloy), 
#       NVIDIA stack, 
#       local registry, 
#       build+push RAG images, 
#       deploy RAG stack; 
#       resumable via scripts/journal-helper.sh.
## Config (optional): 
# FRESH_INSTALL=true -> clean from-scratch where supported; 
# FORCE_REINIT=true -> force Pulsar BookKeeper rejoin; 
# REPO_DIR -> override RAG stack path; 
# set NO_PROXY to include cluster CIDRs and .hierocracy.home; 
# child scripts default to KUBECTL=/home/k8s/kube/kubectl and KUBECONFIG=/home/k8s/kube/config/kubeconfig.
#

set -Eeuo pipefail
#
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export BASE_DIR
VERSION="${VERSION:-1.5.7}"
export VERSION

# Tools & context (explicit paths per guidelines)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
TALOSCTL="/home/k8s/talos/talosctl"
export TALOSCONFIG="/home/k8s/talos/config/talosconfig"

source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

echo "--- 0. Verifying Cluster Registry Trust ---"
# Check if registry mirrors are configured on nodes. If not, patch and reboot.
# This ensures that Step 1.6 (Cluster-Native Builds) and Step 2 (Deployment) can pull images.
if ! is_step_done "registry-trust-verified"; then
    if [[ "${FRESH_INSTALL:-false}" == "true" ]]; then
        echo "FRESH_INSTALL detected. Skipping pre-check; registry trust will be applied in Step 1.5."
    else
        echo "Checking registry configuration on nodes..."
        # Heuristic: Check if '172.20.1.26:5000' is in the mirrors of the first node
        FIRST_NODE=$($KUBECTL get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' --request-timeout=5s 2>/dev/null || echo "")
        
        NEEDS_PATCH=false
        if [[ -n "$FIRST_NODE" ]]; then
            # Check mirrors using talosctl. We use the LB IP as the primary indicator.
            if ! $TALOSCTL -n "$FIRST_NODE" get machineconfig -o yaml 2>/dev/null | grep -q "172.20.1.26:5000"; then
                NEEDS_PATCH=true
            fi
        else
            echo "Cluster nodes not reachable. Assuming fresh install or bootstrap in progress."
        fi

        if [[ "$NEEDS_PATCH" == "true" ]]; then
            echo "Registry trust missing or outdated on nodes. Applying fast-track patch and reboot..."
            # Apply the YAML patch to all nodes (uses infrastructure/registry/apply-patch.sh)
            # This is safe to run before resources are deployed.
            bash "$BASE_DIR/infrastructure/registry/apply-patch.sh"
            
            # Perform a simple serial reboot of all nodes
            # We skip drain/ceph checks here for simplicity at the start of setup
            IPS=$($TALOSCTL config info --output jsonpath='{.nodes[*]}' 2>/dev/null || echo "")
            for ip in $IPS; do
                echo "  - Rebooting node $ip..."
                $TALOSCTL -n "$ip" reboot --wait --timeout=600s
            done
            echo "Registry trust applied and nodes rebooted."
        else
            [[ -n "$FIRST_NODE" ]] && echo "Registry trust verified."
        fi
    fi
    mark_step_done "registry-trust-verified"
fi

echo "--- 0.5. Labeling Worker Nodes ---"
if ! is_step_done "worker-labeling"; then
    echo "Labeling nodes starting with 'worker' as 'role=storage-node'..."
    # Get all node names starting with worker
    WORKER_NODES=$($KUBECTL get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^worker' || echo "")
    
    if [[ -n "$WORKER_NODES" ]]; then
        for node in $WORKER_NODES; do
            echo "  - Labeling $node..."
            $KUBECTL label node "$node" role=storage-node --overwrite
        done
        echo "Worker nodes labeled successfully."
    else
        echo "No nodes matching 'worker*' found. Skipping labeling."
    fi
    mark_step_done "worker-labeling"
fi

echo "===================================================="
echo "Starting Complete Kubernetes Build and RAG Stack"
echo "Target service image version: $VERSION"
echo "===================================================="

if ! is_step_done "basic"; then
echo ""
echo "Step 1: Basic Infrastructure Setup (includes Rook-Ceph)"
echo "----------------------------------------------------"
$BASE_DIR/setup-01-basic.sh
mark_step_done "basic"
fi

if ! is_step_done "apm"; then
echo ""
echo "Step 1.2: APM (LGTM + Grafana Alloy)"
echo "----------------------------------------------------"
bash $BASE_DIR/infrastructure/APM/install.sh
mark_step_done "apm"
fi

if ! is_step_done "nvidia"; then
echo ""
echo "Step 1.4: NVIDIA Infrastructure Setup"
echo "----------------------------------------------------"
# Deploy NVIDIA device plugin and runtime class
bash $BASE_DIR/infrastructure/nvidia-operator.sh
mark_step_done "nvidia"
fi

if ! is_step_done "registry"; then
echo ""
echo "Step 1.5: Local Registry Setup"
echo "----------------------------------------------------"
$BASE_DIR/infrastructure/registry/install.sh
mark_step_done "registry"
fi

if ! is_step_done "kubernetes-dashboard"; then
echo ""
echo "Step 1.5.5: Kubernetes Dashboard Setup"
echo "----------------------------------------------------"
bash $BASE_DIR/infrastructure/kubernetes-dashboard/dashboard.sh
mark_step_done "kubernetes-dashboard"
fi

if ! is_step_done "pulsar"; then
echo ""
echo "Step 1.5.7: Apache Pulsar Infrastructure"
echo "----------------------------------------------------"
# REPO_DIR is needed for pulsar scripts
export REPO_DIR="$BASE_DIR/rag-stack"
bash $BASE_DIR/rag-stack/infrastructure/pulsar/install.sh
mark_step_done "pulsar"
fi

if ! is_step_done "pulsar-init"; then
echo ""
echo "Step 1.5.7.1: Pulsar Initialization"
echo "----------------------------------------------------"
bash $BASE_DIR/rag-stack/infrastructure/pulsar/init-rag-pulsar.sh
mark_step_done "pulsar-init"
fi

if ! is_step_done "build-pipeline-infra"; then
echo ""
echo "Step 1.5.8: Build Pipeline Infrastructure (Kaniko + S3)"
echo "----------------------------------------------------"
bash $BASE_DIR/rag-stack/infrastructure/build-pipeline/install.sh
mark_step_done "build-pipeline-infra"
fi

if ! is_step_done "rag-images"; then
echo ""
echo "Step 1.6: Build and Push RAG Images (Cluster-Native)"
echo "----------------------------------------------------"
# Use the new cluster-native build pipeline (Kaniko + S3 + Pulsar)
# This prevents host resource exhaustion during builds
# We wait for completion here to ensure Step 2 has the images it needs.
    VERSION="$VERSION" bash $BASE_DIR/rag-stack/build-all-on-cluster.sh --wait
mark_step_done "rag-images"
fi

if ! is_step_done "rag-stack"; then
echo ""
echo "Step 2: RAG Stack Deployment"
echo "----------------------------------------------------"
# We can either call setup-all.sh or we can un-comment the infra parts in it if needed.
# Since setup-01-basic.sh already handles Rook/Traefik, we only need the RAG services.

# Ensure REPO_DIR is set for the RAG stack
export REPO_DIR="$BASE_DIR/rag-stack"
    VERSION="$VERSION" $REPO_DIR/setup-all.sh
mark_step_done "rag-stack"
fi

clear_journal

echo ""
echo "===================================================="
echo "Complete Build Finished Successfully"
echo "===================================================="
