#!/usr/bin/env bash
# bootstrap-metadata.sh — Initialize Pulsar tenants, namespaces, and topics used by RAG
# Run on hierophant. Requires kubectl path and KUBECONFIG per guidelines.

set -Eeuo pipefail

NS="apache-pulsar"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
REQ_TIMEOUT="20s"

log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

[[ -x "$KUBECTL" ]] || fail "kubectl not found at $KUBECTL"
[[ -r "$KUBECONFIG" ]] || fail "kubeconfig not readable at $KUBECONFIG"

log "Locating pulsar-toolset pod"
TOOLSET_POD=$($KUBECTL -n "$NS" get pods -l app=pulsar,component=toolset -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[[ -n "$TOOLSET_POD" ]] || fail "pulsar-toolset pod not found in namespace $NS"
log "Using toolset pod: $TOOLSET_POD"

ADMIN="/pulsar/bin/pulsar-admin"; ALT="/opt/pulsar/bin/pulsar-admin"

run_admin() {
  # Build a safely-quoted argument string for inner shell
  local cmd_quoted=""
  local a
  for a in "$@"; do
    local q
    printf -v q '%q' "$a"
    cmd_quoted+=" ${q}"
  done
  # Execute pulsar-admin with the composed arguments inside the toolset pod
  $KUBECTL --request-timeout="$REQ_TIMEOUT" -n "$NS" exec "$TOOLSET_POD" -- sh -lc \
    "A=/pulsar/bin/pulsar-admin; [ -x \$A ] || A=/opt/pulsar/bin/pulsar-admin; exec \"\$A\"${cmd_quoted}"
}

log "Detecting cluster name"
# Try to parse from internal config; fall back to 'pulsar' if not detected
CLUSTER_NAME=$( $KUBECTL -n "$NS" exec "$TOOLSET_POD" -- sh -lc '
  A=/pulsar/bin/pulsar-admin; [ -x "$A" ] || A=/opt/pulsar/bin/pulsar-admin;
  $A brokers get-internal-config 2>/dev/null | sed -n "s/.*\"clusterName\"\s*:\s*\"\([^\"]*\)\".*/\1/p"
' 2>/dev/null | head -n1 )
if [[ -z "$CLUSTER_NAME" ]]; then CLUSTER_NAME="pulsar"; fi
log "Cluster name: $CLUSTER_NAME"

log "Ensuring tenant 'public' exists and allows cluster $CLUSTER_NAME"
run_admin tenants create public --allowed-clusters "$CLUSTER_NAME" || \
run_admin tenants update public --allowed-clusters "$CLUSTER_NAME" || true
run_admin namespaces create public/default || true

log "Ensuring tenant 'rag-pipeline' exists"
if ! run_admin tenants list | tr -d '\r' | grep -q '^rag-pipeline$'; then
  run_admin tenants create rag-pipeline --allowed-clusters "$CLUSTER_NAME"
else
  run_admin tenants update rag-pipeline --allowed-clusters "$CLUSTER_NAME" || true
fi

log "Ensuring namespaces 'rag-pipeline/data' and 'rag-pipeline/operations' exist"
run_admin namespaces create rag-pipeline/data || true
run_admin namespaces create rag-pipeline/operations || true

if [[ "${CREATE_TOPICS:-true}" == "true" ]]; then
  log "Creating commonly used topics (idempotent)"
  # Data flow topics
  for t in \
    persistent://rag-pipeline/data/chat-prompts \
    persistent://rag-pipeline/data/chat-responses \
    persistent://rag-pipeline/data/llm-tasks \
    persistent://rag-pipeline/operations/db-ops \
    persistent://rag-pipeline/operations/qdrant-ops \
    persistent://rag-pipeline/operations/qdrant-ops-results; do
    # Derive namespace from topic to avoid 409 noise when already exists
    tmp=${t#persistent://}
    ns=${tmp%/*}
    if run_admin topics list "$ns" | tr -d '\r' | grep -Fxq "$t"; then
      log "Topic already present: $t (skip)"
    else
      run_admin topics create "$t" || true
    fi
  done
fi

log "Pulsar metadata bootstrap complete."
