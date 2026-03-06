#!/usr/bin/env bash
# verify-install.sh — Verification sequence for Apache Pulsar deployment
#
# Performs:
#  1) RBAC presence check (nodes → create serviceaccounts/token in apache-pulsar)
#  2) Rollout readiness checks for ZK/BookKeeper/Recovery/Broker/Proxy
#  3) Functional smoke test using pulsar-toolset (produce + consume)
#  4) Optional: run broader RAG integration tests job if RUN_RAG_TESTS=true
#
# To be executed on host: hierophant

set -Eeuo pipefail

NS="apache-pulsar"
KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
REQ_TIMEOUT="${REQ_TIMEOUT:-30s}"

# Optional: run extended RAG tests (in namespace rag-system) if set to "true"
RUN_RAG_TESTS="${RUN_RAG_TESTS:-false}"
RAG_TEST_JOB_FILE="/mnt/hegemon-share/share/code/complete-build/rag-stack/tests/test-job.yaml"

log()  { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
warn() { log "WARN: $*"; }
fail() { log "ERROR: $*"; exit 1; }

require_bin() { [[ -x "$1" ]] || fail "Required binary not found or not executable: $1"; }
require_read() { [[ -r "$1" ]] || fail "Required file not readable: $1"; }

rollout_wait() {
  local kind="$1"; shift
  local name="$1"; shift
  local ns="$1"; shift
  local timeout="${1:-15m}"
  log "Waiting for $kind/$name in $ns to be Ready (timeout $timeout)"
  if ! $KUBECTL -n "$ns" rollout status "$kind/$name" --timeout="$timeout"; then
    warn "$kind/$name did not become Ready within $timeout"
    return 1
  fi
}

smoke_test_with_toolset() {
  local ns="$1"
  # Locate toolset pod
  local pod
  pod=$($KUBECTL -n "$ns" get pods -l app=pulsar,component=toolset -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$pod" ]]; then
    warn "pulsar-toolset pod not found in $ns — skipping smoke test"
    return 2
  fi
  log "Using toolset pod: $pod for smoke test"
  # Choose a unique topic for the test
  local topic
  topic="persistent://public/default/smoke-$(date +%s)-$RANDOM"
  local url
  url="pulsar://pulsar-proxy.${NS}.svc.cluster.local:6650"
  # Try both common client locations
  local client_cmd='P=/pulsar/bin/pulsar-client; test -x "$P" || P=/opt/pulsar/bin/pulsar-client; echo "$P"'
  local client_path
  client_path=$($KUBECTL -n "$ns" exec "$pod" -- sh -lc "$client_cmd" 2>/dev/null | tail -n1 || true)
  if [[ -z "$client_path" ]]; then
    warn "Unable to determine pulsar-client path inside toolset pod — skipping smoke test"
    return 2
  fi
  log "pulsar-client at: $client_path"
  # Produce one message
  log "Producing 1 message to $topic via $url"
  if ! $KUBECTL -n "$ns" exec "$pod" -- sh -lc "$client_path produce -m 'hello-from-smoke' -n 1 --service-url '$url' '$topic'"; then
    warn "Produce failed"
    return 1
  fi
  # Consume one message
  log "Consuming 1 message from $topic via $url (timeout 20s)"
  if ! $KUBECTL -n "$ns" exec "$pod" -- sh -lc "timeout 20s $client_path consume --service-url '$url' -s smoke-sub -n 1 '$topic'"; then
    warn "Consume failed"
    return 1
  fi
  log "Smoke test PASSED for topic: $topic"
}

main() {
  log "Pre-flight checks"
  require_bin "$KUBECTL"
  require_read "$KUBECONFIG"
  $KUBECTL --request-timeout="$REQ_TIMEOUT" version || true

  log "1) RBAC presence check in namespace $NS"
  if ! $KUBECTL -n "$NS" get role nodes-serviceaccount-token-creator -o name >/dev/null 2>&1; then
    fail "Missing Role nodes-serviceaccount-token-creator in $NS"
  fi
  if ! $KUBECTL -n "$NS" get rolebinding nodes-serviceaccount-token-creator-binding -o name >/dev/null 2>&1; then
    fail "Missing RoleBinding nodes-serviceaccount-token-creator-binding in $NS"
  fi
  log "RBAC verified"

  log "2) Rollout readiness for core components"
  local ok=true
  rollout_wait statefulset pulsar-zookeeper "$NS" || ok=false
  rollout_wait statefulset pulsar-bookie "$NS" || ok=false
  rollout_wait statefulset pulsar-recovery "$NS" || ok=false
  rollout_wait statefulset pulsar-broker "$NS" || ok=false
  rollout_wait statefulset pulsar-proxy "$NS" || ok=false

  log "Current pod status:"
  $KUBECTL --request-timeout="$REQ_TIMEOUT" -n "$NS" get pods -o wide || true

  log "3) Inspect Pulsar init job (if present)"
  if $KUBECTL -n "$NS" get job pulsar-pulsar-init >/dev/null 2>&1; then
    $KUBECTL -n "$NS" describe job pulsar-pulsar-init | sed -n '1,200p' || true
    $KUBECTL -n "$NS" logs job/pulsar-pulsar-init --all-containers --tail=200 || true
  else
    log "Init job pulsar-pulsar-init not found (may not be used by this chart version)"
  fi

  log "4) Pulsar smoke test using toolset"
  if ! smoke_test_with_toolset "$NS"; then
    warn "Smoke test did not fully pass; investigate broker/proxy/toolset logs."
    ok=false
  fi

  if [[ "$RUN_RAG_TESTS" == "true" ]]; then
    log "5) Running extended RAG integration tests job from: $RAG_TEST_JOB_FILE"
    if [[ -r "$RAG_TEST_JOB_FILE" ]]; then
      # Cleanup any previous job with the same name/namespace declared in the YAML
      local job_ns job_name
      job_ns=$(awk '/namespace:/ {print $2}' "$RAG_TEST_JOB_FILE" | head -n1 || true)
      job_name=$(awk '/name:/ {print $2}' "$RAG_TEST_JOB_FILE" | head -n1 || true)
      if [[ -n "$job_ns" && -n "$job_name" ]]; then
        $KUBECTL -n "$job_ns" delete job "$job_name" --ignore-not-found=true || true
      fi
      $KUBECTL apply -f "$RAG_TEST_JOB_FILE"
      if [[ -n "$job_ns" && -n "$job_name" ]]; then
        $KUBECTL -n "$job_ns" wait --for=condition=complete job/"$job_name" --timeout=15m || ok=false
        $KUBECTL -n "$job_ns" logs job/"$job_name" --all-containers --tail=400 || true
      else
        warn "Could not parse job name/namespace from $RAG_TEST_JOB_FILE; skipping wait/logs"
      fi
    else
      warn "RAG test job file not readable: $RAG_TEST_JOB_FILE"
    fi
  fi

  if [[ "$ok" == true ]]; then
    log "Verification SUCCESS"
    exit 0
  else
    fail "Verification FAILED — see warnings above"
  fi
}

main "$@"
