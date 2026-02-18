
KUBECTL="/home/k8s/kube/kubectl"

$KUBECTL create namespace gpu-operator || true

$KUBECTL label --overwrite namespace gpu-operator \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged

# Create the nvidia RuntimeClass
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
$KUBECTL apply -f "$SCRIPT_DIR/nvidia-runtimeclass.yaml"

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update
helm upgrade --install \
-n gpu-operator \
nvidia-device-plugin \
nvdp/nvidia-device-plugin \
--version=0.14.5 \
--set=runtimeClassName=nvidia  \
--set nodeSelector.role=inference-node

# Deploy the DCGM Exporter for metrics
/bin/bash "$SCRIPT_DIR/nvidia-gpu-exporter.sh"

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

