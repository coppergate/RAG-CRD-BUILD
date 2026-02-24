#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

# Journaling
source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

if ! is_step_done "nvidia-namespace"; then
  echo "[NVIDIA] Creating namespace and applying Pod Security labels"
  $KUBECTL create namespace gpu-operator || true
  $KUBECTL label --overwrite namespace gpu-operator \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged
  mark_step_done "nvidia-namespace"
fi

if ! is_step_done "nvidia-runtimeclass"; then
  echo "[NVIDIA] Creating RuntimeClass 'nvidia'"
  $KUBECTL apply -f "$SCRIPT_DIR/nvidia-runtimeclass.yaml"
  mark_step_done "nvidia-runtimeclass"
fi

if ! is_step_done "nvidia-device-plugin"; then
  echo "[NVIDIA] Installing/Upgrading NVIDIA Device Plugin via Helm"
  helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
  helm repo update
  helm upgrade --install \
    -n gpu-operator \
    nvidia-device-plugin \
    nvdp/nvidia-device-plugin \
    --version=0.14.5 \
    --set=runtimeClassName=nvidia \
    --set nodeSelector.role=inference-node \
    --wait
  mark_step_done "nvidia-device-plugin"
fi

if ! is_step_done "nvidia-dcgm-exporter"; then
  echo "[NVIDIA] Deploying DCGM Exporter"
  /bin/bash "$SCRIPT_DIR/nvidia-gpu-exporter.sh"
  mark_step_done "nvidia-dcgm-exporter"
fi

## Add the nvidia helm repostiory
#helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
#
## Update the repostiories to get the latest changes
#helm repo update
#
#  
## Install the nvidia operator helm chart
#helm install --wait --name nvidia-operator-deploy \
# -n gpu-operator \
# nvidia/gpu-operator \
# --set driver.enabled=false \
# --set nodeSelector.role=inference-node

