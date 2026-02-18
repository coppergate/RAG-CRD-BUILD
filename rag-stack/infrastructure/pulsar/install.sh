#!/bin/bash
# install.sh - Apache Pulsar Installation
# To be executed on host: hierophant

set -e

NAMESPACE="apache-pulsar"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
export PULSAR_INSTALL="$REPO_DIR/infrastructure/pulsar"

echo "--- 1. Preparing Namespace and Cleanup ---"
if $KUBECTL get namespace $NAMESPACE >/dev/null 2>&1; then
    echo "Existing namespace found. Cleaning up Pulsar..."
    helm uninstall pulsar -n $NAMESPACE || true
    $KUBECTL delete pvc --all -n $NAMESPACE || true
    # Wait for PVs to be released and delete them if they stick
    sleep 10
    $KUBECTL get pv | grep Released | awk '{print $1}' | xargs -r $KUBECTL patch pv -p '{"metadata":{"finalizers":null}}' || true
    $KUBECTL get pv | grep Released | awk '{print $1}' | xargs -r $KUBECTL delete pv || true
else
    $KUBECTL create namespace $NAMESPACE
fi

$KUBECTL label --overwrite namespace $NAMESPACE \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/enforce=privileged

echo "--- 1.5. Labeling Nodes for Pulsar ---"
# Ensure only worker nodes (not control-plane) have the required label for Pulsar components
# Using --selector instead of -l to avoid shell interpolation issues with !
$KUBECTL label nodes --selector="!node-role.kubernetes.io/control-plane" rag.role.pulsar-worker=true --overwrite


echo "--- 2. Adding Helm Repos ---"
helm repo add apache https://pulsar.apache.org/charts
helm repo update

echo "--- 3. Installing Pulsar ---"
# Note: Using the localized full-values.yaml which has nodeSelectors for pulsar-worker role
# Pinning to chart version 3.6.0 (Pulsar 3.0.x LTS)
helm install pulsar apache/pulsar \
    --version 3.6.0 \
    --namespace $NAMESPACE \
    --values $PULSAR_INSTALL/full-values.yaml \
    --set volumes.persistence=true \
    --set zookeeper.volumes.persistence=true \
    --set zookeeper.volumes.data.storageClassName=rook-ceph-block \
    --set bookkeeper.volumes.persistence=true \
    --set bookkeeper.volumes.journal.storageClassName=rook-ceph-block \
    --set bookkeeper.volumes.ledgers.storageClassName=rook-ceph-block \
    --set pulsar_manager.volumes.persistence=true \
    --set pulsar_manager.volumes.data.storageClassName=rook-ceph-block \
    --timeout 60m \
    --wait

echo "--- 4. Exposing Pulsar Manager admin ---"
$KUBECTL expose service pulsar-pulsar-manager-admin \
    --name=pulsar-manager-lb \
    --port=8080 \
    --target-port=9527 \
    --type=LoadBalancer \
    -n $NAMESPACE

echo "Pulsar Installation Complete."
