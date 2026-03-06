#!/usr/bin/env bash
# update-talosctl.sh — Update talosctl on hierophant
#
# Purpose:
#   - Install/upgrade talosctl to a version matching the cluster Talos OS when possible.
#   - Default behavior tries to detect Talos OS version from Kubernetes nodes and use that.
#   - Falls back to a pinned safe version if detection fails.
#
# Requirements (per project guidelines):
#   - Run on host: hierophant
#   - Uses explicit paths
#     * KUBECTL: /home/k8s/kube/kubectl
#     * TALOSCTL destination: /home/k8s/talos/talosctl
#
# Config via env vars:
#   TALOSCTL_VERSION   Explicit version (e.g., v1.11.6). If unset, auto-detect from nodes.
#   DRY_RUN=true       Print actions without making changes.
#   FRESH_INSTALL=true Reset journal.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
export BASE_DIR

KUBECTL="/home/k8s/kube/kubectl"
DEST_DIR="/home/k8s/talos"
DEST_BIN="$DEST_DIR/talosctl"

# Journal helpers
source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

log() { echo -e "$*"; }

run_or_echo() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo "DRY_RUN $*"
  else
    eval "$*"
  fi
}

is_executable() { command -v "$1" >/dev/null 2>&1; }

detect_version_from_cluster() {
  if ! is_executable "$KUBECTL"; then
    return 1
  fi
  # Try to parse Talos version from node info (e.g., "Talos (v1.11.6)")
  local osimage
  if ! osimage=$("$KUBECTL" get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage}' 2>/dev/null); then
    return 1
  fi
  if [[ "$osimage" =~ (v[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

arch_map() {
  local m=$(uname -m)
  case "$m" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "amd64" ;;
  esac
}

download_talosctl() {
  local ver="$1"
  local arch
  arch=$(arch_map)
  local url="https://github.com/siderolabs/talos/releases/download/${ver}/talosctl-linux-${arch}"

  log "[STEP] Download talosctl ${ver} for ${arch}"
  run_or_echo "curl -fL --connect-timeout 10 --retry 3 --retry-delay 2 -o $SAFE_TMP_DIR/talosctl.new '${url}'"
  run_or_echo "chmod +x $SAFE_TMP_DIR/talosctl.new"
}

backup_existing() {
  if [[ -x "$DEST_BIN" ]]; then
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    run_or_echo "cp -f '$DEST_BIN' '${DEST_BIN}.bak.${ts}'"
    log "[INFO] Existing talosctl backed up to ${DEST_BIN}.bak.${ts}"
  fi
}

install_new() {
  run_or_echo "mkdir -p '$DEST_DIR'"
  if run_or_echo "mv -f $SAFE_TMP_DIR/talosctl.new '$DEST_BIN'"; then
    :
  else
    # Fallback to sudo if we lack permissions
    run_or_echo "sudo mv -f $SAFE_TMP_DIR/talosctl.new '$DEST_BIN'"
  fi
}

verify_version() {
  if [[ -x "$DEST_BIN" ]]; then
    "$DEST_BIN" version || "$DEST_BIN" --version || true
  else
    log "[WARN] $DEST_BIN not found/executable after install"
  fi
}

main() {
  if ! is_step_done "update-start"; then
    log "=== talosctl updater ==="
    mark_step_done "update-start"
  fi

  local ver="${TALOSCTL_VERSION:-}"
  if [[ -z "$ver" ]]; then
    if ver=$(detect_version_from_cluster); then
      log "[INFO] Detected Talos OS version from cluster: $ver"
    else
      ver="v1.11.6" # safe default matching observed cluster Talos version
      log "[WARN] Could not detect version from cluster; defaulting to $ver"
    fi
  else
    log "[INFO] Using requested talosctl version: $ver"
  fi

  if ! is_step_done "download"; then
    download_talosctl "$ver"
    mark_step_done "download"
  fi

  if ! is_step_done "backup"; then
    backup_existing
    mark_step_done "backup"
  fi

  if ! is_step_done "install"; then
    install_new
    mark_step_done "install"
  fi

  if ! is_step_done "verify"; then
    log "[STEP] Verifying talosctl"
    verify_version
    mark_step_done "verify"
  fi

  clear_journal
  log "[DONE] talosctl update complete"
}

main "$@"
