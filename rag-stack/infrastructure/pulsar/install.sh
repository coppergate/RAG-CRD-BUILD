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
JOURNAL_DIR="${INSTALL_JOURNAL_DIR:-/var/lib/complete-build/journal/pulsar}"
mkdir -p "$JOURNAL_DIR"
chmod 777 "$JOURNAL_DIR" 2>/dev/null || true
STEP_PREFIX="pulsar"

log()  { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
warn() { log "WARN: $*"; }
fail() { log "ERROR: $*"; exit 1; }

mark_done() {
  local step="$1"
  touch "$JOURNAL_DIR/${STEP_PREFIX}.$step.done"
  chmod 666 "$JOURNAL_DIR/${STEP_PREFIX}.$step.done" 2>/dev/null || true
}
is_done() {
  local step="$1"; [[ -f "$JOURNAL_DIR/${STEP_PREFIX}.$step.done" ]];
}

# If we are forcibly removing/resetting, clear journal so we don't skip steps incorrectly
if [ "$PULSAR_REMOVE" = "true" ] && [ -d "$JOURNAL_DIR" ]; then
  log "PULSAR_REMOVE=true detected. Clearing install journal at $JOURNAL_DIR"
  rm -f "$JOURNAL_DIR/${STEP_PREFIX}."*.done 2>/dev/null || true
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
  
  # Inject the registry Root CA ConfigMap
  log "Injecting registry-ca-cm into $NAMESPACE..."
  if $KUBECTL get configmap registry-ca-cm -n container-registry >/dev/null 2>&1; then
      $KUBECTL get configmap registry-ca-cm -n container-registry -o yaml | \
      sed "s/namespace: container-registry/namespace: $NAMESPACE/" | \
      $KUBECTL apply -f -
  else
      # Fallback: Extract from talos patch if source CM is missing
      CA_B64=$(grep "ca: " "$REPO_DIR/../infrastructure/registry/talos-registry-patch.yaml" | head -n 1 | awk '{print $2}')
      if [ -n "$CA_B64" ]; then
          log "Creating registry-ca-cm from Talos patch..."
          echo "$CA_B64" | base64 -d > /tmp/ca.crt
          $KUBECTL create configmap registry-ca-cm -n $NAMESPACE --from-file=ca.crt=/tmp/ca.crt --dry-run=client -o yaml | $KUBECTL apply -f -
          rm /tmp/ca.crt
      else
          warn "Could not find registry-ca-cm or Talos patch to inject CA."
      fi
  fi

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
      --set "broker.extraVolumes[0].name=registry-ca,broker.extraVolumes[0].configMap.name=registry-ca-cm" \
      --set "broker.extraVolumeMounts[0].name=registry-ca,broker.extraVolumeMounts[0].mountPath=/etc/ssl/certs/ca.crt,broker.extraVolumeMounts[0].subPath=ca.crt" \
      --set "proxy.extraVolumes[0].name=registry-ca,proxy.extraVolumes[0].configMap.name=registry-ca-cm" \
      --set "proxy.extraVolumeMounts[0].name=registry-ca,proxy.extraVolumeMounts[0].mountPath=/etc/ssl/certs/ca.crt,proxy.extraVolumeMounts[0].subPath=ca.crt" \
      --set "pulsar_manager.extraVolumes[0].name=registry-ca,pulsar_manager.extraVolumes[0].configMap.name=registry-ca-cm" \
      --set "pulsar_manager.extraVolumeMounts[0].name=registry-ca,pulsar_manager.extraVolumeMounts[0].mountPath=/etc/ssl/certs/ca.crt,pulsar_manager.extraVolumeMounts[0].subPath=ca.crt" \
      --set "toolset.extraVolumes[0].name=registry-ca,toolset.extraVolumes[0].configMap.name=registry-ca-cm" \
      --set "toolset.extraVolumeMounts[0].name=registry-ca,toolset.extraVolumeMounts[0].mountPath=/etc/ssl/certs/ca.crt,toolset.extraVolumeMounts[0].subPath=ca.crt" \
      --timeout 60m \
      --wait
  mark_done 30.helmInstall
else
  log "Helm install/upgrade already completed (journal 30.helmInstall)"
fi

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
  BK_POD=$($KUBECTL -n $NAMESPACE get pods -o jsonpath='{range .items[?(@.metadata.ownerReferences[0].kind=="StatefulSet" && @.metadata.ownerReferences[0].name=="pulsar-bookie")]}{.metadata.name}{"\n"}{end}' | head -n1 2>/dev/null || true)
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
      for POD in $($KUBECTL -n $NAMESPACE get pods -o jsonpath='{range .items[?(@.metadata.ownerReferences[0].kind=="StatefulSet" && @.metadata.ownerReferences[0].name=="pulsar-bookie")]}{.metadata.name}{"\n"}{end}'); do
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
      $KUBECTL -n $NAMESPACE rollout status statefulset/pulsar-bookkeeper --timeout=10m || true
      set -e
    fi
  else
    echo "WARNING: No BookKeeper pod found to verify/initialize metadata. Skipping post-install check."
  fi
  mark_done 60.bkMeta
else
  log "BookKeeper metadata step already completed (journal 60.bkMeta)"
fi

echo "Pulsar Installation Complete. BookKeeper cluster metadata validated."
