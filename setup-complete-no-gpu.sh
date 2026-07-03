#!/bin/bash
## setup-complete-no-gpu.sh - Master Orchestration Script (No GPU)
## To be executed on host: hierophant
## Usage: FRESH_INSTALL=true [FORCE_REINIT=true] [REPO_DIR=<path>] ./setup-complete-no-gpu.sh
## Purpose:
#     End-to-end bootstrap WITHOUT GPU/inference components:
#       basic infra (Rook-Ceph/Traefik),
#       APM (LGTM+Alloy),
#       local registry,
#       build+push RAG images,
#       deploy RAG stack (no Ollama);
#       resumable via scripts/journal-helper.sh.
#
# Omitted vs setup-complete.sh:
#   - llm-models-pre-populate (no inference PVCs to seed)
#   - ollama image group excluded from image prefetch
#   - NVIDIA GPU operator step
#   - setup-all.sh replaced with setup-all-no-gpu.sh
#
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
# Exclude 'ollama' — inference nodes are not present in no-gpu installs
IMAGE_PREFETCH_GROUPS="${IMAGE_PREFETCH_GROUPS:-bootstrap,storage,apm-core,pulsar-core,registry,data-services,helm-runtime}"
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

INSTALL_TIMING_LOG="${INSTALL_TIMING_LOG:-$JOURNAL_FILE_DIR/setup-complete-no-gpu-timing.log}"
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
    echo "$line" >> "$JOURNAL_FILE"
}

# wait_namespace_stable <namespace> <timeout_seconds>
# Polls until every non-Job pod in the namespace is Running or Succeeded/Completed.
# Exits 0 once stable; warns and exits 0 on timeout (non-fatal — some pods may be optional).
wait_namespace_stable() {
    local ns="$1"
    local timeout="${2:-300}"
    local interval=15
    local elapsed=0
    echo "Waiting for namespace '$ns' to stabilize (timeout: ${timeout}s)..."
    while (( elapsed < timeout )); do
        local not_ready
        not_ready=$($KUBECTL get pods -n "$ns" --no-headers \
            --request-timeout=15s 2>/dev/null \
            | grep -cvE '^\S+\s+\S+\s+(Running|Completed|Succeeded)' || true)
        local total
        total=$($KUBECTL get pods -n "$ns" --no-headers \
            --request-timeout=15s 2>/dev/null | wc -l || true)
        if (( total > 0 && not_ready == 0 )); then
            echo "  Namespace '$ns' stable: $total pods Running/Completed (${elapsed}s)."
            return 0
        fi
        echo "  Namespace '$ns': ${not_ready}/${total} pods not yet ready — waiting ${interval}s... (${elapsed}s/${timeout}s)"
        sleep "$interval"
        (( elapsed += interval )) || true
    done
    echo "WARNING: Namespace '$ns' did not fully stabilize after ${timeout}s — proceeding anyway."
    $KUBECTL get pods -n "$ns" --no-headers --request-timeout=15s 2>/dev/null || true
}

echo "--- 0. Verifying Cluster Registry Trust ---"
if ! is_step_done "registry-trust-verified"; then
    STEP_TS_START=$(date +%s)
    if [[ "${FRESH_INSTALL:-false}" == "true" ]]; then
        echo "FRESH_INSTALL detected. Skipping pre-check; registry trust will be applied in Step 1.5."
    else
        echo "Checking registry configuration on nodes..."
        FIRST_NODE=$($KUBECTL get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' --request-timeout=5s 2>/dev/null || echo "")

        NEEDS_PATCH=false
        if [[ -n "$FIRST_NODE" ]]; then
            if ! $TALOSCTL -n "$FIRST_NODE" get machineconfig -o yaml 2>/dev/null | grep -q "registry.hierocracy.home:5000"; then
                NEEDS_PATCH=true
            fi
        else
            echo "Cluster nodes not reachable. Assuming fresh install or bootstrap in progress."
        fi

        if [[ "$NEEDS_PATCH" == "true" ]]; then
            echo "Registry trust missing or outdated on nodes. Applying fast-track patch and reboot..."
            bash "$BASE_DIR/infrastructure/registry/apply-patch.sh"

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
echo "Starting Complete Kubernetes Build and RAG Stack (No GPU)"
echo "Target service image version: $VERSION"
echo "===================================================="

if ! is_step_done "basic"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1: Basic Infrastructure Setup (includes Rook-Ceph)"
echo "----------------------------------------------------"
# Point wipe-disks.sh at the no-GPU disk layout (worker-0/3: vdb/vdc/vdd; worker-1/2: vdb/vdc).
# The full setup uses vdb-vdf on worker-0 which don't exist in the no-GPU VM layout.
export WIPE_DISKS_YAML="$BASE_DIR/infrastructure/rook-ceph/wipe-disks-no-gpu.yaml"
export WIPE_DISKS_JOB_SELECTOR="app=wipe-disks-no-gpu"
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

# Step 1.1.2 (llm-models-pre-populate) is intentionally omitted:
# No inference nodes are present — there are no Ollama PVCs to seed models into.

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
echo "Step 1.2.1: Wait for APM namespace to stabilize"
echo "----------------------------------------------------"
wait_namespace_stable "monitoring" 300
mark_step_done "apm-stabilize"
fi

if ! is_step_done "pulsar"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.5.8: Apache Pulsar Infrastructure"
echo "----------------------------------------------------"
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
echo "Step 1.5.9: Wait for all infrastructure namespaces to stabilize"
echo "----------------------------------------------------"
wait_namespace_stable "apache-pulsar"    600
wait_namespace_stable "monitoring"       300
wait_namespace_stable "build-pipeline"   180
wait_namespace_stable "timescaledb"      300
mark_step_done "pre-build-stabilize"
fi

if ! is_step_done "rag-images"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 1.6: Build and Push RAG Images (Cluster-Native)"
echo "----------------------------------------------------"
bash "$BASE_DIR/rag-stack/build.sh" --mode cluster --wait
mark_step_done "rag-images"
STEP_TS_END=$(date +%s)
log_step_timing "rag-images" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

if ! is_step_done "rag-stack"; then
STEP_TS_START=$(date +%s)
echo ""
echo "Step 2: RAG Stack Deployment (no GPU)"
echo "----------------------------------------------------"
export REPO_DIR="$BASE_DIR/rag-stack"
    VERSION="$VERSION" $REPO_DIR/setup-all-no-gpu.sh
mark_step_done "rag-stack"
STEP_TS_END=$(date +%s)
log_step_timing "rag-stack" "$STEP_TS_START" "$STEP_TS_END" "ok"
fi

# NVIDIA GPU operator step intentionally omitted — no inference nodes present.

clear_journal

echo ""
echo "===================================================="
echo "Complete Build (No GPU) Finished Successfully"
echo "===================================================="
