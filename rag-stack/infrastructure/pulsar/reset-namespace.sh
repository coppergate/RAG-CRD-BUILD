#!/usr/bin/env bash
# reset-namespace.sh — Full namespace reset for Apache Pulsar (Option A)
#
# This script removes the entire apache-pulsar namespace, cleans up any
# lingering PVs that were bound to it, reapplies the required RBAC for
# kubelets (system:nodes) to create ServiceAccount tokens, and then
# re-installs Pulsar using the project installer.
#
# IMPORTANT:
# - Run this on host: hierophant
# - Non‑interactive; uses strict timeouts

set -Eeuo pipefail

NS="apache-pulsar"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
REQ_TIMEOUT="${REQ_TIMEOUT:-20s}"

# By default, use the repo path mounted on hierophant
REPO_DIR="${REPO_DIR:-/mnt/hegemon-share/share/code/complete-build/rag-stack}"
INSTALL_SH="$REPO_DIR/infrastructure/pulsar/install.sh"

log()  { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
warn() { log "WARN: $*"; }
fail() { log "ERROR: $*"; exit 1; }

require_bin() {
  [[ -x "$1" ]] || fail "Required binary not found or not executable: $1"
}

require_read() {
  [[ -r "$1" ]] || fail "Required file not readable: $1"
}

wait_ns_deleted() {
  local ns="$1"; local timeout_s="${2:-300}"; local start
  start=$(date +%s)
  while true; do
    if ! $KUBECTL get ns "$ns" >/dev/null 2>&1; then
      log "Namespace '$ns' is deleted."
      return 0
    fi
    local now elapsed
    now=$(date +%s); elapsed=$(( now - start ))
    if (( elapsed > timeout_s )); then
      warn "Timed out waiting for namespace '$ns' to delete (>${timeout_s}s). Proceeding anyway."
      return 1
    fi
    sleep 3
  done
}

log "Pre-flight checks"
require_bin "$KUBECTL"
require_read "$KUBECONFIG"
require_read "$INSTALL_SH"

log "kubectl version (client/server if reachable)"
$KUBECTL --request-timeout="$REQ_TIMEOUT" version || true

log "Step 1: Delete namespace '$NS' (if exists)"
if $KUBECTL get ns "$NS" >/dev/null 2>&1; then
  $KUBECTL --request-timeout="$REQ_TIMEOUT" delete ns "$NS" --wait=false || true
  sleep 5
else
  log "Namespace '$NS' not present. Skipping delete."
fi

log "Step 2: Cleanup PVs that referenced namespace '$NS'"
PVS=$($KUBECTL get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="apache-pulsar")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
if [[ -n "${PVS}" ]]; then
  while IFS= read -r pv; do
    [[ -n "$pv" ]] || continue
    log "Patching finalizers and deleting PV: $pv"
    $KUBECTL patch pv "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge || true
    $KUBECTL delete pv "$pv" || true
  done <<< "$PVS"
else
  log "No PVs referencing namespace '$NS' were found."
fi

log "Step 3: Wait for namespace deletion to complete (up to 5m)"
wait_ns_deleted "$NS" 300 || true

log "Step 4: Recreate namespace '$NS'"
$KUBECTL --request-timeout="$REQ_TIMEOUT" create ns "$NS" || true

log "Step 5: Apply nodes RBAC (system:nodes → create serviceaccounts/token in $NS)"
cat <<'YAML' | $KUBECTL --request-timeout="$REQ_TIMEOUT" --validate=false apply -f -
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

log "Step 6: Re-install Pulsar via installer"
export REPO_DIR
"$INSTALL_SH"

log "Step 7: Post-install status"
$KUBECTL --request-timeout="$REQ_TIMEOUT" -n "$NS" get pods -o wide || true

log "Done. If pods remain Pending/Init, describe one failing pod and share logs."
