#!/bin/bash
# wipe-disks.sh - Wipes disks on worker nodes before Rook-Ceph OSD creation
# To be executed on host: hierophant

set -e

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

echo "--- Wiping disks on worker nodes ---"
$KUBECTL delete -f "$REPO_DIR/wipe-disks.yaml" --ignore-not-found
$KUBECTL apply -f "$REPO_DIR/wipe-disks.yaml"

echo "Waiting for wipe-disks jobs to complete..."
if ! $KUBECTL wait --for=condition=complete job -l 'job-name in (wipe-disks-worker-0, wipe-disks-worker-1, wipe-disks-worker-2, wipe-disks-worker-3)' -n rook-ceph --timeout=300s; then
    echo "ERROR: wipe-disks jobs timed out or failed."
    $KUBECTL get pods -n rook-ceph
    $KUBECTL delete -f "$REPO_DIR/wipe-disks.yaml"
    exit 1
fi

echo "Cleaning up wipe-disks jobs..."
$KUBECTL delete -f "$REPO_DIR/wipe-disks.yaml"

echo "Disk wiping complete."
