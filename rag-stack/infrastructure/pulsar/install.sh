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
      CA_B64=$(grep "ca: " "/mnt/hegemon-share/share/code/kubernetes-setup/configs/talos-registry-patch.yaml" | head -n 1 | awk '{print $2}')
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
---
# The pulsar-bookkeeper-verify-clusterid init container runs a Kubernetes
# client that watches ConfigMaps for service discovery. Without this Role
# the informer cache sync times out and the bookie pods never start.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pulsar-bookie-configmap-reader
  namespace: apache-pulsar
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets", "endpoints", "services", "pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pulsar-bookie-configmap-reader-binding
  namespace: apache-pulsar
subjects:
- kind: ServiceAccount
  name: pulsar
  namespace: apache-pulsar
roleRef:
  kind: Role
  name: pulsar-bookie-configmap-reader
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
  # --wait is intentionally omitted: the chart creates a cert-manager selfsigning
  # chain (SelfSigned Issuer -> CA cert -> CA Issuer -> component certs). With --wait,
  # Helm blocks on pod readiness, but pods can't start until their cert secrets exist,
  # and cert-manager can't finish issuing until the CA Issuer is reconciled. This race
  # causes the context deadline to be hit. We gate on certs explicitly in step 35 instead.
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
      --timeout 20m
  mark_done 30.helmInstall
else
  log "Helm install/upgrade already completed (journal 30.helmInstall)"
fi

echo "--- 3.5. Waiting for cert-manager certificates to be issued ---"
if ! is_done 35.certWait; then
  # The selfsigning chain takes time: SelfSigned Issuer -> CA cert -> CA Issuer -> component certs.
  # All component secrets (broker-certs, bookie-certs, etc.) must exist before pods can start.
  cert_timeout=300
  cert_interval=15
  cert_elapsed=0
  log "Waiting for all Pulsar TLS certificates to reach Ready state (up to ${cert_timeout}s)..."
  while (( cert_elapsed < cert_timeout )); do
    log "  Polling certificates... (${cert_elapsed}s/${cert_timeout}s)"
    # Use --request-timeout to prevent hanging when API server is under load during install storm.
    # NOTE: '|| true' inside the pipe absorbs kubectl failures before wc/grep see them.
    # Without it, pipefail causes both the pipe command AND '|| echo 0' to produce output,
    # resulting in variables containing two values (e.g. "0\n0") which breaks (( )).
    total=$({ $KUBECTL get certificate -n $NAMESPACE --no-headers \
        --request-timeout=20s 2>/dev/null || true; } | wc -l)
    ready=$({ $KUBECTL get certificate -n $NAMESPACE \
        --request-timeout=20s \
        -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
        2>/dev/null || true; } | grep -c "^True$" || true)
    if (( total > 0 && ready >= total )); then
      log "All $total Pulsar certificates are Ready"
      break
    fi
    log "  Certificates: ${ready}/${total} Ready — waiting ${cert_interval}s..."
    sleep "$cert_interval"
    (( cert_elapsed += cert_interval )) || true
    if (( cert_elapsed >= cert_timeout )); then
      log "WARNING: Not all certificates became Ready within ${cert_timeout}s — current state:"
      $KUBECTL get certificate -n $NAMESPACE --request-timeout=20s 2>/dev/null || true
    fi
  done
  mark_done 35.certWait
else
  log "Cert wait step already completed (journal 35.certWait)"
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

echo "--- 4.5. Initializing BookKeeper cluster metadata ---"
# MUST complete before step 50 waits on bookie StatefulSet readiness.
# Bookie pods have a verify-clusterid init container that blocks until the BookKeeper
# instance ID exists in ZooKeeper. initnewcluster writes this ID. If it hasn't run,
# every bookie pod is stuck in Init:0/2 forever and the rollout wait never resolves.
# We use the toolset pod (no bookie dependency) and wait for both ZK and toolset
# to be accessible before running the command.
if ! is_done 45.bkMetaInit; then
  # 1. Wait for ZooKeeper StatefulSet — initnewcluster must be able to connect to ZK
  log "Waiting for ZooKeeper StatefulSet to be Ready (up to 15m)..."
  set +e
  $KUBECTL -n $NAMESPACE rollout status statefulset/pulsar-zookeeper --timeout=15m \
    || log "WARNING: ZK rollout wait timed out — attempting initnewcluster anyway"
  set -e

  # 2. Wait for toolset-0 to be Running
  log "Waiting for pulsar-toolset-0 to be Running (up to 5m)..."
  ts_elapsed=0
  while (( ts_elapsed < 300 )); do
    ts_phase=$($KUBECTL -n $NAMESPACE get pod pulsar-toolset-0 \
        --request-timeout=15s \
        -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$ts_phase" == "Running" ]] && break
    log "  toolset-0 phase=${ts_phase:-unknown} — waiting 10s... (${ts_elapsed}s/300s)"
    sleep 10; (( ts_elapsed += 10 )) || true
  done

  # 3. Initialize cluster metadata
  TOOLSET_POD=$($KUBECTL -n $NAMESPACE get pod pulsar-toolset-0 \
      -o jsonpath='{.metadata.name}' 2>/dev/null || true)
  if [ -n "$TOOLSET_POD" ]; then
    log "Running BookKeeper cluster metadata check/init via $TOOLSET_POD..."
    $KUBECTL -n $NAMESPACE exec -i "$TOOLSET_POD" -- bash -lc '
    BK=/pulsar/bin/bookkeeper
    CONF=/pulsar/conf/bookkeeper.conf
    ZK=$(grep -E "^zkServers=" -m1 "$CONF" | cut -d= -f2 | xargs)
    ROOT=$(grep -E "^(zkLedgersRootPath|ledgersRootPath)=" -m1 "$CONF" | cut -d= -f2 | xargs)
    echo "ZK=$ZK  ROOT=$ROOT"
    # Note: BookKeeper 4.16.6 does NOT support -l/-r flags on whatisinstanceid/initnewcluster.
    # The CLI reads zkServers and zkLedgersRootPath from bookkeeper.conf automatically.
    IID=$($BK shell whatisinstanceid 2>/dev/null | grep -Ev "JAVA_HOME|INFO|WARN" | tail -1 || true)
    if [ -z "$IID" ]; then
      echo "No instance ID found — running initnewcluster..."
      $BK shell initnewcluster
      IID=$($BK shell whatisinstanceid 2>/dev/null | grep -Ev "JAVA_HOME|INFO|WARN" | tail -1 || true)
      echo "Instance ID after init: ${IID:-none}"
    else
      echo "Existing instance ID: $IID"
    fi
    ' || log "WARNING: initnewcluster via toolset failed — bookie init containers may stall"
  else
    log "WARNING: pulsar-toolset-0 not found — bookie verify-clusterid init containers may stall"
  fi
  mark_done 45.bkMetaInit
else
  log "BookKeeper metadata init already completed (journal 45.bkMetaInit)"
fi

echo "--- 5. Validating BookKeeper Cluster Metadata (instance ID) ---"
# Optional reset flow: if FORCE_REINIT=true is exported, we will clean local bookie data after ensuring metadata exists.
# Non-interactive, uses service names and parses config from within a bookkeeper pod.

# ZK is already waited on in step 45. Wait only for bookie here.
if ! is_done 50.waitCore; then
  set +e
  # Chart names its BK statefulset 'pulsar-bookie'
  $KUBECTL -n $NAMESPACE rollout status statefulset/pulsar-bookie --timeout=20m || true
  set -e
  mark_done 50.waitCore
else
  log "Wait core step already completed (journal 50.waitCore)"
fi

if ! is_done 60.bkMeta; then
  # Verify metadata via the toolset pod — always Running, no Init-phase ambiguity.
  # Bookie pods may still be in Init phase at this point; exec-ing into them targets
  # the main container which doesn't exist yet, causing "container not found" errors.
  # BookKeeper 4.16.6 does NOT support -l/-r flags; conf is read from bookkeeper.conf.
  TOOLSET_POD=$($KUBECTL -n $NAMESPACE get pod pulsar-toolset-0 \
      -o jsonpath='{.metadata.name}' 2>/dev/null || true)
  if [ -n "$TOOLSET_POD" ]; then
    log "Verifying BookKeeper cluster metadata via $TOOLSET_POD..."
    $KUBECTL -n $NAMESPACE exec -i "$TOOLSET_POD" -- bash -lc '
    BK=/pulsar/bin/bookkeeper
    IID=$($BK shell whatisinstanceid 2>/dev/null | grep -Ev "JAVA_HOME|INFO|WARN" | tail -1 || true)
    if [ -z "$IID" ]; then
      echo "No instance ID found — running initnewcluster..."
      $BK shell initnewcluster
      IID=$($BK shell whatisinstanceid 2>/dev/null | grep -Ev "JAVA_HOME|INFO|WARN" | tail -1 || true)
      echo "Instance ID after init: ${IID:-none}"
    else
      echo "Existing instance ID: $IID"
    fi
    ' || log "WARNING: metadata verification via toolset failed"

    # Optional: clean local bookie data if FORCE_REINIT=true
    if [ "${FORCE_REINIT:-false}" = "true" ]; then
      echo "FORCE_REINIT=true detected. Cleaning local bookie data across pods..."
      for POD in $($KUBECTL -n $NAMESPACE get pods -l app=pulsar,component=bookie \
          --field-selector=status.phase=Running --no-headers -o custom-columns=:metadata.name); do
        echo "Cleaning bookie on pod: $POD"
        $KUBECTL -n $NAMESPACE exec -i "$POD" -- bash -lc '
        BK=/pulsar/bin/bookkeeper
        echo "Running bookieformat -nonInteractive -force -deleteCookie"
        $BK shell bookieformat -nonInteractive -force -deleteCookie || $BK shell bookieformat -force -deleteCookie
        '
        $KUBECTL -n $NAMESPACE delete pod "$POD" --wait=false || true
      done
      set +e
      $KUBECTL -n $NAMESPACE rollout status statefulset/pulsar-bookie --timeout=10m || true
      set -e
    fi
  else
    log "WARNING: pulsar-toolset-0 not found — skipping post-install metadata check"
  fi
  mark_done 60.bkMeta
else
  log "BookKeeper metadata step already completed (journal 60.bkMeta)"
fi

echo "--- 6. Post-Install Verification ---"
# Verify that critical Pulsar components are actually running before declaring success.
# This catches cases where Helm --wait succeeded but pods subsequently crashed.
VERIFY_TIMEOUT=600
VERIFY_POLL=30
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
