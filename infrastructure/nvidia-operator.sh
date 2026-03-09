#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

NAMESPACE="gpu-operator"
RELEASE_NAME="gpu-operator"
GPU_OPERATOR_CHART_VERSION="${GPU_OPERATOR_CHART_VERSION:-25.10.1}"
TIMEOUT_SECS="${TIMEOUT_SECS:-600}"

source "$BASE_DIR/scripts/journal-helper.sh"
init_journal

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $c" >&2
    exit 1
  fi
}

require_cmd "$KUBECTL"
require_cmd helm

echo "[NVIDIA] Validating Kubernetes API access..."
"$KUBECTL" version >/dev/null 2>&1

if ! is_step_done "nvidia-namespace"; then
  echo "[NVIDIA] Ensuring namespace and Pod Security labels"
  "$KUBECTL" get ns "$NAMESPACE" >/dev/null 2>&1 || "$KUBECTL" create namespace "$NAMESPACE"
  "$KUBECTL" label --overwrite namespace "$NAMESPACE" \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/enforce-version=latest \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged
  mark_step_done "nvidia-namespace"
fi

if ! is_step_done "nvidia-runtimeclass"; then
  echo "[NVIDIA] Applying RuntimeClass 'nvidia'"
  "$KUBECTL" apply -f "$SCRIPT_DIR/nvidia-runtimeclass.yaml"
  mark_step_done "nvidia-runtimeclass"
fi

if ! is_step_done "nvidia-talos-config"; then
  echo "[NVIDIA] Applying Talos-specific device plugin config"
  "$KUBECTL" apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
data:
  config.yaml: |
    version: v1
    flags:
      failOnInitError: true
      nvidiaDriverRoot: /
      nvidiaDevRoot: /
      deviceDiscoveryStrategy: nvml
    sharing:
      timeSlicing: {}
EOF

  echo "[NVIDIA] Applying Talos validation-fix DaemonSet"
  "$KUBECTL" apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-talos-validation-fix
  labels:
    app: nvidia-talos-validation-fix
spec:
  selector:
    matchLabels:
      name: nvidia-talos-validation-fix
  template:
    metadata:
      labels:
        name: nvidia-talos-validation-fix
    spec:
      nodeSelector:
        nvidia.com/gpu.present: "true"
      hostPID: true
      tolerations:
      - operator: Exists
      containers:
      - name: validation-fix
        image: registry.hierocracy.home:5000/busybox:1.36
        command:
        - sh
        - -c
        - |
          while true; do
            mkdir -p /run/nvidia/validations /run/nvidia/driver/usr
            ln -sfn /host/usr/local/bin /run/nvidia/driver/usr/bin
            ln -sfn /host/usr/local/glibc/usr/lib /run/nvidia/driver/usr/lib64
            touch /run/nvidia/validations/driver-ready
            touch /run/nvidia/validations/toolkit-ready
            touch /run/nvidia/validations/cuda-ready
            sleep 30
          done
        volumeMounts:
        - name: run-nvidia
          mountPath: /run/nvidia
      volumes:
      - name: run-nvidia
        hostPath:
          path: /run/nvidia
          type: DirectoryOrCreate
EOF
  mark_step_done "nvidia-talos-config"
fi

if ! is_step_done "nvidia-cleanup-legacy"; then
  echo "[NVIDIA] Removing legacy NVIDIA releases to avoid conflicts (best effort)"
  if helm -n "$NAMESPACE" status nvidia-device-plugin >/dev/null 2>&1; then
    helm -n "$NAMESPACE" uninstall nvidia-device-plugin || true
  fi
  if helm -n "$NAMESPACE" status nvidia-dcgm-exporter >/dev/null 2>&1; then
    helm -n "$NAMESPACE" uninstall nvidia-dcgm-exporter || true
  fi
  mark_step_done "nvidia-cleanup-legacy"
fi

if ! is_step_done "nvidia-gpu-operator"; then
  echo "[NVIDIA] Installing/Upgrading NVIDIA GPU Operator (Talos-aware)"
  helm repo add nvidia https://nvidia.github.io/gpu-operator >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  VALUES_FILE="${SAFE_TMP_DIR}/gpu-operator-values.yaml"
  cat > "$VALUES_FILE" <<'EOF'
driver:
  enabled: false
toolkit:
  enabled: false
operator:
  defaultRuntime: nvidia
devicePlugin:
  enabled: true
  runtimeClassName: nvidia
  config:
    name: nvidia-device-plugin-config
  env:
    - name: CDI_ENABLED
      value: "false"
    - name: DEVICE_LIST_STRATEGY
      value: "envvar"
EOF

  helm upgrade --install "$RELEASE_NAME" nvidia/gpu-operator \
    -n "$NAMESPACE" \
    --create-namespace \
    --version "$GPU_OPERATOR_CHART_VERSION" \
    -f "$VALUES_FILE" \
    --wait \
    --timeout "${TIMEOUT_SECS}s"
  mark_step_done "nvidia-gpu-operator"
fi

echo "[NVIDIA] Waiting for GPU operator deployment rollout"
"$KUBECTL" -n "$NAMESPACE" rollout status deploy/gpu-operator --timeout="${TIMEOUT_SECS}s" || true

echo "[NVIDIA] Waiting for device plugin daemonset rollout"
PLUGIN_DS=$("$KUBECTL" -n "$NAMESPACE" get ds -l app.kubernetes.io/name=nvidia-device-plugin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "${PLUGIN_DS}" ]]; then
  "$KUBECTL" -n "$NAMESPACE" rollout status "ds/${PLUGIN_DS}" --timeout="${TIMEOUT_SECS}s" || true
fi

echo "[NVIDIA] Current GPU operator pods"
"$KUBECTL" -n "$NAMESPACE" get pods -o wide || true

echo "[NVIDIA] Node allocatable GPU view"
"$KUBECTL" get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' || true
