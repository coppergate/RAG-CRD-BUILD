#!/bin/bash
# metrics-server.sh - Setup Kubernetes Metrics Server
# Run on hierophant
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"

echo "--- Initializing Kubernetes Metrics Server Setup ---"

# 1. Apply metrics-server manifest
$KUBECTL apply -f "$SCRIPT_DIR/metrics-server.yaml"

# 2. Wait for deployment to be ready
echo "--- Waiting for metrics-server deployment to be ready ---"
$KUBECTL rollout status deployment/metrics-server -n kube-system

echo "--- Kubernetes Metrics Server Setup Complete ---"
$KUBECTL get apiservice v1beta1.metrics.k8s.io
