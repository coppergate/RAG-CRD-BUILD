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

should_run_step() {
  local step_name="$1"
  local verify_cmd="$2"

  if is_step_done "$step_name"; then
    if [[ -z "$verify_cmd" ]] || eval "$verify_cmd" >/dev/null 2>&1; then
      return 1
    fi
    echo "Journal has '$step_name' but live verification failed. Re-running step..."
    return 0
  fi

  if [[ -n "$verify_cmd" ]] && eval "$verify_cmd" >/dev/null 2>&1; then
    echo "Step '$step_name' is not in journal but live verification succeeded. Skipping."
    mark_step_done "$step_name"
    return 1
  fi

  return 0
}

if should_run_step "timescaledb-node-labels" "$KUBECTL get nodes -l rag.role.timescaledb-node=true -o name 2>/dev/null | grep -q '^node/'"; then
  echo "[TSDB] Labeling TimescaleDB nodes"
  $KUBECTL label --overwrite nodes worker-0 rag.role.timescaledb-node=true || true
  $KUBECTL label --overwrite nodes worker-1 rag.role.timescaledb-node=true || true
  $KUBECTL label --overwrite nodes worker-2 rag.role.timescaledb-node=true || true
  $KUBECTL label --overwrite nodes worker-3 rag.role.timescaledb-node=true || true
  mark_step_done "timescaledb-node-labels"
fi

if should_run_step "cnpg-operator-apply" "$KUBECTL -n cnpg-system get deploy >/dev/null 2>&1"; then
  echo "--- 1. Installing CloudNativePG Operator (v1.25.0) ---"
  $KUBECTL apply -f "$TIMESCALEDB_INSTALL/cnpg-1.25.0.yaml" \
    --server-side --force-conflicts
  mark_step_done "cnpg-operator-apply"
fi

if should_run_step "cnpg-operator-wait" "$KUBECTL -n cnpg-system wait --for=condition=available deployment/cloudnative-pg-controller-manager --timeout=1s >/dev/null 2>&1"; then
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

if should_run_step "timescaledb-namespace" "$KUBECTL get namespace $NAMESPACE >/dev/null 2>&1"; then
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

if should_run_step "timescaledb-tls" "$KUBECTL get certificate timescaledb-server-cert -n $NAMESPACE >/dev/null 2>&1"; then
  echo "--- 2.5. Creating TimescaleDB TLS Certificates ---"
  $KUBECTL apply -f $TIMESCALEDB_INSTALL/timescaledb-tls.yaml
  # Wait for the certificate to be ready
  echo "Waiting for TimescaleDB server certificate to be ready..."
  $KUBECTL wait --for=condition=Ready certificate/timescaledb-server-cert -n $NAMESPACE --timeout=60s
  mark_step_done "timescaledb-tls"
fi

if should_run_step "timescaledb-cluster-apply" "$KUBECTL get cluster -n $NAMESPACE timescaledb >/dev/null 2>&1"; then
  echo "--- 3. Deploying TimescaleDB Cluster ---"
  $KUBECTL apply -f $TIMESCALEDB_INSTALL/cluster.yaml --server-side --force-conflicts
  mark_step_done "timescaledb-cluster-apply"
fi

if ! $KUBECTL get secret timescaledb-app -n $NAMESPACE >/dev/null 2>&1; then
  echo "Waiting for timescaledb-app secret in namespace '$NAMESPACE'..."
  retries=0
  max_retries=120
  until $KUBECTL get secret timescaledb-app -n $NAMESPACE >/dev/null 2>&1; do
    if [ "$retries" -ge "$max_retries" ]; then
      echo "ERROR: timescaledb-app secret was not created in $NAMESPACE after waiting."
      exit 1
    fi
    sleep 5
    retries=$((retries + 1))
  done
fi

echo "Waiting for TimescaleDB instances to be ready (this can take several minutes)..."
echo "Check status with: $KUBECTL get cluster -n $NAMESPACE && $KUBECTL -n $NAMESPACE get pods -l cnpg.io/cluster=timescaledb"

clear_journal

echo "TimescaleDB Installation Triggered."
