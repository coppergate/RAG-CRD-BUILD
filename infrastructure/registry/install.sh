#!/bin/bash
# install.sh - Local Registry Installation
# To be executed on host: hierophant

set -e

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

source "${BASE_DIR:-.}/scripts/journal-helper.sh"
init_journal

if ! is_step_done "registry-deploy"; then
echo "--- 1. Deploying Local Registry to K8s ---"
$KUBECTL apply -f "$REPO_DIR/registry.yaml"
mark_step_done "registry-deploy"
fi

if ! is_step_done "registry-patch"; then
echo "--- 2. Applying Talos Registry Patches ---"
# Note: apply-patch.sh expects absolute paths and uses talosctl
bash "$REPO_DIR/apply-patch.sh"
mark_step_done "registry-patch"
fi

if ! is_step_done "registry-wait"; then
echo "--- 3. Waiting for Registry Pod to be Ready ---"
$KUBECTL wait --for=condition=ready pod -l app=registry -n container-registry --timeout=120s
mark_step_done "registry-wait"
fi

clear_journal

echo "Local Registry Setup Complete."
