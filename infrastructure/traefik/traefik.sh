NAMESPACE="traefik"
KUBECTL="/home/k8s/kube/kubectl"

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
helm install traefik traefik/traefik -n $NAMESPACE