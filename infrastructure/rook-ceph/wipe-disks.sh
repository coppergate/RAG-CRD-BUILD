#!/bin/bash
# wipe-disks.sh - Wipes disks on worker nodes before Rook-Ceph OSD creation
# To be executed on host: hierophant

set -e

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

# Allow callers to override which YAML and job selector to use.
# Default: full-GPU layout (3 workers, vdb-vdf on worker-0).
# No-GPU callers export WIPE_DISKS_YAML and WIPE_DISKS_JOB_SELECTOR before running this script.
WIPE_YAML="${WIPE_DISKS_YAML:-$REPO_DIR/wipe-disks.yaml}"
WIPE_JOB_SELECTOR="${WIPE_DISKS_JOB_SELECTOR:-job-name in (wipe-disks-worker-0, wipe-disks-worker-1, wipe-disks-worker-2, wipe-disks-worker-3)}"

# ── SAFETY GATE — DO NOT REMOVE ─────────────────────────────────────────────
# These jobs zero the first 100 MB of every device they list. That is only safe
# BEFORE OSDs exist.
#
# On 2026-09-14 this script re-ran against a LIVE cluster and zeroed the LVM PV
# labels and BlueStore superblocks under all five running OSDs. They kept
# serving from already-mapped device-mapper devices while being unrecoverable on
# disk -- nothing looked broken until a reboot would have lost every OSD.
#
# It re-ran because the guard in setup-01-basic.sh is only the journal marker
# "rook-ceph-wipe-disks", and an earlier run had created the CephCluster and
# then died before writing it. A journal marker cannot express "OSDs now exist";
# only the cluster can. So ask the cluster.
#
# FORCE_WIPE=true is the deliberate "I am reprovisioning storage and accept
# losing everything on it" override.
osd_count=$($KUBECTL -n rook-ceph get deploy -l app=rook-ceph-osd \
              --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
if [ "${osd_count:-0}" -gt 0 ] && [ "${FORCE_WIPE:-false}" != "true" ]; then
    echo "--- SKIPPING disk wipe: ${osd_count} rook-ceph OSD deployment(s) already exist ---"
    echo "    Wiping now would zero the disks backing them."
    echo "    If you are deliberately reprovisioning storage, re-run with FORCE_WIPE=true."
    exit 0
fi

echo "--- Wiping disks on worker nodes (YAML: $WIPE_YAML) ---"
$KUBECTL delete -f "$WIPE_YAML" --ignore-not-found
$KUBECTL apply -f "$WIPE_YAML"

echo "Waiting for wipe-disks jobs to complete..."
if ! $KUBECTL wait --for=condition=complete job -l "$WIPE_JOB_SELECTOR" -n rook-ceph --timeout=300s; then
    echo "ERROR: wipe-disks jobs timed out or failed."
    $KUBECTL get pods -n rook-ceph
    $KUBECTL delete -f "$WIPE_YAML"
    exit 1
fi

echo "Cleaning up wipe-disks jobs..."
$KUBECTL delete -f "$WIPE_YAML"

echo "Disk wiping complete."
