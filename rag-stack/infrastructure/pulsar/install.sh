#!/bin/bash
# install.sh - Apache Pulsar Installation
# To be executed on host: hierophant

set -euo pipefail

NAMESPACE="apache-pulsar"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
REPO_DIR="${REPO_DIR:-/mnt/hegemon-share/share/code/complete-build/rag-stack}"
export REPO_DIR
export PULSAR_INSTALL="$REPO_DIR/infrastructure/pulsar"
PULSAR_REMOVE="${PULSAR_REMOVE:-${FRESH_INSTALL:-false}}"

# Journaling (resumable install)
source "${REPO_DIR}/../scripts/journal-helper.sh"
init_journal

log()  { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
warn() { log "WARN: $*"; }
fail() { log "ERROR: $*"; exit 1; }

# Bridge custom journaling to standard journal-helper
mark_done() { mark_step_done "$1"; }
is_done() { is_step_done "$1"; }

# If we are forcibly removing/resetting, clear journal so we don't skip steps incorrectly
if [[ "${PULSAR_REMOVE:-false}" == "true" ]]; then
  log "PULSAR_REMOVE=true detected. Clearing install journal."
  clear_journal
fi

echo "--- 1. Preparing Namespace and Optional Cleanup ---"
if ! is_done 10.ns; then
  if $KUBECTL get namespace $NAMESPACE >/dev/null 2>&1; then
      if [ "$PULSAR_REMOVE" = "true" ]; then
          log "Removing existing Pulsar release and PVCs in namespace $NAMESPACE..."
          helm uninstall pulsar -n $NAMESPACE || true
          $KUBECTL delete pvc --all -n $NAMESPACE || true
          # Wait for PVs to be released and delete them if they stick
          sleep 10
          $KUBECTL get pv | grep Released | awk '{print $1}' | xargs -r $KUBECTL patch pv -p '{"metadata":{"finalizers":null}}' || true
          $KUBECTL get pv | grep Released | awk '{print $1}' | xargs -r $KUBECTL delete pv || true
      else
          log "Namespace $NAMESPACE exists. Skipping removal (set PULSAR_REMOVE=true to force cleanup)."
      fi
  else
      $KUBECTL create namespace $NAMESPACE
  fi
  # Always ensure labels are set (idempotent)
  $KUBECTL label --overwrite namespace $NAMESPACE \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    pod-security.kubernetes.io/enforce=privileged
  
  # Inject the registry & Pulsar Root CA ConfigMap
  log "Ensuring registry-ca-cm (combined Registry & Pulsar) in $NAMESPACE..."
  
  # Ensure SAFE_TMP_DIR exists
  mkdir -p "$SAFE_TMP_DIR"
  
  COMBINED_CA="$SAFE_TMP_DIR/combined-ca.crt"
  rm -f "$COMBINED_CA"
  touch "$COMBINED_CA"

  # 1. Extract Registry CA
  if $KUBECTL get secret in-cluster-registry-tls -n container-registry >/dev/null 2>&1; then
      log "Extracting Registry CA from container-registry/in-cluster-registry-tls..."
      $KUBECTL get secret in-cluster-registry-tls -n container-registry -o jsonpath='{.data.ca\.crt}' | base64 --decode >> "$COMBINED_CA"
  else
      # Fallback: Extract from talos patch if source secret is missing
      log "Fallback: Extracting Registry CA from Talos registry patch..."
      CA_B64=$(grep "ca: " "$REPO_DIR/../infrastructure/registry/talos-registry-patch.yaml" | head -n 1 | awk '{print $2}')
      if [ -n "$CA_B64" ]; then
          echo "$CA_B64" | base64 -d >> "$COMBINED_CA"
      fi
  fi

  # 2. Extract Pulsar CA (if available - might not be yet on first install)
  if $KUBECTL get secret pulsar-ca-tls -n apache-pulsar >/dev/null 2>&1; then
      log "Extracting Pulsar CA from apache-pulsar/pulsar-ca-tls..."
      echo "" >> "$COMBINED_CA" # Ensure newline
      $KUBECTL get secret pulsar-ca-tls -n apache-pulsar -o jsonpath='{.data.ca\.crt}' | base64 --decode >> "$COMBINED_CA"
  fi

  if [ -s "$COMBINED_CA" ]; then
      $KUBECTL create configmap registry-ca-cm -n $NAMESPACE --from-file=ca.crt="$COMBINED_CA" --dry-run=client -o yaml | $KUBECTL apply -f -
      # Also create 'registry-ca' for legacy compatibility
      $KUBECTL create configmap registry-ca -n $NAMESPACE --from-file=ca.crt="$COMBINED_CA" --dry-run=client -o yaml | $KUBECTL apply -f -
  else
      warn "Could not find any CA to inject into $NAMESPACE."
  fi

  # Clean up the temporary cert file
  rm -f "$COMBINED_CA"

  mark_done 10.ns
else
  log "Step 1 already completed (journal 10.ns)"
fi

echo "--- 1.5. Labeling Nodes for Pulsar ---"
if ! is_done 15.nodeLabels; then
  # Ensure only worker nodes (not control-plane or inference nodes) have the required label for Pulsar components
  WORKER_NODES=$($KUBECTL get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^worker' || echo "")
  if [[ -n "$WORKER_NODES" ]]; then
      for node in $WORKER_NODES; do
          $KUBECTL label node "$node" rag.role.pulsar-worker=true --overwrite
      done
  fi
  mark_done 15.nodeLabels
else
  log "Node labeling already completed (journal 15.nodeLabels)"
fi

echo "--- 1.6. Applying namespaced RBAC for kubelet token requests ---"
if ! is_done 16.rbac; then
  cat <<'YAML' | $KUBECTL --validate=false apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nodes-serviceaccount-token-creator
  namespace: apache-pulsar
rules:
- apiGroups: [""]
  resources: ["serviceaccounts/token"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nodes-serviceaccount-token-creator-binding
  namespace: apache-pulsar
subjects:
- kind: Group
  name: system:nodes
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: nodes-serviceaccount-token-creator
  apiGroup: rbac.authorization.k8s.io
YAML
  mark_done 16.rbac
else
  log "RBAC already applied (journal 16.rbac)"
fi


echo "--- 2. Adding Helm Repos ---"
if ! is_done 20.helmRepo; then
  helm repo add apache https://pulsar.apache.org/charts || true
  helm repo update || true
  mark_done 20.helmRepo
else
  log "Helm repo step already completed (journal 20.helmRepo)"
fi

echo "--- 3. Installing Pulsar ---"
if ! is_done 30.helmInstall; then
  # Use upgrade --install to support resume/idempotency
  helm upgrade --install pulsar apache/pulsar \
      --version 3.6.0 \
      --namespace $NAMESPACE \
      --values $PULSAR_INSTALL/full-values.yaml \
      --set zookeeper.podMonitor.enabled=false,bookkeeper.podMonitor.enabled=false,autorecovery.podMonitor.enabled=false,broker.podMonitor.enabled=false,proxy.podMonitor.enabled=false \
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
  mark_done 30.helmInstall
else
  log "Helm install/upgrade already completed (journal 30.helmInstall)"
fi

# Update CA ConfigMap now that Pulsar CA might be newly created/rotated
log "Updating registry-ca-cm with latest combined CAs..."
mkdir -p "$SAFE_TMP_DIR"
COMBINED_CA="$SAFE_TMP_DIR/combined-ca.crt"
rm -f "$COMBINED_CA"
touch "$COMBINED_CA"
if $KUBECTL get secret in-cluster-registry-tls -n container-registry >/dev/null 2>&1; then
    $KUBECTL get secret in-cluster-registry-tls -n container-registry -o jsonpath='{.data.ca\.crt}' | base64 --decode >> "$COMBINED_CA"
fi
if $KUBECTL get secret pulsar-ca-tls -n apache-pulsar >/dev/null 2>&1; then
    echo "" >> "$COMBINED_CA"
    $KUBECTL get secret pulsar-ca-tls -n apache-pulsar -o jsonpath='{.data.ca\.crt}' | base64 --decode >> "$COMBINED_CA"
fi
if [ -s "$COMBINED_CA" ]; then
    $KUBECTL create configmap registry-ca-cm -n $NAMESPACE --from-file=ca.crt="$COMBINED_CA" --dry-run=client -o yaml | $KUBECTL apply -f -
    $KUBECTL create configmap registry-ca -n $NAMESPACE --from-file=ca.crt="$COMBINED_CA" --dry-run=client -o yaml | $KUBECTL apply -f -
fi
rm -f "$COMBINED_CA"

echo "--- 4. Exposing Pulsar Manager admin ---"
if ! is_done 40.exposePM; then
  if ! $KUBECTL -n $NAMESPACE get svc pulsar-manager-lb >/dev/null 2>&1; then
    $KUBECTL expose service pulsar-pulsar-manager-admin \
        --name=pulsar-manager-lb \
        --port=8080 \
        --target-port=9527 \
        --type=LoadBalancer \
        -n $NAMESPACE || true
  else
    log "Service pulsar-manager-lb already exists"
  fi
  mark_done 40.exposePM
else
  log "Expose PM step already completed (journal 40.exposePM)"
fi

echo "--- 5. Validating BookKeeper Cluster Metadata (instance ID) ---"
# Optional reset flow: if FORCE_REINIT=true is exported, we will clean local bookie data after ensuring metadata exists.
# Non-interactive, uses service names and parses config from within a bookkeeper pod.

# Wait for ZK and BK statefulsets to be ready (best-effort; ignore errors to avoid hard-fail)
if ! is_done 50.waitCore; then
  set +e
  $KUBECTL -n $NAMESPACE rollout status statefulset/pulsar-zookeeper --timeout=10m || true
  # Chart names its BK statefulset 'pulsar-bookie'
  $KUBECTL -n $NAMESPACE rollout status statefulset/pulsar-bookie --timeout=10m || true
  set -e
  mark_done 50.waitCore
else
  log "Wait core step already completed (journal 50.waitCore)"
fi

if ! is_done 60.bkMeta; then
  # Pick a pod owned by the 'pulsar-bookie' StatefulSet (robust to label changes)
  BK_POD=$($KUBECTL -n $NAMESPACE get pods -l app=pulsar,component=bookie --no-headers -o custom-columns=:metadata.name | head -n1 2>/dev/null || true)
  if [ -n "$BK_POD" ]; then
    echo "Using bookkeeper pod: $BK_POD to verify metadata"
    $KUBECTL -n $NAMESPACE exec -i "$BK_POD" -- bash -lc '
    set -e
    BK=/pulsar/bin/bookkeeper; test -x "$BK" || BK=/opt/bookkeeper/bin/bookkeeper;
    CONF=/pulsar/conf/bookkeeper.conf; test -f "$CONF" || CONF=/opt/bookkeeper/conf/bookkeeper.conf;
    ZK=$(grep -E "^(zkServers)\s*=|^zkServers=" -m1 "$CONF" | awk -F= "{print \$2}" | xargs);
    ROOT=$(grep -E "^(zkLedgersRootPath|ledgersRootPath)\s*=|^(zkLedgersRootPath|ledgersRootPath)=" -m1 "$CONF" | awk -F= "{print \$2}" | xargs);
    echo "Detected ZK=$ZK ROOT=$ROOT";
    IID=$($BK shell whatisinstanceid -l "$ZK" -r "$ROOT" 2>/dev/null || true);
    if [ -z "$IID" ]; then
      echo "No instance ID found in ZooKeeper. Initializing new cluster metadata...";
      $BK shell initnewcluster -l "$ZK" -r "$ROOT";
      IID=$($BK shell whatisinstanceid -l "$ZK" -r "$ROOT" 2>/dev/null || true);
      echo "Instance ID after init: ${IID:-none}";
    else
      echo "Existing instance ID: $IID";
    fi
    '

    # Optional: clean local bookie data if FORCE_REINIT=true
    if [ "${FORCE_REINIT:-false}" = "true" ]; then
      echo "FORCE_REINIT=true detected. Cleaning local bookie data across pods..."
      for POD in $($KUBECTL -n $NAMESPACE get pods -l app=pulsar,component=bookie --no-headers -o custom-columns=:metadata.name); do
        echo "Cleaning bookie on pod: $POD"
        $KUBECTL -n $NAMESPACE exec -i "$POD" -- bash -lc '
        set -e
        BK=/pulsar/bin/bookkeeper; test -x "$BK" || BK=/opt/bookkeeper/bin/bookkeeper;
        echo "Running bookieformat -force -deleteCookie (non-interactive)";
        $BK shell bookieformat -nonInteractive -force -deleteCookie || $BK shell bookieformat -force -deleteCookie
        '
        # recycle pod to ensure fresh cookie
        $KUBECTL -n $NAMESPACE delete pod "$POD" --wait=false || true
      done
      echo "Waiting for bookkeeper statefulset to become Ready after cleanup..."
      set +e
      $KUBECTL -n $NAMESPACE rollout status statefulset/pulsar-bookie --timeout=10m || true
      set -e
    fi
  else
    echo "WARNING: No BookKeeper pod found to verify/initialize metadata. Skipping post-install check."
  fi
  mark_done 60.bkMeta
else
  log "BookKeeper metadata step already completed (journal 60.bkMeta)"
fi

echo "--- 6. Post-Install Verification ---"
# Verify that critical Pulsar components are actually running before declaring success.
# This catches cases where Helm --wait succeeded but pods subsequently crashed.
VERIFY_TIMEOUT=120
VERIFY_POLL=10
VERIFY_ELAPSED=0
VERIFY_OK=false

while [[ "$VERIFY_ELAPSED" -lt "$VERIFY_TIMEOUT" ]]; do
    ZK_READY=$($KUBECTL get pods -n $NAMESPACE -l component=zookeeper --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    BK_READY=$($KUBECTL get pods -n $NAMESPACE -l component=bookie --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    BR_READY=$($KUBECTL get pods -n $NAMESPACE -l component=broker --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    PX_READY=$($KUBECTL get pods -n $NAMESPACE -l component=proxy --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [[ "$ZK_READY" -ge 1 && "$BK_READY" -ge 1 && "$BR_READY" -ge 1 && "$PX_READY" -ge 1 ]]; then
        VERIFY_OK=true
        break
    fi
    log "Waiting for Pulsar components (ZK=$ZK_READY BK=$BK_READY BR=$BR_READY PX=$PX_READY)..."
    sleep "$VERIFY_POLL"
    VERIFY_ELAPSED=$((VERIFY_ELAPSED + VERIFY_POLL))
done

if [[ "$VERIFY_OK" == "true" ]]; then
    log "Pulsar verification PASSED: ZK=$ZK_READY BK=$BK_READY BR=$BR_READY PX=$PX_READY"
else
    log "ERROR: Pulsar verification FAILED after ${VERIFY_TIMEOUT}s."
    log "Pod status:"
    $KUBECTL get pods -n $NAMESPACE -o wide 2>&1 || true
    log "Recent events:"
    $KUBECTL get events -n $NAMESPACE --sort-by=.lastTimestamp 2>&1 | tail -30 || true
    fail "Pulsar components are not running. Aborting."
fi

echo "Pulsar Installation Complete. All components verified running."
# Do NOT clear journal here — let the parent script (setup-complete.sh) manage
# journal lifecycle via clear_all_journals on FRESH_INSTALL.
# This prevents re-running all Pulsar steps when setup-all.sh or other scripts
# call install.sh again in the same session.
