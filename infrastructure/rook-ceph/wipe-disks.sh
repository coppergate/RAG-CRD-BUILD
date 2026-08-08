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
WIPE_JOB_SELECTOR="${WIPE_DISKS_JOB_SELECTOR:-job-name in (wipe-disks-worker-0, wipe-disks-worker-1, wipe-disks-worker-2)}"

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
