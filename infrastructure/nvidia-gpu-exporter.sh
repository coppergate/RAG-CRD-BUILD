#!/bin/bash
# nvidia-gpu-exporter.sh - Deploy DCGM Exporter for NVIDIA GPU metrics on Talos
# To be executed on host: hierophant

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="gpu-operator"

# Journaling
source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

if ! is_step_done "dcgm-exporter"; then
  echo "--- Deploying NVIDIA DCGM Exporter ---"
  helm repo add dcgm-repo https://nvidia.github.io/dcgm-exporter/helm-charts
  helm repo update

  # Deploy dcgm-exporter with Talos-specific settings
  helm upgrade --install dcgm-exporter dcgm-repo/dcgm-exporter \
    --namespace $NAMESPACE \
    --create-namespace \
    --set runtimeClassName=nvidia \
    --set nodeSelector.role=inference-node \
    --set serviceMonitor.enabled=false \
    --wait
  mark_step_done "dcgm-exporter"
fi

clear_journal

echo "DCGM Exporter deployed successfully."
