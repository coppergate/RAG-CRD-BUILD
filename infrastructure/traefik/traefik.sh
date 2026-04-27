NAMESPACE="traefik"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

echo "--- 1. Preparing Namespace ---"
if ! $KUBECTL get namespace $NAMESPACE >/dev/null 2>&1; then
    $KUBECTL create namespace $NAMESPACE
fi

$KUBECTL label --overwrite namespace $NAMESPACE \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/enforce=privileged
  

helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik -n $NAMESPACE \
  --set nodeSelector.role=storage-node \
  --set "additionalArguments={--tracing.otlp=true,--tracing.otlp.grpc.endpoint=otel-collector.monitoring.svc.cluster.local:4317,--tracing.otlp.grpc.insecure=true}" \
  --set logs.general.format=json \
  --set logs.access.enabled=true \
  --set logs.access.format=json