#!/bin/bash
# nvidia-gpu-exporter.sh - Deploy DCGM Exporter for NVIDIA GPU metrics on Talos
# To be executed on host: hierophant

set -e

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
NAMESPACE="gpu-operator"

echo "--- Deploying NVIDIA DCGM Exporter ---"

helm repo add dcgm-repo https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# Deploy dcgm-exporter with Talos-specific settings
helm upgrade --install dcgm-exporter dcgm-repo/dcgm-exporter \
  --namespace $NAMESPACE \
  --create-namespace \
  --set runtimeClassName=nvidia \
  --set nodeSelector.role=inference-node \
  --wait

echo "DCGM Exporter deployed successfully."
