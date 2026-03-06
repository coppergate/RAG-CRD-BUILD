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