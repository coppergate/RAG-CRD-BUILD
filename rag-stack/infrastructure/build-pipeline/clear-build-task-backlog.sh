#!/bin/bash
# clear-build-task-backlog.sh - clear backlog for build orchestrator subscription
# Run on hierophant

set -Eeuo pipefail

KUBECTL="/home/k8s/kube/kubectl"
export KUBECONFIG="/home/k8s/kube/config/kubeconfig"
PULSAR_NAMESPACE="${PULSAR_NAMESPACE:-apache-pulsar}"
TOPIC="${TOPIC:-persistent://public/default/build-tasks}"
SUBSCRIPTION="${SUBSCRIPTION:-build-orchestrator-sub}"

find_pod() {
  local pod=""
  for sel in "component=toolset" "app.kubernetes.io/component=toolset" "component=broker" "app.kubernetes.io/component=broker"; do
    pod=$($KUBECTL get pods -n "$PULSAR_NAMESPACE" -l "$sel" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    [[ -n "$pod" ]] && { echo "$pod"; return 0; }
  done
  pod=$($KUBECTL get pods -n "$PULSAR_NAMESPACE" -o name 2>/dev/null | grep -E 'toolset|broker' | head -n1 | cut -d/ -f2 || true)
  [[ -n "$pod" ]] && { echo "$pod"; return 0; }
  return 1
}

POD="$(find_pod || true)"
if [[ -z "$POD" ]]; then
  echo "ERROR: could not find Pulsar toolset/broker pod in namespace $PULSAR_NAMESPACE"
  exit 1
fi

$KUBECTL wait --for=condition=Ready "pod/$POD" -n "$PULSAR_NAMESPACE" --timeout=120s >/dev/null

echo "Using pod: $POD"
echo "Topic: $TOPIC"
echo "Subscription: $SUBSCRIPTION"

# Try commands across Pulsar versions.
if $KUBECTL exec -n "$PULSAR_NAMESPACE" "$POD" -- sh -lc \
  'A=/pulsar/bin/pulsar-admin; [ -x "$A" ] || A=/opt/pulsar/bin/pulsar-admin; exec "$A" topics clear-backlog -s "'$SUBSCRIPTION'" "'$TOPIC'"'; then
  echo "Backlog cleared with clear-backlog."
  exit 0
fi

if $KUBECTL exec -n "$PULSAR_NAMESPACE" "$POD" -- sh -lc \
  'A=/pulsar/bin/pulsar-admin; [ -x "$A" ] || A=/opt/pulsar/bin/pulsar-admin; exec "$A" topics skip-all-messages -s "'$SUBSCRIPTION'" "'$TOPIC'"'; then
  echo "Backlog cleared with skip-all-messages."
  exit 0
fi

echo "ERROR: could not clear backlog with known pulsar-admin commands."
exit 1
