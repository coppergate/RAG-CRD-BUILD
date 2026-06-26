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
# worker-0..2 already carry role=storage-node; embed-instance is additive.
$KUBECTL label nodes worker-0 embed-instance=0 --overwrite
$KUBECTL label nodes worker-1 embed-instance=1 --overwrite
$KUBECTL label nodes worker-2 embed-instance=2 --overwrite

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

# Deploy Ollama WITHOUT model pulling — models are seeded separately via seed-models.sh
# This avoids long postStart hangs during install.
#
# Two GPU deployments on inference-0:
#   ollama-llama3  — planner endpoint (ollama service); llama3.1 + granite3.1-dense:8b seeded
#   ollama-qwen32b — executor endpoint (ollama-code service); qwen2.5:32b + all GPU models seeded
# Both use nodeSelector: role=inference-node (values.yaml default) — no --set override needed.
$HELM upgrade --install ollama-llama3 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values.yaml" \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"
$HELM upgrade --install ollama-qwen32b otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values-qwen32b.yaml" \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"
$KUBECTL expose deployment ollama-llama3 --name=ollama --port=11434 --target-port=11434 --type=LoadBalancer -n llms-ollama || true
$KUBECTL expose deployment ollama-qwen32b --name=ollama-code --port=11434 --target-port=11434 --type=LoadBalancer -n llms-ollama || true

# Deploy CPU-only embedding Ollama on inference-0.
# Selected by the ollama-embed ClusterIP service alongside worker-node embed pods.
# nodeSelector: role=inference-node comes from values-embed.yaml default.
$HELM upgrade --install ollama-embed-0 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values-embed.yaml" \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"

# Deploy CPU-only alternate planner Ollama on inference-0.
# Selected by the ollama-planner-cpu ClusterIP service alongside worker-node planner pods.
# nodeSelector: role=inference-node comes from values-planner-cpu.yaml default.
$HELM upgrade --install ollama-planner-cpu-0 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values-planner-cpu.yaml" \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"

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
$KUBECTL rollout status deploy/ollama-llama3 -n llms-ollama --timeout=120s || true
$KUBECTL rollout status deploy/ollama-qwen32b -n llms-ollama --timeout=120s || true
$KUBECTL rollout status deploy/ollama-embed-0 -n llms-ollama --timeout=120s || true
$KUBECTL rollout status deploy/ollama-planner-cpu-0 -n llms-ollama --timeout=120s || true

# Wait for worker-node pods to be ready
echo "Waiting for worker-node Ollama pods to be ready..."
for IDX in 2 3 4 5 6 7 8 9; do
  $KUBECTL rollout status deploy/ollama-embed-${IDX} -n llms-ollama --timeout=120s || true
done
for IDX in 2 3 4 5; do
  $KUBECTL rollout status deploy/ollama-planner-cpu-${IDX} -n llms-ollama --timeout=120s || true
done

# Seed models from local registry into PVCs
if [[ "${SKIP_SEEDING:-false}" != "true" ]]; then
    echo "Seeding LLM models from local registry..."
    bash "$SCRIPT_DIR/seed-models.sh"
fi