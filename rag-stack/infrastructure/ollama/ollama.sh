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
# The ollama/ollama runtime image and every ollama/* model artifact live in the
# UPSTREAM mirror on hierophant, not the in-cluster registry (which holds only
# locally built services). Verified: hierophant carries ollama/ollama plus
# ollama/{all-minilm,devstral-small-2,granite3.1-dense,llama3.1,llama3.2,
# mxbai-embed-large,nomic-embed-text}; the in-cluster catalog is
# ["build-orchestrator"] alone.
#
# This was the in-cluster name until 2026-09-16 and it silently overrode the
# values files via --set image.repository, so repointing values*.yaml alone was
# not enough: every ollama-embed-*/planner-cpu-*/llama3/qwen32b deployment went
# into ImagePullBackOff with "not found". $REGISTRY is used ONLY for
# image.repository here, so pointing it upstream is complete.
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../../../config/network.env" ]]; then
    # shellcheck source=../../../config/network.env
    source "$(dirname "${BASH_SOURCE[0]}")/../../../config/network.env"
fi
REGISTRY="${REGISTRY_PREFIX:-hierophant.hierocracy.home:5000}"

# --- GPU allocation ----------------------------------------------------------
# REMOVED 2026-09-13: the UUID-resolve block and the ollama-gpu-pin-v100
# ConfigMap that used to live here.
#
# inference-0 held a MIXED pool (1x V100 32GB + 2x P4 8GB) advertised as one
# fungible nvidia.com/gpu, so a plain resource request could hand a 32B model an
# 8GB card. The workaround was to set ollama.gpu.enabled=false, skip the resource
# request entirely, and pin the V100 via NVIDIA_VISIBLE_DEVICES from a ConfigMap
# built right here from the hierocracy.home/gpu-v100-uuid node label.
#
# The P4s are gone and the node now holds TWO identical V100 32GB cards, so:
#   - ordinary 'nvidia.com/gpu: 1' requests are correct and sufficient;
#   - allocatable is 2, so the scheduler puts the two GPU pods on TWO DISTINCT
#     cards instead of stacking both on one — this is a straight win over the
#     old arrangement, where they shared a card and contended for VRAM;
#   - scheduler accounting is restored, so nothing can double-book a card.
#
# Both values files now set ollama.gpu.enabled=true with number: 1, and neither
# references the deleted ConfigMap. infrastructure/nvidia-operator.sh no longer
# publishes any gpu-*-uuid label, so resolving one here would fail outright.
#
# Deploy Ollama WITHOUT model pulling — models are seeded separately via
# seed-models.sh. This avoids long postStart hangs during install.
#
# Two GPU deployments on inference-0, one card each:
#   ollama-llama3  — planner endpoint (ollama service); llama3.1 + granite3.1-dense:8b seeded
#   ollama-qwen32b — executor endpoint (ollama-code service); qwen2.5:32b + all GPU models seeded
# Both use nodeSelector: role=inference-node (values.yaml default) — no --set override needed.
#
# NOTE: inference-0 is tainted nvidia.com/gpu=present:NoSchedule by
# scripts/setup-node-labels.sh. These pods tolerate it TWICE over, and that is
# expected — verified with 'helm template' 2026-09-13:
#   1. an explicit block in each values file (values.yaml, values-qwen32b.yaml);
#   2. one the chart itself adds now that ollama.gpu.enabled=true (it added
#      none while that flag was false, which is why the explicit block exists).
# Two identical tolerations are legal and inert; Kubernetes does not dedupe them.
# The explicit blocks are kept deliberately so the toleration does not silently
# depend on gpu.enabled staying true.
# --- Executor model selection ------------------------------------------------
# The executor pod's values file is switchable because the two candidates are
# mutually exclusive: there are two cards, the planner holds one, so the
# executor model is a swap and never an addition.
#
#   values-qwen32b.yaml   qwen3:32b        ~20 GB Q4_K_M, 16384 ctx  (default)
#   values-devstral.yaml  devstral-small-2 ~15 GB q4_K_M, 65536 ctx
#
# To switch:  EXECUTOR_VALUES=values-devstral.yaml bash ollama.sh
#
# The release name stays 'ollama-qwen32b' under either file. The otwld/ollama
# chart names the PVC after the release, so renaming it would create a new PVC
# and discard every seeded model. Service name (ollama-code), endpoint URL and
# rag-worker config are unaffected by the swap; only which model is resident
# changes, and both are seeded into this PVC by seed-models.sh.
EXECUTOR_VALUES="${EXECUTOR_VALUES:-values-qwen32b.yaml}"
if [[ ! -f "$SCRIPT_DIR/$EXECUTOR_VALUES" ]]; then
  echo "ERROR: EXECUTOR_VALUES=$EXECUTOR_VALUES not found in $SCRIPT_DIR" >&2
  exit 1
fi
echo "Executor values file: $EXECUTOR_VALUES"

$HELM upgrade --install ollama-llama3 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values.yaml" \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"
$HELM upgrade --install ollama-qwen32b otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/$EXECUTOR_VALUES" \
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
# REMOVED 2026-09-13: waits on deploy/ollama-embed-0 and
# deploy/ollama-planner-cpu-0. Both releases were deleted from this script (see
# the REMOVED note further down) when inference-0 became GPU-only, so these
# waited on objects that do not exist. Harmless under '|| true', but they logged
# a failure on every install and read as if two pods were missing.

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