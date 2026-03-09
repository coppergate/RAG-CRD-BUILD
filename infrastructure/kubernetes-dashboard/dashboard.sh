#!/bin/bash
# dashboard.sh - Setup Kubernetes Dashboard
# Run on hierophant

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
HELM="helm --kubeconfig /home/k8s/kube/config/kubeconfig"

echo "--- Initializing Kubernetes Dashboard Setup ---"

# 1. Add Helm Repository
$HELM repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ || true
$HELM repo update kubernetes-dashboard || true

# Check if repo was added, if not try alternative
if ! $HELM search repo kubernetes-dashboard/kubernetes-dashboard > /dev/null 2>&1; then
    echo "Official repo failed, trying alternative/direct URL..."
fi

# 2. Install Dashboard via Helm
# We put it in the kubernetes-dashboard namespace
$KUBECTL create namespace kubernetes-dashboard --dry-run=client -o yaml | $KUBECTL apply -f -

# Label the namespace for privileged security profile
$KUBECTL label --overwrite namespace kubernetes-dashboard \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged

# Use the older but stable recommended manifest if Helm is being problematic
# Or try a different repository for the chart.
# Some environments use 'helm.sh/charts' or similar.
# Actually, let's try to use the manifest-based approach as a fallback if Helm fails.

$HELM upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --repo https://kubernetes.github.io/dashboard/ \
  --namespace kubernetes-dashboard \
  --set kong.enabled=true \
  --set metrics-server.enabled=true \
  --set app.ingress.enabled=true \
  --set app.ingress.hosts={dashboard.hierocracy.home} \
  --set app.ingress.ingressClassName=traefik \
  --set app.ingress.annotations."traefik.ingress.kubernetes.io/router.entrypoints"=web || {
    echo "Helm installation failed, applying YAML manifests instead..."
    $KUBECTL apply -f "$SCRIPT_DIR/../vendor/kubernetes-dashboard-v2.7.0.yaml"
  }

# 3. Create Service Account and ClusterRoleBinding for Admin access
cat <<ADMIN_EOF | $KUBECTL apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: dashboard.hierocracy.home
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
ADMIN_EOF

# 4. Create LoadBalancer Service
$KUBECTL apply -f "$SCRIPT_DIR/dashboard-lb.yaml"

# 5. Create persistent token secret
$KUBECTL apply -f "$SCRIPT_DIR/admin-token-secret.yaml"

echo "--- Kubernetes Dashboard Setup Complete ---"
echo "Access at: http://dashboard.hierocracy.home"
echo "Admin Token (save this - persistent):"
$KUBECTL -n kubernetes-dashboard get secret admin-user-token -o jsonpath='{.data.token}' | base64 --decode
echo ""
