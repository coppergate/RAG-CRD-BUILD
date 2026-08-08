SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
HELM="helm --kubeconfig /home/k8s/kube/config/kubeconfig"

$HELM repo add otwld https://helm.otwld.com/
$HELM repo update

$KUBECTL create namespace llms-ollama || true

$KUBECTL label --overwrite namespace llms-ollama \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged

# Inject Registry & Pulsar CA ConfigMap
echo "--- Injecting Registry & Pulsar CA into llms-ollama ---"
# Source journal-helper for SAFE_TMP_DIR and REPO_DIR (if available)
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$REPO_DIR/../scripts/journal-helper.sh"
mkdir -p "$SAFE_TMP_DIR"

COMBINED_CA="$SAFE_TMP_DIR/combined-ca.crt"
rm -f "$COMBINED_CA"
touch "$COMBINED_CA"

# 0. Include system roots
HOST_CA_BUNDLE="/etc/pki/tls/certs/ca-bundle.crt"
if [ ! -f "$HOST_CA_BUNDLE" ]; then
    HOST_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
fi
if [ -f "$HOST_CA_BUNDLE" ]; then
    echo "Including system CA roots from $HOST_CA_BUNDLE..."
    cat "$HOST_CA_BUNDLE" >> "$COMBINED_CA"
fi

# 1. Extract Registry CA
if $KUBECTL get secret in-cluster-registry-tls -n container-registry >/dev/null 2>&1; then
    echo "Extracting Registry CA from container-registry/in-cluster-registry-tls..."
    $KUBECTL get secret in-cluster-registry-tls -n container-registry -o jsonpath='{.data.ca\.crt}' | base64 --decode >> "$COMBINED_CA"
else
    echo "Fallback: Extracting Registry CA from Talos registry patch..."
    CA_B64=$(grep "ca: " "/mnt/hegemon-share/share/code/kubernetes-setup/configs/talos-registry-patch.yaml" | head -n 1 | awk '{print $2}')
    if [ -n "$CA_B64" ]; then
        echo "$CA_B64" | base64 -d >> "$COMBINED_CA"
    fi
fi

# 2. Extract Pulsar CA (if available)
if $KUBECTL get secret pulsar-ca-tls -n apache-pulsar >/dev/null 2>&1; then
    echo "Extracting Pulsar CA from apache-pulsar/pulsar-ca-tls..."
    echo "" >> "$COMBINED_CA" # Ensure newline
    $KUBECTL get secret pulsar-ca-tls -n apache-pulsar -o jsonpath='{.data.ca\.crt}' | base64 --decode >> "$COMBINED_CA"
fi

if [ -s "$COMBINED_CA" ]; then
    $KUBECTL create configmap registry-ca-cm -n llms-ollama --from-file=ca.crt="$COMBINED_CA" --dry-run=client -o yaml | $KUBECTL apply -f -
    # Also create 'registry-ca' for legacy compatibility
    $KUBECTL create configmap registry-ca -n llms-ollama --from-file=ca.crt="$COMBINED_CA" --dry-run=client -o yaml | $KUBECTL apply -f -
else
    echo "WARNING: Could not find any CA to inject into llms-ollama."
fi
rm -f "$COMBINED_CA"
  
# Single inference node — label inference-0 only.
$KUBECTL label nodes inference-0 role=inference-node --overwrite

# Label worker nodes with embed-instance index for pod pinning.
# worker-0..3 already carry role=storage-node; embed-instance is additive.
# NOTE: must cover every index the deploy loops below iterate (0..3). worker-3
# was previously missing, which left ollama-embed-8, ollama-embed-9 and
# ollama-planner-cpu-5 selecting embed-instance=3 — a label on no node — so they
# sat permanently Pending on a fresh install.
$KUBECTL label nodes worker-0 embed-instance=0 --overwrite
$KUBECTL label nodes worker-1 embed-instance=1 --overwrite
$KUBECTL label nodes worker-2 embed-instance=2 --overwrite
$KUBECTL label nodes worker-3 embed-instance=3 --overwrite

# Create services for CPU pods before installing them so they are ready when pods come up.
# Each service selects pods by the ollama-role label set via podLabels in the values files.
$KUBECTL apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: ollama-embed
  namespace: llms-ollama
spec:
  selector:
    ollama-role: embed
  ports:
  - port: 11434
    targetPort: 11434
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: ollama-planner-cpu
  namespace: llms-ollama
spec:
  selector:
    ollama-role: planner-cpu
  ports:
  - port: 11434
    targetPort: 11434
  type: ClusterIP
EOF

# Deploy using the OCI artifacts pushed to the local registry
# We revert image.repository to the base Ollama image and specify models to pull from the local registry.
REGISTRY="registry.container-registry.svc.cluster.local:5000"

# --- GPU pinning: resolve the V100 by UUID -----------------------------------
# inference-0 has a MIXED GPU pool (1x V100 32GB + 2x P4 8GB) all advertised as
# one fungible nvidia.com/gpu. The GPU values files therefore set
# ollama.gpu.enabled=false and pin the card by UUID instead, via the ConfigMap
# built here. See values-qwen32b.yaml for why node-affinity is not an option.
#
# TODO(revisit once the cluster is stable): both GPU pods currently share the
# V100, preserving the VRAM tuning written for the old single-GPU node
# (OLLAMA_MAX_LOADED_MODELS is set accordingly in each values file). With three
# cards available, ollama-llama3 could move to a P4 (gpu-p4-0-uuid) to free
# ~5GB of V100 VRAM for the 32B executor. That also requires trimming the 32B
# models from ollama-llama3's seed list in seed-models.sh (an 8GB P4 cannot
# load them) and forcing its OLLAMA_MAX_LOADED_MODELS to 1. Deferred
# deliberately: it changes model routing as well as placement.
echo "--- Resolving GPU UUID for pinning ---"
GPU_NODE=$($KUBECTL get nodes -l role=inference-node \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "$GPU_NODE" ]]; then
  echo "ERROR: no node carries role=inference-node — cannot pin a GPU." >&2
  echo "       scripts/setup-node-labels.sh should have applied it." >&2
  exit 1
fi

# Label published by kubernetes-setup/new-setup-external-gpu/52-install-gpu-operator.sh
V100_UUID=$($KUBECTL get node "$GPU_NODE" \
  -o jsonpath='{.metadata.labels.hierocracy\.home/gpu-v100-uuid}' 2>/dev/null || echo "")
if [[ -z "$V100_UUID" ]]; then
  echo "ERROR: node $GPU_NODE has no hierocracy.home/gpu-v100-uuid label." >&2
  echo "       Re-run 52-install-gpu-operator.sh in kubernetes-setup/new-setup-external-gpu" >&2
  echo "       to republish the GPU UUID labels, then retry." >&2
  exit 1
fi
echo "  - $GPU_NODE V100 = $V100_UUID"

# NVIDIA_DRIVER_CAPABILITIES must include 'compute' for CUDA; 'utility' alone
# only yields nvidia-smi. Consumed via extraEnvFrom in both GPU values files.
$KUBECTL create configmap ollama-gpu-pin-v100 -n llms-ollama \
  --from-literal=NVIDIA_VISIBLE_DEVICES="$V100_UUID" \
  --from-literal=NVIDIA_DRIVER_CAPABILITIES="compute,utility" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

# Deploy Ollama WITHOUT model pulling — models are seeded separately via seed-models.sh
# This avoids long postStart hangs during install.
#
# Two GPU deployments on inference-0, both pinned to the V100 by UUID:
#   ollama-llama3  — planner endpoint (ollama service); llama3.1 + granite3.1-dense:8b seeded
#   ollama-qwen32b — executor endpoint (ollama-code service); qwen2.5:32b + all GPU models seeded
# Both use nodeSelector: role=inference-node (values.yaml default) — no --set override needed.
# NOTE: with no nvidia.com/gpu request there is no scheduler GPU accounting, so
# co-residency on the V100 is enforced by these manifests, not by Kubernetes.
$HELM upgrade --install ollama-llama3 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values.yaml" \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"
$HELM upgrade --install ollama-qwen32b otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values-qwen32b.yaml" \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"
$KUBECTL expose deployment ollama-llama3 --name=ollama --port=11434 --target-port=11434 --type=LoadBalancer -n llms-ollama || true
$KUBECTL expose deployment ollama-qwen32b --name=ollama-code --port=11434 --target-port=11434 --type=LoadBalancer -n llms-ollama || true

# REMOVED: ollama-embed-0 and ollama-planner-cpu-0.
#
# Both were CPU-only pods (ollama.gpu.enabled=false) pinned to role=inference-node,
# using values-embed.yaml / values-planner-cpu.yaml. inference-0 is now reserved
# for GPU workloads only — it is tainted nvidia.com/gpu=present:NoSchedule by
# scripts/setup-node-labels.sh — so CPU-only work belongs on the worker nodes.
#
# No service change is needed: ollama-embed and ollama-planner-cpu are ClusterIP
# services selecting on the ollama-role pod label (set via podLabels in the values
# files), not on release name. The worker-node pods deployed below continue to
# back both services.
#
# Capacity after this change, with the worker-3 label fix above:
#   embed        — 8 pods (ollama-embed-2..9, 2 per worker node)
#   planner-cpu  — 4 pods (ollama-planner-cpu-2..5, 1 per worker node)
#
# values-embed.yaml and values-planner-cpu.yaml are now unreferenced. They are
# kept as the templates for the inference-node variant in case a second, non-GPU
# inference node is ever added; the deployed worker pods use the *-worker.yaml
# variants instead.
#
# If embed/planner capacity needs to be restored, add instances on the workers
# with values-embed-worker.yaml / values-planner-cpu-worker.yaml — do NOT
# reintroduce these two releases on the inference node.

# Deploy CPU-only embedding Ollama on each worker node — 2 pods per node (embed-2..9).
# All pods carry ollama-role=embed and are picked up by the ollama-embed ClusterIP service.
# Each pair is pinned to its node via embed-instance label set above.
for INSTANCE in 0 1 2 3; do
  for OFFSET in 0 1; do
    IDX=$(( INSTANCE * 2 + OFFSET + 2 ))
    echo "Deploying ollama-embed-${IDX} on worker node embed-instance=${INSTANCE}..."
    $HELM upgrade --install ollama-embed-${IDX} otwld/ollama \
      --namespace llms-ollama \
      -f "$SCRIPT_DIR/values-embed-worker.yaml" \
      --set-string "nodeSelector.embed-instance=${INSTANCE}" \
      --set image.repository="${REGISTRY}/ollama/ollama" \
      --set image.tag="0.15.6"
  done
done

# Deploy CPU-only planner Ollama on each worker node — 1 pod per node (planner-cpu-2..5).
# All pods carry ollama-role=planner-cpu and are picked up by the ollama-planner-cpu service.
for INSTANCE in 0 1 2 3; do
  IDX=$(( INSTANCE + 2 ))
  echo "Deploying ollama-planner-cpu-${IDX} on worker node embed-instance=${INSTANCE}..."
  $HELM upgrade --install ollama-planner-cpu-${IDX} otwld/ollama \
    --namespace llms-ollama \
    -f "$SCRIPT_DIR/values-planner-cpu-worker.yaml" \
    --set-string "nodeSelector.embed-instance=${INSTANCE}" \
    --set image.repository="${REGISTRY}/ollama/ollama" \
    --set image.tag="0.15.6"
done

# Wait for inference-node pods to be ready before seeding models
echo "Waiting for inference-node Ollama pods to be ready..."
$KUBECTL rollout status deploy/ollama-llama3 -n llms-ollama --timeout=600s || true
$KUBECTL rollout status deploy/ollama-qwen32b -n llms-ollama --timeout=600s || true
$KUBECTL rollout status deploy/ollama-embed-0 -n llms-ollama --timeout=600s || true
$KUBECTL rollout status deploy/ollama-planner-cpu-0 -n llms-ollama --timeout=600s || true

# Wait for worker-node pods to be ready
echo "Waiting for worker-node Ollama pods to be ready..."
for IDX in 2 3 4 5 6 7 8 9; do
  $KUBECTL rollout status deploy/ollama-embed-${IDX} -n llms-ollama --timeout=600s || true
done
for IDX in 2 3 4 5; do
  $KUBECTL rollout status deploy/ollama-planner-cpu-${IDX} -n llms-ollama --timeout=600s || true
done

# Seed models from local registry into PVCs
if [[ "${SKIP_SEEDING:-false}" != "true" ]]; then
    echo "Seeding LLM models from local registry..."
    bash "$SCRIPT_DIR/seed-models.sh"
fi