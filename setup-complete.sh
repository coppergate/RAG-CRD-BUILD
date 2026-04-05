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

# Source of truth for versioning
if [[ -z "${VERSION:-}" ]]; then
    if [[ -f "$BASE_DIR/CURRENT_VERSION" ]]; then
        VERSION=$(cat "$BASE_DIR/CURRENT_VERSION" | tr -d '[:space:]')
    else
        VERSION="2.4.9"
    fi
fi
export VERSION
IMAGE_PREFETCH_ON_START="${IMAGE_PREFETCH_ON_START:-true}"
IMAGE_PREFETCH_GROUPS="${IMAGE_PREFETCH_GROUPS:-bootstrap,storage,apm-core,pulsar-core,registry,data-services,ollama}"
IMAGE_PREFETCH_PARALLELISM="${IMAGE_PREFETCH_PARALLELISM:-3}"

# Tools & context (explicit paths per guidelines)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
TALOSCTL="/home/k8s/talos/talosctl"
export TALOSCONFIG="/home/k8s/talos/config/talosconfig"

source "$BASE_DIR/scripts/journal-helper.sh"

# On full fresh installs, clear all nested journals first (including sub-journals
# used by child scripts such as Pulsar's ~/.complete-build/journal/pulsar/*.done).
if [[ "${FRESH_INSTALL:-false}" == "true" ]]; then
    clear_all_journals
fi

init_journal

INSTALL_TIMING_LOG="${INSTALL_TIMING_LOG:-$JOURNAL_FILE_DIR/setup-complete-timing.log}"
touch "$INSTALL_TIMING_LOG"
chmod 600 "$INSTALL_TIMING_LOG" 2>/dev/null || true

log_step_timing() {
    local step_name="$1"
    local start_epoch="$2"
    local end_epoch="$3"
    local status="${4:-ok}"
    local duration=$((end_epoch - start_epoch))
    local start_iso end_iso line
    start_iso="$(date -u -d "@$start_epoch" +'%Y-%m-%dT%H:%M:%SZ')"
    end_iso="$(date -u -d "@$end_epoch" +'%Y-%m-%dT%H:%M:%SZ')"
    line="timing|step=${step_name}|status=${status}|start=${start_iso}|end=${end_iso}|duration_seconds=${duration}"
    echo "$line" | tee -a "$INSTALL_TIMING_LOG" >/dev/null
    # Append timing marker to the journal file as requested, while keeping is_step_done matching intact.
    echo "$line" >> "$JOURNAL_FILE"
}

echo "--- 0. Verifying Cluster Registry Trust ---"
# Check if registry mirrors are configured on nodes. If not, patch and reboot.
# This ensures that Step 1.6 (Cluster-Native Builds) and Step 2 (Deployment) can pull images.
if ! is_step_done "registry-trust-verified"; then
    STEP_TS_START=$(date +%s)
    if [[ "${FRESH_INSTALL:-false}" == "true" ]]; then
        echo "FRESH_INSTALL detected. Skipping pre-check; registry trust will be applied in Step 1.5."
    else
        echo "Checking registry configuration on nodes..."
        # Heuristic: Check if 'registry.hierocracy.home:5000' is in the mirrors of the first node
        FIRST_NODE=$($KUBECTL get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' --request-timeout=5s 2>/dev/null || echo "")
        
        NEEDS_PATCH=false
        if [[ -n "$FIRST_NODE" ]]; then
            # Check mirrors using talosctl. We use the LB IP as the primary indicator.
            if ! $TALOSCTL -n "$FIRST_NODE" get machineconfig -o yaml 2>/dev/null | grep -q "registry.hierocracy.home:5000"; then
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
    STEP_TS_END=$(date +%s)
    log_step_timing "registry-trust-verified" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

echo "--- 0.5. Node Labeling (Idempotent) ---"
bash "$BASE_DIR/scripts/setup-node-labels.sh"

echo "===================================================="
echo "Starting Complete Kubernetes Build and RAG Stack"
echo "Target service image version: $VERSION"
echo "===================================================="

if ! is_step_done "basic"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1: Basic Infrastructure Setup (includes Rook-Ceph)"
echo "----------------------------------------------------"
$BASE_DIR/setup-01-basic.sh
mark_step_done "basic"
STEP_TS_END=$(date +%s)
log_step_timing "basic" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "headlamp"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.1: Headlamp Setup (Replacing Kubernetes Dashboard)"
echo "----------------------------------------------------"
if [[ -d "$BASE_DIR/infrastructure/kubernetes-dashboard" ]]; then
    # Try to uninstall if the directory still exists
    bash $BASE_DIR/infrastructure/headlamp/uninstall-old-dashboard.sh || true
fi
bash $BASE_DIR/infrastructure/headlamp/headlamp.sh
mark_step_done "headlamp"
mark_step_done "kubernetes-dashboard"
STEP_TS_END=$(date +%s)
log_step_timing "headlamp" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

# Step 1.5 moved to setup-01-basic.sh
if ! is_step_done "registry" || ! $KUBECTL get namespace container-registry >/dev/null 2>&1; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.1.1: Local Registry Setup (Ensuring Ready)"
echo "----------------------------------------------------"
$BASE_DIR/infrastructure/registry/install.sh
mark_step_done "registry"
STEP_TS_END=$(date +%s)
log_step_timing "registry" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "llm-models-pre-populate"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.1.2: LLM Model Pre-population into Local Registry"
echo "----------------------------------------------------"
# This ensures that Step 2 (Deployment) can seed models from the local registry
bash "$BASE_DIR/rag-stack/infrastructure/ollama/push-models-to-cluster.sh"
mark_step_done "llm-models-pre-populate"
STEP_TS_END=$(date +%s)
log_step_timing "llm-models-pre-populate" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if [[ "$IMAGE_PREFETCH_ON_START" == "true" ]] && ! is_step_done "image-prefetch-initial"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.1.3: Initial Image Prefetch to Local Registry"
echo "----------------------------------------------------"
APPLY=true MIRROR_GROUPS="$IMAGE_PREFETCH_GROUPS" PARALLELISM="$IMAGE_PREFETCH_PARALLELISM" \
  bash "$BASE_DIR/scripts/mirror-all-images.sh"
mark_step_done "image-prefetch-initial"
STEP_TS_END=$(date +%s)
log_step_timing "image-prefetch-initial" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "apm"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.2: APM (LGTM + Grafana Alloy)"
echo "----------------------------------------------------"
bash $BASE_DIR/infrastructure/APM/install.sh
mark_step_done "apm"
STEP_TS_END=$(date +%s)
log_step_timing "apm" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "nvidia"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.4: NVIDIA Infrastructure Setup"
echo "----------------------------------------------------"
# Deploy NVIDIA device plugin and runtime class
bash $BASE_DIR/infrastructure/nvidia-operator.sh
mark_step_done "nvidia"
STEP_TS_END=$(date +%s)
log_step_timing "nvidia" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "pulsar"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.5.8: Apache Pulsar Infrastructure"
echo "----------------------------------------------------"
# Verify Rook-Ceph storage is available (Pulsar PVCs depend on it)
echo "Verifying rook-ceph-block StorageClass exists..."
if ! $KUBECTL get storageclass rook-ceph-block >/dev/null 2>&1; then
    echo "ERROR: StorageClass 'rook-ceph-block' not found."
    echo "Pulsar requires Rook-Ceph storage. Ensure Step 1 (basic infra) completed successfully."
    exit 1
fi
echo "StorageClass rook-ceph-block found."
# REPO_DIR is needed for pulsar scripts
export REPO_DIR="$BASE_DIR/rag-stack"
bash $BASE_DIR/rag-stack/infrastructure/pulsar/install.sh
mark_step_done "pulsar"
STEP_TS_END=$(date +%s)
log_step_timing "pulsar" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "pulsar-init"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.5.8.1: Pulsar Initialization"
echo "----------------------------------------------------"
bash $BASE_DIR/rag-stack/infrastructure/pulsar/init-rag-pulsar.sh

# Verify tenant and namespaces were created
echo "Verifying Pulsar tenants and namespaces..."
TOOLSET_POD=$($KUBECTL get pods -n apache-pulsar -l component=toolset -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$TOOLSET_POD" ]]; then
    TENANTS=$($KUBECTL exec -n apache-pulsar "$TOOLSET_POD" -- /pulsar/bin/pulsar-admin tenants list 2>/dev/null || echo "")
    if echo "$TENANTS" | grep -q "rag-pipeline"; then
        echo "Pulsar init verified: rag-pipeline tenant exists."
    else
        echo "WARNING: rag-pipeline tenant not found after init. Tenants: $TENANTS"
    fi
else
    echo "WARNING: Could not find toolset pod to verify Pulsar init."
fi

mark_step_done "pulsar-init"
STEP_TS_END=$(date +%s)
log_step_timing "pulsar-init" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "build-pipeline-infra" || ! $KUBECTL get namespace build-pipeline >/dev/null 2>&1; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.5.8: Build Pipeline Infrastructure (Kaniko + S3)"
echo "----------------------------------------------------"
bash $BASE_DIR/rag-stack/infrastructure/build-pipeline/install.sh
mark_step_done "build-pipeline-infra"
STEP_TS_END=$(date +%s)
log_step_timing "build-pipeline-infra" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "rag-images"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.6: Build and Push RAG Images (Cluster-Native)"
echo "----------------------------------------------------"
# Use the new cluster-native build pipeline (Kaniko + S3 + Pulsar)
# This prevents host resource exhaustion during builds
# We wait for completion here to ensure Step 2 has the images it needs.
    bash "$BASE_DIR/rag-stack/build.sh" --mode cluster --wait
mark_step_done "rag-images"
STEP_TS_END=$(date +%s)
log_step_timing "rag-images" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "rag-stack"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 2: RAG Stack Deployment"
echo "----------------------------------------------------"
# We can either call setup-all.sh or we can un-comment the infra parts in it if needed.
# Since setup-01-basic.sh already handles Rook/Traefik, we only need the RAG services.

# Ensure REPO_DIR is set for the RAG stack
export REPO_DIR="$BASE_DIR/rag-stack"
    VERSION="$VERSION" $REPO_DIR/setup-all.sh
mark_step_done "rag-stack"
STEP_TS_END=$(date +%s)
log_step_timing "rag-stack" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

clear_journal

echo ""
echo "===================================================="
echo "Complete Build Finished Successfully"
echo "===================================================="
