#!/bin/bash
# headlamp.sh - Setup Headlamp
# Run on hierophant

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
HELM="helm --kubeconfig /home/k8s/kube/config/kubeconfig"

echo "--- Initializing Headlamp Setup ---"

# Cleanup any previous failed helm installation
$HELM uninstall headlamp -n headlamp 2>/dev/null || true

# Apply static manifest
echo "Applying Headlamp static manifest..."
$KUBECTL apply -f "$SCRIPT_DIR/headlamp.yaml"

# Label the namespace for pod security standards
$KUBECTL label --overwrite namespace headlamp \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged

echo "--- Headlamp Setup Complete ---"
echo "Access at: http://dashboard.hierocracy.home"
echo "Admin Token (save this - persistent):"
$KUBECTL -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 --decode
echo ""
