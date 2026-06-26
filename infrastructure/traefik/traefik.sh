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

echo "running upgrade"

helm upgrade --install traefik traefik/traefik -n $NAMESPACE -f - <<EOF
nodeSelector:
  role: storage-node

# Disable Traefik Hub explicitly. The Helm chart installs Hub CRDs by default
# (apiportals.hub.traefik.io, uplinks.hub.traefik.io, etc.) and registers API
# extension handlers for them. Even when Hub is unused, these handlers generate
# 1-2s slow OpenAPI aggregation entries per API server cycle, contributing to
# control plane CPU saturation.
hub:
  enabled: false

experimental:
  otlpLogs: true

log:
  level: INFO
  format: json
  otlp:
    enabled: true
    grpc:
      enabled: true
      endpoint: "otel-collector.monitoring.svc.cluster.local:4317"
      insecure: true

accessLog:
  enabled: true
  format: json
  otlp:
    enabled: true
    grpc:
      enabled: true
      endpoint: "otel-collector.monitoring.svc.cluster.local:4317"
      insecure: true

tracing:
  otlp:
    grpc:
      enabled: true
      endpoint: "otel-collector.monitoring.svc.cluster.local:4317"
      insecure: true
EOF

#helm upgrade --install traefik traefik/traefik -n $NAMESPACE \
#  --set nodeSelector.role=storage-node \
#  --set "additionalArguments={--tracing.otlp=true,--tracing.otlp.grpc.endpoint=otel-collector.monitoring.svc.cluster.local:4317,--tracing.otlp.grpc.insecure=true}" \
#  --set logs.general.format=json \
#  --set logs.access.enabled=true \
#  --set logs.access.format=json
