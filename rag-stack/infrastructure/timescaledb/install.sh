#!/bin/bash
# install.sh - TimescaleDB (CloudNativePG) Installation
# To be executed on host: hierophant

set -e

NAMESPACE="timescaledb"
KUBECTL="/home/k8s/kube/kubectl"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR="/mnt/hegemon-share/share/code/complete-build"

export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
export TIMESCALEDB_INSTALL="$REPO_DIR/rag-stack/infrastructure/timescaledb"

# Journaling (resumable)
source "$REPO_DIR/scripts/journal-helper.sh"
init_journal

if ! is_step_done "timescaledb-node-labels"; then
  echo "[TSDB] Labeling TimescaleDB nodes"
  $KUBECTL label --overwrite nodes worker-0 rag.role.timescaledb-node=true || true
  $KUBECTL label --overwrite nodes worker-1 rag.role.timescaledb-node=true || true
  $KUBECTL label --overwrite nodes worker-2 rag.role.timescaledb-node=true || true
  $KUBECTL label --overwrite nodes worker-3 rag.role.timescaledb-node=true || true
  mark_step_done "timescaledb-node-labels"
fi

if ! is_step_done "cnpg-operator-apply"; then
  echo "--- 1. Installing CloudNativePG Operator (v1.25.0) ---"
  $KUBECTL apply -f "$TIMESCALEDB_INSTALL/cnpg-1.25.0.yaml" \
    --server-side --force-conflicts
  mark_step_done "cnpg-operator-apply"
fi

if ! is_step_done "cnpg-operator-wait"; then
  echo "Waiting for CNPG operator namespace to appear..."
  # Wait up to 5 minutes for the namespace and deployment to show up
  NS_TIMEOUT=300
  start_ts=$(date +%s)
  until $KUBECTL get ns cnpg-system >/dev/null 2>&1; do
    if (( $(date +%s) - start_ts > NS_TIMEOUT )); then
      echo "[ERROR] Timeout waiting for namespace cnpg-system to be created by the manifest" >&2
      exit 1
    fi
    sleep 5
  done

  echo "Locating CNPG operator Deployment..."
  DEPLOY="cloudnative-pg-controller-manager"
  # If the expected name is not present yet, try to discover by label
  DPLY_TIMEOUT=300
  start_ts=$(date +%s)
  until $KUBECTL -n cnpg-system get deploy "$DEPLOY" >/dev/null 2>&1; do
    alt=$($KUBECTL -n cnpg-system get deploy -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$alt" ]]; then DEPLOY="$alt"; fi
    if $KUBECTL -n cnpg-system get deploy "$DEPLOY" >/dev/null 2>&1; then break; fi
    if (( $(date +%s) - start_ts > DPLY_TIMEOUT )); then
      echo "[ERROR] Timeout waiting for CNPG Deployment to be created in cnpg-system" >&2
      $KUBECTL -n cnpg-system get deploy || true
      exit 1
    fi
    sleep 5
  done

  echo "Waiting for CNPG operator Deployment/$DEPLOY to become Available..."
  $KUBECTL -n cnpg-system wait --for=condition=available deployment "$DEPLOY" --timeout=300s
  mark_step_done "cnpg-operator-wait"
fi

if ! is_step_done "timescaledb-namespace"; then
  echo "--- 2. Preparing Namespace '$NAMESPACE' ---"
  if ! $KUBECTL get namespace $NAMESPACE >/dev/null 2>&1; then
      $KUBECTL create namespace $NAMESPACE
  fi
  $KUBECTL label --overwrite namespace $NAMESPACE \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    pod-security.kubernetes.io/enforce=privileged
  mark_step_done "timescaledb-namespace"
fi

if ! is_step_done "timescaledb-cluster-apply"; then
  echo "--- 3. Deploying TimescaleDB Cluster ---"
  $KUBECTL apply -f $TIMESCALEDB_INSTALL/cluster.yaml --server-side --force-conflicts
  mark_step_done "timescaledb-cluster-apply"
fi

echo "Waiting for TimescaleDB instances to be ready (this can take several minutes)..."
echo "Check status with: $KUBECTL get cluster -n $NAMESPACE && $KUBECTL -n $NAMESPACE get pods -l cnpg.io/cluster=timescaledb"

clear_journal

echo "TimescaleDB Installation Triggered."
