#!/bin/bash
# nvidia-operator.sh — NVIDIA GPU Operator for the external GPU node (Talos-aware)
#
# AUTHORITATIVE. This script is the single source of truth for the GPU operator
# and for the GPU node labels the RAG stack depends on. The logic was previously
# duplicated in kubernetes-setup/new-setup-external-gpu/52-install-gpu-operator.sh,
# and complete-build's copy had drifted into the WORSE of the two — it was missing
# mig.strategy=none and devicePlugin.config.default, so running it would undo the
# tuned install. That divergence is resolved here.
#
# Repo boundary: kubernetes-setup owns Talos-level node provisioning (machine
# config, kernel modules, driver extensions, enrolment). complete-build owns
# everything that is a Kubernetes object — this operator, the RuntimeClass, the
# device-plugin ConfigMap, the validation-fix DaemonSet, and the GPU node labels.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

NAMESPACE="gpu-operator"
RELEASE_NAME="gpu-operator"
GPU_OPERATOR_CHART_VERSION="${GPU_OPERATOR_CHART_VERSION:-25.10.1}"
TIMEOUT_SECS="${TIMEOUT_SECS:-600}"

# Whether to advertise nvidia.com/gpu at all.
#
# Under the pin-by-UUID model this cluster uses, nothing should REQUEST
# nvidia.com/gpu — pinned pods bypass the plugin entirely, so the scheduler does
# not know the card is busy. A pod that does request it can be handed a GPU a
# pinned job already holds, and they fight over VRAM.
#
# Left enabled by default: inert as long as no manifest asks for the resource,
# and it keeps GFD's node labels current. Set false to remove the resource from
# the node outright. DCGM metrics and the driver are unaffected either way.
DEVICE_PLUGIN_ENABLED="${DEVICE_PLUGIN_ENABLED:-true}"

# GPU UUIDs, published as node labels so workloads pin a card by reading a label
# instead of hardcoding a 40-character UUID in every manifest. Consumed by
# rag-stack/infrastructure/ollama/ollama.sh, which HARD-FAILS without them.
#
# Verified: an UNPRIVILEGED pod setting NVIDIA_VISIBLE_DEVICES to one of these
# sees exactly that GPU and nothing else. The operator's own DaemonSets are
# privileged, which is why the same trick does not work on them.
#
# These are fallbacks. If GPU_UUID_DISCOVER=true (default) the script derives
# them from the live node first, so a reseated or swapped card does not silently
# leave every pinned workload pointing at a UUID that no longer exists.
GPU_UUID_DISCOVER="${GPU_UUID_DISCOVER:-true}"
GPU_UUID_V100="${GPU_UUID_V100:-GPU-ce06ba79-6e2e-b16e-e326-3ba4747c6ecb}"
GPU_UUID_P4_0="${GPU_UUID_P4_0:-GPU-6a3e90b5-542c-4189-8385-62224608c4fa}"
GPU_UUID_P4_1="${GPU_UUID_P4_1:-GPU-d5cfa048-3ff2-dcec-f9bc-d0c7797dfbb5}"

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
      # 'none' — neither the V100 nor the P4 supports MIG. The chart default
      # 'single' asserts a uniform node, which makes GFD log "Multiple device
      # types detected" and pick one product to describe all three GPUs.
      migStrategy: none
      deviceDiscoveryStrategy: nvml
    #
    # REMOVED — nvidiaDriverRoot: / and nvidiaDevRoot: /
    # Harmless only while this ConfigMap was being ignored (see the 'default'
    # key in the Helm values below). Now that it is actually consumed, they are
    # wrong: '/' does not exist as a driver root on Talos. The plugin default of
    # /run/nvidia/driver is the layout nvidia-talos-validation-fix builds.
    #
    # DO NOT add a 'resources:' block to split the P4s onto their own resource
    # name. Tried; plugin v0.19.3 refuses it outright:
    #   W config.go:88] Customizing the 'resources' field is not yet supported
    #                   in the config. Ignoring...
    # Per-product resource naming is unimplemented, so every GPU on the node
    # lands in one nvidia.com/gpu pool regardless. Restricting the pool has to
    # happen below the plugin — hence pin-by-UUID.
    #
    # DO NOT add an empty 'sharing: timeSlicing: {}' block. It fails config
    # parsing with "no resources specified", the plugin will not start, and
    # nvidia.com/gpu drops to 0. This was previously present and inert; it only
    # became fatal once 'default: config.yaml' made the file load. Re-add only
    # with real content, e.g.:
    #   sharing:
    #     timeSlicing:
    #       resources:
    #       - name: nvidia.com/gpu
    #         replicas: 2
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
        gpu: "true"
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
            # On Talos, /usr/local is accessible from the host.
            # This pod needs to create symlinks in /run/nvidia so the validator thinks the driver is ready.
            # We use absolute paths that point to /host since the validator and device plugin mount the host root at /host.
            ln -sfn /host/usr/local/bin /run/nvidia/driver/usr/bin
            ln -sfn /host/usr/local/glibc/usr/lib /run/nvidia/driver/usr/lib64
            touch /run/nvidia/validations/driver-ready
            touch /run/nvidia/validations/toolkit-ready
            touch /run/nvidia/validations/cuda-ready
            sleep 30
          done
        securityContext:
          privileged: true
        volumeMounts:
        - name: run-nvidia
          mountPath: /run/nvidia
        - name: host-root
          mountPath: /host
          readOnly: true
      volumes:
      - name: run-nvidia
        hostPath:
          path: /run/nvidia
          type: DirectoryOrCreate
      - name: host-root
        hostPath:
          path: /
EOF
  mark_step_done "nvidia-talos-config"
fi

# ── GPU node labels ──────────────────────────────────────────────────────────
# Publishes the per-card UUIDs that workloads pin against. This is a HARD
# dependency of rag-stack/infrastructure/ollama/ollama.sh, which exits non-zero
# if hierocracy.home/gpu-v100-uuid is absent. Verified against the live node,
# so re-run this script after any GPU is added, removed or reseated.
#
# Custom domain prefix so these cannot be confused with, or overwritten by, the
# nvidia.com/* labels GFD manages.
if ! is_step_done "nvidia-gpu-labels" "$KUBECTL" get node -l hierocracy.home/gpu-v100-uuid -o name | grep -q node; then
  echo "[NVIDIA] Publishing GPU inventory labels"

  GPU_NODE=$("$KUBECTL" get nodes -l role=inference-node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -z "$GPU_NODE" ]]; then
    echo "ERROR: no node carries role=inference-node. scripts/setup-node-labels.sh" >&2
    echo "       should have applied it before this script runs." >&2
    exit 1
  fi

  # Prefer discovery over the hardcoded fallbacks. nvidia-smi is not directly
  # runnable on Talos, so shell out through a throwaway pod that mounts the host
  # NVIDIA userspace. Parses 'nvidia-smi -L' lines of the form:
  #   GPU 0: Tesla PG500-216 (UUID: GPU-ce06ba79-...)
  if [[ "$GPU_UUID_DISCOVER" == "true" ]]; then
    echo "[NVIDIA] Discovering GPU UUIDs on $GPU_NODE..."
    SMI_OUT=$("$KUBECTL" run gpu-uuid-probe-$$ --rm -i --restart=Never \
      --image="${REGISTRY_PREFIX:-hierophant.hierocracy.home:5000}/busybox:1.36" \
      --overrides="{\"spec\":{\"nodeName\":\"$GPU_NODE\",\"hostPID\":true,\"tolerations\":[{\"operator\":\"Exists\"}],\"containers\":[{\"name\":\"p\",\"image\":\"${REGISTRY_PREFIX:-hierophant.hierocracy.home:5000}/busybox:1.36\",\"command\":[\"chroot\",\"/host\",\"/usr/local/bin/nvidia-smi\",\"-L\"],\"securityContext\":{\"privileged\":true},\"volumeMounts\":[{\"name\":\"h\",\"mountPath\":\"/host\"}]}],\"volumes\":[{\"name\":\"h\",\"hostPath\":{\"path\":\"/\"}}]}}" \
      --timeout=120s 2>/dev/null || echo "")

    D_V100=$(echo "$SMI_OUT" | grep -iE "PG500|V100" | grep -oE 'GPU-[0-9a-f-]+' | head -1 || true)
    mapfile -t D_P4 < <(echo "$SMI_OUT" | grep -i "Tesla P4" | grep -oE 'GPU-[0-9a-f-]+' || true)

    if [[ -n "$D_V100" ]]; then
      echo "  discovered V100: $D_V100"; GPU_UUID_V100="$D_V100"
    else
      echo "  WARNING: V100 not discovered — using fallback $GPU_UUID_V100" >&2
    fi
    [[ -n "${D_P4[0]:-}" ]] && { echo "  discovered P4-0: ${D_P4[0]}"; GPU_UUID_P4_0="${D_P4[0]}"; }
    [[ -n "${D_P4[1]:-}" ]] && { echo "  discovered P4-1: ${D_P4[1]}"; GPU_UUID_P4_1="${D_P4[1]}"; }
  fi

  # gpu-pool-mixed is the important one: even with mig.strategy=none the
  # nvidia.com/gpu pool contains all THREE devices, so the nvidia.com/gpu.*
  # labels describe only part of it. Pin by UUID; do not select on those labels.
  #
  # Deliberately NOT publishing a 'gpu-labels-describe' claim here. The sibling
  # repo set it to tesla-v100-32gb, and it was observed to be FALSE on the live
  # node (GFD was reporting Tesla-P4 at the time). A label asserting something
  # unverifiable is worse than no label.
  "$KUBECTL" label --overwrite node "$GPU_NODE" \
    hierocracy.home/gpu-total-count=3 \
    hierocracy.home/gpu-v100-count=1 \
    hierocracy.home/gpu-p4-count=2 \
    hierocracy.home/gpu-heterogeneous=true \
    hierocracy.home/gpu-pool-mixed=true \
    "hierocracy.home/gpu-v100-uuid=${GPU_UUID_V100}" \
    "hierocracy.home/gpu-p4-0-uuid=${GPU_UUID_P4_0}" \
    "hierocracy.home/gpu-p4-1-uuid=${GPU_UUID_P4_1}"

  mark_step_done "nvidia-gpu-labels"
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
  cat > "$VALUES_FILE" <<EOF
driver:
  enabled: false
toolkit:
  enabled: false
mig:
  # REQUIRED on this node. The chart default is 'single', which asserts a
  # uniform node; on a mixed pool (1x V100 + 2x P4) that makes GFD collapse the
  # node's labels onto one product — observed reporting gpu.product=Tesla-P4 /
  # count=2 and hiding the V100 entirely.
  #
  # This surfaces on the containers as the MIG_STRATEGY env var, and the plugin
  # resolves env ABOVE its config file — so setting migStrategy in the ConfigMap
  # alone cannot fix it. It must be set here too. Neither card supports MIG, so
  # 'none' is also simply correct.
  strategy: none
operator:
  defaultRuntime: nvidia
  # Run the operator controller on a worker node, not control plane.
  nodeSelector:
    role: storage-node
node-feature-discovery:
  # NFD workers run on EVERY node by default, including control plane.
  # Restrict to inference nodes only — they are the only nodes with GPUs.
  # The 'role=inference-node' label is set by setup-node-labels.sh before
  # this script runs, so it is safe to use as a nodeSelector here.
  # Key is the sub-chart name 'node-feature-discovery', NOT 'nodeFeatureDiscovery'.
  worker:
    nodeSelector:
      role: inference-node
  master:
    nodeSelector:
      role: storage-node
devicePlugin:
  enabled: ${DEVICE_PLUGIN_ENABLED}
  runtimeClassName: nvidia
  nodeSelector:
    gpu: "true"
  config:
    name: nvidia-device-plugin-config
    # REQUIRED. Without 'default' naming the key, the operator ignores the
    # entire ConfigMap and the plugin silently runs on chart defaults — which is
    # what advertised all three GPUs as one pool and lost migStrategy.
    default: config.yaml
  env:
    - name: CDI_ENABLED
      value: "false"
    - name: DEVICE_LIST_STRATEGY
      value: "envvar"
gfd:
  enabled: true
  nodeSelector:
    gpu: "true"
dcgmExporter:
  enabled: true
  nodeSelector:
    gpu: "true"
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
