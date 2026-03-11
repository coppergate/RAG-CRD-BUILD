#!/usr/bin/env bash
# fix-image-pulls-rolling-reboot.sh
#
# Purpose:
#   - Canonically configure Talos registry mirrors so nodes can pull images by
#     service name `registry.hierocracy.home:5000` and by LB IP.
#   - Perform a careful rolling reboot of worker nodes with cordon/drain and
#     Ceph health checks between nodes to avoid disrupting the Ceph cluster.
#   - Integrate Ceph maintenance best-practices: set `noout` before maintenance,
#     verify `ceph osd ok-to-stop` per node, and unset `noout` after.
#   - Verify image pull by launching a short-lived pod which pulls from the
#     service name.
#   - Optionally scale RAG and LLM deployments and run E2E tests (enabled by default).
#
# Execution:
#   - MUST be executed on host: hierophant
#   - Uses non-interactive kubectl/talosctl with explicit paths per guidelines
#   - Requires Krew `rook-ceph` kubectl plugin (preferred/assumed). A toolbox
#     fallback is available but disabled by default (see ALLOW_TOOLBOX_FALLBACK).
#
# Environment flags:
#   DRY_RUN=true                 # If set, prints actions without making changes
#   SKIP_SCALE=true              # If set, skip scaling deployments back up
#   SKIP_E2E=true                # If set, skip running the E2E test script
#   FRESH_INSTALL=true           # If set, journal will be cleared (see journal-helper)
#   ALLOW_TOOLBOX_FALLBACK=true  # If set, allow toolbox fallback when Krew plugin is missing
#   GPU_SAFE_MODE=true           # If set, apply GPU-safe reboot workflow for GPU nodes
#   GPU_REBOOT_METHOD=talosctl-shutdown+virsh  # For GPU nodes: 'talosctl-reboot' or 'talosctl-shutdown+virsh'
#   GPU_DOMAIN_PREFIX=           # Optional prefix for libvirt domain name mapping
#   GPU_DOMAIN_SUFFIX=           # Optional suffix for libvirt domain name mapping
#   GPU_DOMAIN_MAP_FILE=         # Optional CSV (node,domain) to map node to libvirt domain
#   VIRSH_BIN=virsh              # virsh binary (can be overridden)
#   ENABLE_TALOS_UPGRADE=false   # If true, perform Talos OS upgrade instead of plain reboot
#   TALOS_TARGET_VERSION=        # Target Talos version, e.g. v1.11.6 (used if installer image not provided)
#   TALOS_INSTALLER_IMAGE=       # Full installer image, e.g. ghcr.io/siderolabs/installer:v1.11.6
#   GPU_ALLOW_AUTO_REBOOT_ON_UPGRADE=false  # If true, allow talosctl upgrade auto-reboot on GPU nodes
#
set -euo pipefail

BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
export BASE_DIR

# Tools & context (explicit paths per guidelines)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
TALOSCTL="/home/k8s/talos/talosctl"
export TALOSCONFIG="/home/k8s/talos/config/talosconfig"
VIRSH_BIN="${VIRSH_BIN:-virsh}"

REGISTRY_SVC_FQDN="registry.hierocracy.home:5000"
REGISTRY_LB_IP="registry.hierocracy.home:5000"
REGISTRY_HTTP_ENDPOINT="http://registry.hierocracy.home:5000"

RAG_NAMESPACE="rag-system"
LLM_NAMESPACE="llms-ollama"
ROOK_NS="rook-ceph"

# RAG/LLM deployments to scale back up after verification (leave healthy ones alone)
RAG_DEPLOYMENTS=(
  db-adapter
  llm-gateway
  object-store-mgr
  qdrant-adapter
  rag-ingestion-service
  rag-worker
)
LLM_DEPLOYMENTS=(
  ollama-granite31-8b
  ollama-llama3
)

# Include journaling helpers
source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

require_tools() {
  if [[ ! -x "$KUBECTL" ]]; then
    echo "[ERROR] kubectl not found at $KUBECTL or not executable" >&2
    exit 1
  fi
  if [[ ! -x "$TALOSCTL" ]]; then
    echo "[ERROR] talosctl not found at $TALOSCTL or not executable" >&2
    exit 1
  fi
  # Require Krew rook-ceph plugin unless fallback is explicitly allowed
  if ! _rook_ceph_plugin_available; then
    if [[ "${ALLOW_TOOLBOX_FALLBACK:-false}" == "true" ]]; then
      echo "[WARN] Krew rook-ceph plugin not detected; will attempt toolbox fallback when needed."
    else
      echo "[ERROR] Krew rook-ceph plugin not detected. Please install via Krew (kubectl krew install rook-ceph) or set ALLOW_TOOLBOX_FALLBACK=true to allow toolbox fallback." >&2
      exit 1
    fi
  fi
}

# --- Ceph helpers (plugin preferred, toolbox fallback) ---
_ceph_toolbox_pod() {
  # Try by label first (rook-ceph-tools), otherwise grep by name
  local pod
  pod=$("$KUBECTL" -n "$ROOK_NS" get pods -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$pod" ]]; then
    pod=$("$KUBECTL" -n "$ROOK_NS" get pods -o name 2>/dev/null | grep -m1 rook-ceph-tools || true)
    pod=${pod#pod/}
  fi
  echo "$pod"
}

_rook_ceph_plugin_available() {
  # Quick heuristic: try a harmless command via plugin; don't spam logs
  "$KUBECTL" rook-ceph version >/dev/null 2>&1
}

run_ceph() {
  # Usage: run_ceph <args...>  (e.g., run_ceph osd set noout)
  if _rook_ceph_plugin_available; then
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      echo "DRY_RUN $KUBECTL rook-ceph -n $ROOK_NS ceph $*"
      return 0
    fi
    "$KUBECTL" rook-ceph -n "$ROOK_NS" ceph "$@"
    return $?
  fi

  if [[ "${ALLOW_TOOLBOX_FALLBACK:-false}" == "true" ]]; then
    local toolbox
    toolbox=$(_ceph_toolbox_pod)
    if [[ -n "$toolbox" ]]; then
      if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "DRY_RUN $KUBECTL -n $ROOK_NS exec $toolbox -- ceph $*"
        return 0
      fi
      "$KUBECTL" -n "$ROOK_NS" exec "$toolbox" -- ceph "$@"
      return $?
    fi
  fi

  echo "[ERROR] Krew rook-ceph plugin not available and toolbox fallback disabled/unavailable. Cannot run 'ceph $*'" >&2
  return 127
}

set_ceph_noout() {
  if is_step_done "ceph-noout-set"; then return 0; fi
  echo "[CEPH] Setting 'noout' flag"
  run_ceph osd set noout
  mark_step_done "ceph-noout-set"
}

unset_ceph_noout() {
  if is_step_done "ceph-noout-unset"; then return 0; fi
  echo "[CEPH] Unsetting 'noout' flag"
  run_ceph osd unset noout
  mark_step_done "ceph-noout-unset"
}

osd_ids_for_node() {
  # Prints space-separated OSD IDs scheduled on the given node
  local node="$1"
  "$KUBECTL" -n "$ROOK_NS" get pods -l app=rook-ceph-osd -o json \
    | jq -r --arg NODE "$node" '.items[] | select(.spec.nodeName==$NODE) | .metadata.labels["ceph.osd_id"]' 2>/dev/null \
    | xargs echo
}

ok_to_stop_node_osds() {
  local node="$1"
  local ids
  # Attempt to get OSD IDs without jq fallback (in case jq absent)
  if command -v jq >/dev/null 2>&1; then
    ids=$(osd_ids_for_node "$node")
  else
    # jq-less fallback using jsonpath (labels.ceph\.osd_id)
    ids=$("$KUBECTL" -n "$ROOK_NS" get pods -l app=rook-ceph-osd \
      -o jsonpath='{range .items[?(@.spec.nodeName=="'$node'")]}{.metadata.labels.ceph\.osd_id}{"\n"}{end}' 2>/dev/null | xargs echo)
  fi

  if [[ -z "$ids" ]]; then
    echo "[CEPH] No OSDs found on node $node (ok-to-stop trivially true)"
    return 0
  fi

  echo "[CEPH] ok-to-stop check for node $node OSDs: $ids"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "DRY_RUN ceph osd ok-to-stop $ids"
    return 0
  fi
  run_ceph osd ok-to-stop $ids
}

kubectl_cmd() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "DRY_RUN kubectl $*"
  else
    "$KUBECTL" "$@"
  fi
}

talosctl_cmd() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "DRY_RUN talosctl $*"
  else
    "$TALOSCTL" "$@"
  fi
}

# Detect-supported reboot flags and perform a reboot with waiting
talosctl_reboot_wait() {
  local ip="$1"
  local help
  help=$("$TALOSCTL" reboot --help 2>/dev/null || true)
  local args=(reboot -n "$ip")
  if grep -q -- "--wait" <<<"$help"; then
    args+=(--wait)
  fi
  if grep -q -- "--timeout" <<<"$help"; then
    args+=(--timeout=600s)
  fi
  if grep -q -- "--graceful" <<<"$help"; then
    args+=(--graceful)
  fi
  talosctl_cmd "${args[@]}"
}

# ---------- GPU-safe helpers ----------
is_gpu_node() {
  local node="$1"
  # Try jsonpath for allocatable GPU count
  local cnt
  cnt=$("$KUBECTL" get node "$node" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "")
  if [[ -n "$cnt" && "$cnt" != "0" ]]; then
    return 0
  fi
  # Fallback: check capacity
  cnt=$("$KUBECTL" get node "$node" -o jsonpath='{.status.capacity.nvidia\.com/gpu}' 2>/dev/null || echo "")
  if [[ -n "$cnt" && "$cnt" != "0" ]]; then
    return 0
  fi
  return 1
}

lookup_domain_for_node() {
  local node="$1"
  local map_file="${GPU_DOMAIN_MAP_FILE:-}"
  if [[ -n "$map_file" && -f "$map_file" ]]; then
    # Simple CSV: node,domain (ignore whitespace)
    local line domain
    line=$(grep -E "^\s*${node}\s*," "$map_file" 2>/dev/null || true)
    if [[ -n "$line" ]]; then
      domain=${line#*,}
      domain=${domain// /}
      echo "$domain"
      return 0
    fi
  fi
  echo "${GPU_DOMAIN_PREFIX:-}${node}${GPU_DOMAIN_SUFFIX:-}"
}

run_virsh() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "DRY_RUN $VIRSH_BIN $*"
  else
    "$VIRSH_BIN" "$@"
  fi
}

gpu_cold_cycle_domain() {
  local domain="$1"
  echo "    [GPU] Attempt graceful shutdown of domain '$domain'"
  # Try graceful shutdown, then force if needed
  run_virsh shutdown "$domain" || true
  # Wait up to 120s for domain to stop
  local i
  for i in $(seq 1 24); do
    local st
    st=$($VIRSH_BIN domstate "$domain" 2>/dev/null || echo unknown)
    echo "      [GPU] domstate=$st"
    if [[ "$st" == "shut off" || "$st" == "shutoff" ]]; then
      break
    fi
    sleep 5
  done
  local st
  st=$($VIRSH_BIN domstate "$domain" 2>/dev/null || echo unknown)
  if [[ "$st" != "shut off" && "$st" != "shutoff" ]]; then
    echo "    [GPU] Forcing destroy of domain '$domain'"
    run_virsh destroy "$domain" || true
  fi
  echo "    [GPU] Starting domain '$domain'"
  run_virsh start "$domain"
}

gpu_safe_reboot_node() {
  local node="$1" ip="$2"
  local method="${GPU_REBOOT_METHOD:-talosctl-shutdown+virsh}"
  echo "  - GPU-safe reboot for $node using method: $method"
  if [[ "$method" == "talosctl-reboot" ]]; then
    talosctl_reboot_wait "$ip"
    return $?
  fi
  # Default: shutdown guest first, then host cold cycle
  echo "    [GPU] talosctl shutdown guest $node ($ip)"
  local help
  help=$("$TALOSCTL" shutdown --help 2>/dev/null || true)
  local args=(shutdown -n "$ip")
  if grep -q -- "--wait" <<<"$help"; then args+=(--wait); fi
  if grep -q -- "--timeout" <<<"$help"; then args+=(--timeout=300s); fi
  talosctl_cmd "${args[@]}" || true
  # Host-side domain cycle
  local domain
  domain=$(lookup_domain_for_node "$node")
  gpu_cold_cycle_domain "$domain"
}

# ---------- Talos upgrade helpers ----------
talos_installer_image() {
  # Priority: TALOS_INSTALLER_IMAGE > TALOS_TARGET_VERSION > empty
  if [[ -n "${TALOS_INSTALLER_IMAGE:-}" ]]; then
    echo "$TALOS_INSTALLER_IMAGE"
    return 0
  fi
  if [[ -n "${TALOS_TARGET_VERSION:-}" ]]; then
    echo "ghcr.io/siderolabs/installer:${TALOS_TARGET_VERSION}"
    return 0
  fi
  echo ""  # caller must handle empty
}

talosctl_upgrade_supports_flag() {
  local flag="$1"
  local help
  help=$("$TALOSCTL" upgrade --help 2>/dev/null || true)
  grep -q -- "$flag" <<<"$help"
}

talosctl_upgrade_node() {
  # Args: ip, is_gpu(boolean)
  local ip="$1"; local is_gpu="$2"
  local image
  image=$(talos_installer_image)
  if [[ -z "$image" ]]; then
    echo "[WARN] TALOS_INSTALLER_IMAGE/TALOS_TARGET_VERSION not set; skipping upgrade on $ip"
    return 2
  fi
  local args=(upgrade -n "$ip" --image "$image" --preserve)
  # Prefer to wait for completion when supported
  if talosctl_upgrade_supports_flag "--wait"; then args+=(--wait); fi
  if talosctl_upgrade_supports_flag "--timeout"; then args+=(--timeout=900s); fi
  # If GPU node, try to disable auto reboot so we can do GPU-safe reboot
  if [[ "$is_gpu" == "true" ]]; then
    if talosctl_upgrade_supports_flag "--reboot="; then
      args+=(--reboot=false)
    elif talosctl_upgrade_supports_flag "--reboot-mode"; then
      args+=(--reboot-mode=none)
    else
      if [[ "${GPU_ALLOW_AUTO_REBOOT_ON_UPGRADE:-false}" != "true" ]]; then
        echo "[ERROR] Cannot disable auto-reboot for talosctl upgrade on GPU node $ip; set GPU_ALLOW_AUTO_REBOOT_ON_UPGRADE=true to override."
        return 3
      fi
    fi
  fi
  echo "    [Talos] upgrade $ip with image=$image"
  talosctl_cmd "${args[@]}"
}

upgrade_control_planes_safely() {
  if ! [[ "${ENABLE_TALOS_UPGRADE:-false}" == "true" ]]; then return 0; fi
  if is_step_done "talos-upgrade-cp"; then return 0; fi
  echo "[STEP] Talos OS upgrade: control-plane nodes"
  local cp_nodes
  mapfile -t cp_nodes < <("$KUBECTL" get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  for node in "${cp_nodes[@]}"; do
    [[ -z "$node" ]] && continue
    local ip
    ip=$(get_node_ip "$node")
    echo "[CP] $node ($ip)"
    # Cordon + drain
    cordon_node "$node"
    drain_node "$node"
    # Upgrade (non-GPU path assumed for control-plane)
    talosctl_upgrade_node "$ip" false
    # Wait Ready + uncordon + Ceph health gate
    wait_node_ready "$node"
    uncordon_node "$node"
    if ! wait_ceph_ok; then
      echo "[ERROR] Ceph not HEALTH_OK after control-plane $node upgrade" >&2
      exit 1
    fi
  done
  mark_step_done "talos-upgrade-cp"
}

ceph_health() {
  # Returns Ceph health string or UNKNOWN on error
  "$KUBECTL" -n "$ROOK_NS" get cephcluster -o jsonpath='{.items[0].status.ceph.health}' 2>/dev/null || echo UNKNOWN
}

wait_ceph_ok() {
  local max_wait=180
  local delay=5
  local i=0
  while (( i < max_wait )); do
    local h
    h=$(ceph_health)
    echo "[CEPH] health=$h (t=${i}s)"
    # If health is OK, or if it's WARN but ONLY because 'noout' is set, we are good to proceed.
    if [[ "$h" == "HEALTH_OK" ]]; then
      echo "[CEPH] HEALTH_OK confirmed"
      return 0
    elif [[ "$h" == "HEALTH_WARN" ]]; then
      # Check if 'noout' is the only reason for the warning.
      # We check the detail for the presence of other issues.
      local detail
      detail=$(run_ceph health detail 2>/dev/null || echo "UNKNOWN")
      if grep -q "noout flag(s) set" <<<"$detail" && ! grep -vE "noout flag\(s\) set|HEALTH_WARN" <<<"$detail" | grep -q "[A-Z]"; then
        echo "[CEPH] HEALTH_WARN detected but confirmed only due to 'noout'. Proceeding."
        return 0
      fi
    fi
    sleep "$delay"
    i=$((i+delay))
  done
  echo "[ERROR] Ceph did not reach a safe state within ${max_wait}s" >&2
  return 1
}

node_ready() {
  local node="$1"
  "$KUBECTL" get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo Unknown
}

wait_node_ready() {
  local node="$1"
  local max_wait=600
  local delay=5
  local i=0
  while (( i < max_wait )); do
    local s
    s=$(node_ready "$node")
    echo "[NODE:$node] Ready=$s (t=${i}s)"
    if [[ "$s" == "True" ]]; then
      echo "[NODE:$node] Ready=True"
      return 0
    fi
    sleep "$delay"
    i=$((i+delay))
  done
  echo "[ERROR] Node $node did not become Ready within ${max_wait}s" >&2
  return 1
}

drain_node() {
  local node="$1"
  kubectl_cmd drain "$node" --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=10m
}

cordon_node() {
  local node="$1"
  kubectl_cmd cordon "$node"
}

uncordon_node() {
  local node="$1"
  kubectl_cmd uncordon "$node"
}

get_node_ip() {
  local node="$1"
  "$KUBECTL" get node "$node" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'
}

apply_registries_patch_all_nodes() {
  if is_step_done "registries-patch"; then return 0; fi
  echo "[STEP] Writing canonical registries patch ($SAFE_TMP_DIR/registries-clean.yaml)"
  cat > "$SAFE_TMP_DIR/registries-clean.yaml" <<PATCH
machine:
  registries:
    mirrors:
      "${REGISTRY_SVC_FQDN}":
        endpoints:
          - "${REGISTRY_HTTP_ENDPOINT}"
      "${REGISTRY_LB_IP}":
        endpoints:
          - "${REGISTRY_HTTP_ENDPOINT}"
    config:
      "${REGISTRY_SVC_FQDN}":
        insecure: true
      "${REGISTRY_LB_IP}":
        insecure: true
PATCH

  echo "[STEP] Applying registries patch to all nodes"
  local ips
  ips=$("$KUBECTL" get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
  for ip in $ips; do
    echo "  - Patching $ip"
    talosctl_cmd -n "$ip" patch machineconfig --patch-file "$SAFE_TMP_DIR/registries-clean.yaml"
  done
  mark_step_done "registries-patch"
}

reboot_workers_safely() {
  if is_step_done "workers-rebooted"; then return 0; fi

  echo "[STEP] Enumerating worker nodes"
  mapfile -t WORKERS < <("$KUBECTL" get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  if [[ ${#WORKERS[@]} -eq 0 ]]; then
    echo "[WARN] No worker nodes detected. Skipping reboots."
    mark_step_done "workers-rebooted"
    return 0
  fi

  echo "[INFO] Workers: ${WORKERS[*]}"

  # Set Ceph maintenance flag before starting
  set_ceph_noout

  # shellcheck disable=SC1073
  for node in "${WORKERS[@]}"; do
    echo "[NODE] Processing $node"
    local ip
    ip=$(get_node_ip "$node")
    if [[ -z "$ip" ]]; then
      echo "[ERROR] Could not resolve IP for node $node" >&2
      exit 1
    fi

    echo "  - Verifying ceph osd ok-to-stop for OSDs on $node"
    if ! ok_to_stop_node_osds "$node"; then
      echo "[ERROR] Ceph reports NOT ok-to-stop for node $node OSDs. Aborting." >&2
      exit 1
    fi

    echo "  - Cordon $node"
    cordon_node "$node"
    echo "  - Drain $node"
    drain_node "$node"
    if [[ "${GPU_SAFE_MODE:-false}" == "true" ]] && is_gpu_node "$node"; then
      echo "  - Detected GPU node; performing GPU-safe reboot workflow"
      gpu_safe_reboot_node "$node" "$ip"
    else
      echo "  - Reboot $node (talosctl with auto-detected flags)"
      talosctl_reboot_wait "$ip"
    fi
    echo "  - Waiting for $node to become Ready"
    wait_node_ready "$node"
    echo "  - Uncordon $node"
    uncordon_node "$node"
    echo "  - Waiting for Ceph HEALTH_OK before proceeding"
    if ! wait_ceph_ok; then
      echo "[ERROR] Ceph did not reach HEALTH_OK after rebooting $node. Stopping per policy." >&2
      exit 1
    fi
    echo "[NODE] $node processed successful"
  done

  # Unset Ceph maintenance flag after all nodes processed successfully
  unset_ceph_noout

  mark_step_done "workers-rebooted"
}

verify_image_pull() {
  if is_step_done "image-pull-verified"; then return 0; fi
  echo "[VERIFY] Test image pull via service name"
  kubectl_cmd -n default delete pod image-pull-test --ignore-not-found=true
  kubectl_cmd -n default run image-pull-test \
    --image="${REGISTRY_SVC_FQDN}/rag-test-runner:1.0.0" \
    --restart=Never --command -- sleep 30
  set +e
  "$KUBECTL" -n default wait --for=condition=Ready pod/image-pull-test --timeout=180s
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "[ERROR] image-pull-test did not become Ready; describing pod" >&2
    "$KUBECTL" -n default describe pod image-pull-test || true
    return 1
  fi
  kubectl_cmd -n default delete pod image-pull-test --wait=false --ignore-not-found=true
  mark_step_done "image-pull-verified"
}

scale_services_back_up() {
  if [[ "${SKIP_SCALE:-false}" == "true" ]]; then
    echo "[SCALE] Skipped by SKIP_SCALE=true"
    return 0
  fi
  if is_step_done "scaled-services"; then return 0; fi
  echo "[SCALE] Scaling RAG and LLM deployments to replicas=1"
  for d in "${RAG_DEPLOYMENTS[@]}"; do
    kubectl_cmd -n "$RAG_NAMESPACE" scale deploy "$d" --replicas=1 || true
  done
  for d in "${LLM_DEPLOYMENTS[@]}"; do
    kubectl_cmd -n "$LLM_NAMESPACE" scale deploy "$d" --replicas=1 || true
  done
  mark_step_done "scaled-services"
}

run_e2e() {
  if [[ "${SKIP_E2E:-false}" == "true" ]]; then
    echo "[E2E] Skipped by SKIP_E2E=true"
    return 0
  fi
  if is_step_done "e2e-run"; then return 0; fi
  echo "[E2E] Running end-to-end tests via tests/run-e2e-on-hierophant.sh"
  bash "$BASE_DIR/rag-stack/tests/run-e2e-on-hierophant.sh"
  mark_step_done "e2e-run"
}

main() {
  echo "=== Fix Image Pulls & Rolling Reboot (Talos + Ceph-safe) ==="
  require_tools

  echo "[INFO] Registry Service check"
  "$KUBECTL" -n container-registry get svc registry -o wide || true

  apply_registries_patch_all_nodes
  # Optional Talos OS upgrade on control-plane first (if enabled)
  upgrade_control_planes_safely
  reboot_workers_safely
  verify_image_pull
  scale_services_back_up
  run_e2e

  clear_journal
  echo "[DONE] All steps completed successfully"
}

main "$@"
