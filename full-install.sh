#!/bin/bash
# ==============================================================================
# full-install.sh — End-to-end cluster + RAG stack install
# IMPORTANT: Must be executed on host: hierophant
#
# Usage: FRESH_INSTALL=true bash full-install.sh [--no-gpu]
#
# Flags:
#   --no-gpu            — skip the NVIDIA GPU operator. Default is to INSTALL it:
#                         it publishes the hierocracy.home/gpu-*-uuid node labels
#                         that ollama.sh requires, so the RAG stack cannot deploy
#                         without it. For a genuinely GPU-less build use
#                         full-install-no-gpu.sh instead.
#   --gpu               — retained as a no-op for backward compatibility.
#
# Environment:
#   FRESH_INSTALL=true  — clear ALL journals before starting (both cluster
#                         and RAG stack). Without this, a failed prior run
#                         resumes from the last successful step.
#
# Stages:
#   1. Pre-authenticate sudo (single password prompt, kept alive throughout)
#   2. config-cluster.sh  — provision Talos VMs and bring up Kubernetes
#   3. Wait for all nodes Ready
#   4. setup-complete.sh  — deploy Rook/Ceph, APM, registry, RAG stack
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLUSTER_SETUP_DIR="/mnt/hegemon-share/share/code/kubernetes-setup/new-setup-single"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

# Export FRESH_INSTALL so child scripts (config-cluster.sh, setup-complete.sh) see it
export FRESH_INSTALL="${FRESH_INSTALL:-false}"

# -----------------------------------------------------------------------
# 0. Clear ALL journals on fresh install (BEFORE init_journal)
# -----------------------------------------------------------------------
# Three journal scopes exist:
#   full-install.sh's own journal  — tracks top-level stages (this script)
#   ~/.kubernetes-setup/journal/   — used by config-cluster.sh
#   ~/.complete-build/journal/     — used by setup-complete.sh + setup-01-basic.sh
# Each child script only clears its own. We clear ALL here to guarantee
# a truly fresh start and prevent stale journals from skipping steps.
# This MUST happen before init_journal, otherwise init creates the journal
# and the rm immediately deletes it.
if [[ "$FRESH_INSTALL" == "true" ]]; then
    echo "FRESH_INSTALL=true — clearing all journals from previous runs..."
    rm -rf "${HOME}/.kubernetes-setup/journal/"* 2>/dev/null || true
    rm -rf "${HOME}/.complete-build/journal/"* 2>/dev/null || true
    echo "All journals cleared."
fi

# full-install.sh uses its OWN journal (in the complete-build journal dir) to track
# which top-level stages have completed. This prevents the dangerous scenario where
# config-cluster.sh clears its internal journal on success, then setup-complete.sh
# fails — re-running full-install.sh would re-enter config-cluster.sh with a blank
# journal and reformat disks on a running cluster.
source "$SCRIPT_DIR/scripts/journal-helper.sh"
init_journal

# CRITICAL: Reset FRESH_INSTALL to false for child scripts. full-install.sh has
# already cleared all journals above. If we leave FRESH_INSTALL=true, child scripts
# (especially setup-complete.sh's clear_all_journals) will re-delete the
# ~/.complete-build/journal/ directory — which contains THIS script's journal.
# That destroys our "cluster-provisioned" marker and causes re-entry on resume.
export FRESH_INSTALL="false"

# -----------------------------------------------------------------------
# 1. Sudo pre-authentication
# -----------------------------------------------------------------------
echo "============================================================"
echo "  Full Install: Cluster + RAG Stack"
echo "  FRESH_INSTALL=${FRESH_INSTALL}"
echo "  This script requires sudo for system certificate setup."
echo "============================================================"
echo ""
if ! sudo -n true 2>/dev/null; then
    echo "Please enter your sudo password:"
    sudo -v
fi
# Keep sudo alive in background for the duration of this script
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done & )
echo "Sudo session active."
echo ""

# -----------------------------------------------------------------------
# 2. Cluster provisioning
# -----------------------------------------------------------------------
if ! is_step_done "cluster-provisioned"; then
  echo "============================================================"
  echo "  Stage 1: Provisioning Kubernetes cluster (config-cluster.sh)"
  echo "============================================================"
  bash "${CLUSTER_SETUP_DIR}/config-cluster.sh" "$@"
  mark_step_done "cluster-provisioned"
else
  echo "[full-install] Cluster already provisioned — skipping config-cluster.sh"
fi

# -----------------------------------------------------------------------
# 3. Wait for all nodes to be Ready
# -----------------------------------------------------------------------
if ! is_step_done "nodes-ready"; then
  echo ""
  echo "============================================================"
  echo "  Stage 2: Waiting for cluster nodes to become Ready"
  echo "============================================================"

  NODE_WAIT_TIMEOUT=900   # 15 minutes — nodes reboot + Talos init can be slow
  NODE_WAIT_INTERVAL=15
  elapsed=0

  echo "Waiting for Kubernetes API to respond..."
  until $KUBECTL cluster-info >/dev/null 2>&1; do
      if (( elapsed >= NODE_WAIT_TIMEOUT )); then
          echo "ERROR: Kubernetes API did not become available within ${NODE_WAIT_TIMEOUT}s." >&2
          exit 1
      fi
      echo "  API not ready yet, retrying in ${NODE_WAIT_INTERVAL}s... (${elapsed}s elapsed)"
      sleep "$NODE_WAIT_INTERVAL"
      (( elapsed += NODE_WAIT_INTERVAL )) || true
  done
  echo "Kubernetes API is responding."

  echo "Waiting for all nodes to reach Ready state (timeout: ${NODE_WAIT_TIMEOUT}s)..."
  $KUBECTL wait --for=condition=Ready nodes --all --timeout="${NODE_WAIT_TIMEOUT}s"
  echo "All nodes are Ready."

  # Show node summary
  echo ""
  $KUBECTL get nodes -o wide
  echo ""
  mark_step_done "nodes-ready"
else
  echo "[full-install] Nodes already verified Ready — skipping wait"
fi

# -----------------------------------------------------------------------
# 4. RAG stack deployment
# -----------------------------------------------------------------------
echo "============================================================"
echo "  Stage 3: Deploying RAG stack (setup-complete.sh)"
echo "============================================================"
bash "${SCRIPT_DIR}/setup-complete.sh" "$@"

echo ""
echo "============================================================"
echo "  Full install complete."
echo "============================================================"
