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
VERSION_FILE="$BASE_DIR/CURRENT_VERSION"
if [[ -z "${VERSION:-}" ]]; then
    if [[ -f "$VERSION_FILE" ]]; then
        if jq . "$VERSION_FILE" >/dev/null 2>&1; then
            # Use a default version if we need a global one for tools
            VERSION="2.4.11"
        else
            VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
        fi
    else
        VERSION="2.4.11"
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

# Pre-authenticate sudo upfront so system-wide cert/trust steps don't silently
# skip due to missing credentials. Keeps the session alive for the full run.
if ! sudo -n true 2>/dev/null; then
    echo "This script requires sudo for system certificate installation."
    echo "Please enter your sudo password:"
    sudo -v
fi
# Keepalive: refresh sudo credentials every 50s in the background
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done & )

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

# Ceph readiness is now guaranteed inside the 'rook-ceph-cluster' step in
# setup-01-basic.sh — it blocks until HEALTH_OK/WARN and CSI pods are running
# before marking the step done. No separate gate needed here.

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

if ! is_step_done "apm-stabilize"; then
echo ""
echo "Step 1.2.1: APM stabilization wait (60s)"
echo "----------------------------------------------------"
# APM launches Mimir, Loki, Tempo, Grafana, and Alloy DaemonSet pods simultaneously.
# Each creates CRDs, Secrets, ConfigMaps, leader-election Leases, and readiness probes
# — all hitting the API server at once. Wait for the monitoring namespace to settle
# before starting Pulsar (which brings its own ZK/bookie/broker/proxy startup storm).
sleep 60
mark_step_done "apm-stabilize"
fi

# NOTE: NVIDIA GPU operator is intentionally deferred to the end of the install.
# The V100's PCIe initialization generates device resets and bus transactions that
# cause hypervisor I/O latency spikes during KVM VM scheduling, which destabilizes
# the Kubernetes control plane (etcd slow ops → controller lease timeouts → crash loops).
# GPU resources are NOT needed until inference workloads start. Set SKIP_GPU=true to
# skip GPU setup entirely (useful for cluster rebuilds and CI environments).
# The step is journaled as "nvidia" so it can be resumed independently.

if ! is_step_done "pulsar"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.5.8: Apache Pulsar Infrastructure"
echo "----------------------------------------------------"
# Ceph health was already gated in setup-01-basic.sh (rook-ceph-cluster step). Verify OSDs still stable.
# Additional check: verify all OSDs are running (use jsonpath — avoids fragile container-count string matching)
OSD_TOTAL=$($KUBECTL -n rook-ceph get pods -l app=rook-ceph-osd \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c . || echo 0)
OSD_READY=$($KUBECTL -n rook-ceph get pods -l app=rook-ceph-osd \
    --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.ready}{"\n"}{end}{end}' 2>/dev/null \
    | grep -c "^true$" || echo 0)
echo "OSD status: ${OSD_READY} containers ready across ${OSD_TOTAL} OSD pods"
if (( OSD_READY < OSD_TOTAL )); then
    echo "WARNING: Not all OSDs are ready. Waiting 60s for stragglers..."
    sleep 60
fi
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

if ! is_step_done "cnpg-operator"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.5.8.2: CloudNativePG Operator"
echo "----------------------------------------------------"
CNPG_MANIFEST="$BASE_DIR/rag-stack/infrastructure/timescaledb/cnpg-1.25.0.yaml"
$KUBECTL get namespace cnpg-system >/dev/null 2>&1 || $KUBECTL create namespace cnpg-system
$KUBECTL apply -f "$CNPG_MANIFEST" --server-side --force-conflicts
echo "Waiting for CNPG namespace..."
for _ in $(seq 1 60); do
  if $KUBECTL get namespace cnpg-system >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
CNPG_DEPLOYMENT="cnpg-controller-manager"
CNPG_TIMEOUT=300
CNPG_START_TS=$(date +%s)
until $KUBECTL -n cnpg-system get deployment "$CNPG_DEPLOYMENT" >/dev/null 2>&1; do
  discovered=$($KUBECTL -n cnpg-system get deployment -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$discovered" ]]; then
    CNPG_DEPLOYMENT="$discovered"
    break
  fi
  if (( $(date +%s) - CNPG_START_TS > CNPG_TIMEOUT )); then
    echo "[ERROR] Timeout waiting for CNPG deployment to be created in cnpg-system" >&2
    $KUBECTL -n cnpg-system get deployment || true
    exit 1
  fi
  sleep 5
done
echo "Waiting for CNPG deployment: $CNPG_DEPLOYMENT"
$KUBECTL -n cnpg-system rollout status deployment/"$CNPG_DEPLOYMENT" --timeout=600s
mark_step_done "cnpg-operator"
STEP_TS_END=$(date +%s)
log_step_timing "cnpg-operator" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "timescaledb"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.5.8.3: TimescaleDB Infrastructure"
echo "----------------------------------------------------"
export REPO_DIR="$BASE_DIR/rag-stack"
bash "$REPO_DIR/infrastructure/timescaledb/install.sh"
$KUBECTL apply -f "$REPO_DIR/infrastructure/timescaledb/timescaledb-lb-service.yaml"
mark_step_done "timescaledb"
STEP_TS_END=$(date +%s)
log_step_timing "timescaledb" "$STEP_TS_START" "$STEP_TS_END" "ok"
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

if ! is_step_done "pre-build-stabilize"; then
echo ""
echo "Step 1.5.9: Pre-build stabilization wait (90s)"
echo "----------------------------------------------------"
# Pulsar, TimescaleDB, Qdrant, and the build-pipeline pods all start in the preceding
# steps. Give the API server, etcd, and the newly-started pods 90s to settle before
# launching Kaniko builds. Kaniko jobs + kubectl exec S3 uploads are the heaviest
# API server load in the whole install — starting them too early causes i/o timeouts.
sleep 90
mark_step_done "pre-build-stabilize"
fi

if ! is_step_done "rag-images"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.6: Build and Push RAG Images (Cluster-Native)"
echo "----------------------------------------------------"
# Use the new cluster-native build pipeline (Kaniko + S3 + Pulsar)
# This prevents host resource exhaustion during builds
# We wait for completion here to ensure Step 2 has the images it needs.
# PARALLELISM=2: limit concurrent Kaniko builds to reduce API server load.
# Default of 4 concurrent builds + kubectl exec streams overwhelms the API server
# when Pulsar/APM are still settling. Two at a time is sufficient for 11 services.
    PARALLELISM=2 bash "$BASE_DIR/rag-stack/build.sh" --mode cluster --wait
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

if [[ "${SKIP_GPU:-false}" != "true" ]]; then
  if ! is_step_done "nvidia"; then
    STEP_TS_START=$(date +%s)
    echo ""
    echo "Step 3: NVIDIA GPU Operator (deferred — runs after full RAG stack)"
    echo "----------------------------------------------------"
    bash $BASE_DIR/infrastructure/nvidia-operator.sh
    mark_step_done "nvidia"
    STEP_TS_END=$(date +%s)
    log_step_timing "nvidia" "$STEP_TS_START" "$STEP_TS_END" "ok"
  fi
else
  echo "SKIP_GPU=true — skipping GPU operator install (run nvidia-operator.sh manually when ready)"
fi

clear_journal

echo ""
echo "===================================================="
echo "Complete Build Finished Successfully"
echo "===================================================="
