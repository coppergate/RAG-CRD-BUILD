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
  
$KUBECTL label nodes inference-0 role=inference-node llm-model=llama3.1 --overwrite
$KUBECTL label nodes inference-1 role=inference-node llm-model=granite3.1-dense-8b --overwrite

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
$HELM upgrade --install ollama-llama3 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values.yaml" \
  --set nodeSelector."llm-model"=llama3.1 \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"
$HELM upgrade --install ollama-granite31-8b otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values.yaml" \
  --set nodeSelector."llm-model"=granite3.1-dense-8b \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"
$KUBECTL expose deployment ollama-llama3 --name=ollama --port=11434 --target-port=11434 --type=LoadBalancer -n llms-ollama || true
$KUBECTL expose deployment ollama-granite31-8b --name=ollama-code --port=11434 --target-port=11434 --type=LoadBalancer -n llms-ollama || true

# Deploy CPU-only embedding Ollama on each inference node.
# Each node gets its own embed pod; both are selected by the ollama-embed service.
# To run a different embedding model on a node in the future, change the values-embed.yaml
# or add a per-node override at install time.
$HELM upgrade --install ollama-embed-0 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values-embed.yaml" \
  --set nodeSelector."llm-model"=llama3.1 \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"
$HELM upgrade --install ollama-embed-1 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values-embed.yaml" \
  --set nodeSelector."llm-model"=granite3.1-dense-8b \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"

# Deploy CPU-only alternate planner Ollama on each inference node.
# Both pods are selected by the ollama-planner-cpu service.
# Uses the llama3 prompt format — compatible with the existing planner PromptType.
$HELM upgrade --install ollama-planner-cpu-0 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values-planner-cpu.yaml" \
  --set nodeSelector."llm-model"=llama3.1 \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"
$HELM upgrade --install ollama-planner-cpu-1 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values-planner-cpu.yaml" \
  --set nodeSelector."llm-model"=granite3.1-dense-8b \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6"

# Wait for pods to be ready before seeding models
echo "Waiting for Ollama pods to be ready..."
$KUBECTL rollout status deploy/ollama-llama3 -n llms-ollama --timeout=120s || true
$KUBECTL rollout status deploy/ollama-granite31-8b -n llms-ollama --timeout=120s || true
$KUBECTL rollout status deploy/ollama-embed-0 -n llms-ollama --timeout=120s || true
$KUBECTL rollout status deploy/ollama-embed-1 -n llms-ollama --timeout=120s || true
$KUBECTL rollout status deploy/ollama-planner-cpu-0 -n llms-ollama --timeout=120s || true
$KUBECTL rollout status deploy/ollama-planner-cpu-1 -n llms-ollama --timeout=120s || true

# Seed models from local registry into PVCs
if [[ "${SKIP_SEEDING:-false}" != "true" ]]; then
    echo "Seeding LLM models from local registry..."
    bash "$SCRIPT_DIR/seed-models.sh"
fi