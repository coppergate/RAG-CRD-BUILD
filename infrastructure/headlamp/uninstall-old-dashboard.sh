#!/bin/bash
# uninstall-old-dashboard.sh
# Run on hierophant

set -Eeuo pipefail

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
HELM="helm --kubeconfig /home/k8s/kube/config/kubeconfig"

echo "--- Uninstalling Kubernetes Dashboard ---"

$HELM uninstall kubernetes-dashboard -n kubernetes-dashboard || true
$KUBECTL delete namespace kubernetes-dashboard || true
$KUBECTL delete clusterrolebinding admin-user || true

echo "--- Kubernetes Dashboard Uninstalled ---"
