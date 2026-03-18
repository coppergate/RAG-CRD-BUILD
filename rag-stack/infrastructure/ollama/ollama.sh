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

# Inject Registry CA ConfigMap
echo "--- Injecting Registry CA into llms-ollama ---"
# Source journal-helper for SAFE_TMP_DIR and REPO_DIR (if available)
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$REPO_DIR/../scripts/journal-helper.sh"
mkdir -p "$SAFE_TMP_DIR"

if $KUBECTL get secret in-cluster-registry-tls -n container-registry >/dev/null 2>&1; then
    echo "Extracting CA from container-registry/in-cluster-registry-tls..."
    $KUBECTL get secret in-cluster-registry-tls -n container-registry -o jsonpath='{.data.ca\.crt}' | base64 --decode > "$SAFE_TMP_DIR/ca.crt"
    $KUBECTL create configmap registry-ca-cm -n llms-ollama --from-file=ca.crt="$SAFE_TMP_DIR/ca.crt" --dry-run=client -o yaml | $KUBECTL apply -f -
    # Also create 'registry-ca' for legacy compatibility
    $KUBECTL create configmap registry-ca -n llms-ollama --from-file=ca.crt="$SAFE_TMP_DIR/ca.crt" --dry-run=client -o yaml | $KUBECTL apply -f -
else
    echo "Fallback: Extracting CA from Talos registry patch..."
    CA_B64=$(grep "ca: " "$REPO_DIR/../infrastructure/registry/talos-registry-patch.yaml" | head -n 1 | awk '{print $2}')
    if [ -n "$CA_B64" ]; then
        echo "$CA_B64" | base64 -d > "$SAFE_TMP_DIR/ca.crt"
        $KUBECTL create configmap registry-ca-cm -n llms-ollama --from-file=ca.crt="$SAFE_TMP_DIR/ca.crt" --dry-run=client -o yaml | $KUBECTL apply -f -
        # Also create 'registry-ca' for legacy compatibility
        $KUBECTL create configmap registry-ca -n llms-ollama --from-file=ca.crt="$SAFE_TMP_DIR/ca.crt" --dry-run=client -o yaml | $KUBECTL apply -f -
    else
        echo "WARNING: Could not find CA to inject into llms-ollama."
    fi
fi
rm -f "$SAFE_TMP_DIR/ca.crt"
  
$KUBECTL label nodes inference-0 role=inference-node llm-model=llama3.1 --overwrite
$KUBECTL label nodes inference-1 role=inference-node llm-model=granite3.1-dense-8b --overwrite

# Deploy using the OCI artifacts pushed to the local registry
# We revert image.repository to the base Ollama image and specify models to pull from the local registry.
REGISTRY="registry.hierocracy.home:5000"

$HELM upgrade --install ollama-llama3 otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values.yaml" \
  --set nodeSelector."llm-model"=llama3.1 \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6" \
  --set ollama.models.pull="{llama3.1}" \
  --set ollama.models.run="{llama3.1}"

$HELM upgrade --install ollama-granite31-8b otwld/ollama --namespace llms-ollama -f "$SCRIPT_DIR/values.yaml" \
  --set nodeSelector."llm-model"=granite3.1-dense-8b \
  --set image.repository="${REGISTRY}/ollama/ollama" \
  --set image.tag="0.15.6" \
  --set ollama.models.pull="{granite3.1-dense:8b}" \
  --set ollama.models.run="{granite3.1-dense:8b}"
$KUBECTL expose deployment ollama-llama3 --name=ollama --port=11434 --target-port=11434 --type=LoadBalancer -n llms-ollama || true
$KUBECTL expose deployment ollama-granite31-8b --name=ollama-code --port=11434 --target-port=11434 --type=LoadBalancer -n llms-ollama || true