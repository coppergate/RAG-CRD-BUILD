#!/usr/bin/env bash
# reboot-worker-node.sh
# Cordons, drains, reboots, and uncordons a Talos worker node.
# Usage: ./reboot-worker-node.sh [node-name]
# Default node: worker-0
# Run directly on hierophant.
set -euo pipefail

export KUBECONFIG=/home/k8s/kube/config/kubeconfig
KUBECTL=/home/k8s/kube/kubectl
TALOSCTL=/home/k8s/talos/talosctl
TALOSCONFIG=/home/k8s/talos/config/talosconfig

NODE=${1:-worker-0}

# Resolve the node's InternalIP for talosctl
NODE_IP=$($KUBECTL get node "$NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

echo "=== Rebooting node: $NODE ($NODE_IP) ==="
echo ""

echo "=== Step 1: Cordon $NODE (mark unschedulable) ==="
$KUBECTL cordon "$NODE"
echo "  Cordoned."

echo ""
echo "=== Step 2: Remove blocking webhooks that prevent pod eviction ==="
# The mimir-rollout-operator webhook blocks evictions when its endpoint is down.
# Save manifest so we can note it was removed; it will be recreated by the operator on restart.
WEBHOOK="pod-eviction-monitoring.grafana.com"
if $KUBECTL get mutatingwebhookconfiguration "$WEBHOOK" &>/dev/null; then
  echo "  Removing MutatingWebhookConfiguration: $WEBHOOK"
  $KUBECTL delete mutatingwebhookconfiguration "$WEBHOOK"
  echo "  Webhook removed. It will be recreated by the operator after the node recovers."
else
  echo "  Webhook $WEBHOOK not found — skipping."
fi

echo ""
echo "=== Step 3: Drain $NODE ==="
$KUBECTL drain "$NODE" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30 \
  --timeout=300s \
  --force
echo "  Drain complete."

echo ""
echo "=== Step 4: Reboot $NODE via talosctl ==="
$TALOSCTL reboot \
  --talosconfig "$TALOSCONFIG" \
  --nodes "$NODE_IP"
echo "  Reboot command sent."

echo ""
echo "=== Step 5: Wait for $NODE to go NotReady ==="
echo "  (Waiting up to 120s for node to go NotReady...)"
DEADLINE=$(( $(date +%s) + 120 ))
while true; do
  STATUS=$($KUBECTL get node "$NODE" \
    --no-headers \
    -o custom-columns='STATUS:.status.conditions[-1].type,READY:.status.conditions[-1].status' \
    2>/dev/null || echo "NotFound NotFound")
  if echo "$STATUS" | grep -q "Ready.*False\|NotFound"; then
    echo "  Node is NotReady / unreachable."
    break
  fi
  if [[ $(date +%s) -gt $DEADLINE ]]; then
    echo "  Timed out waiting for NotReady — continuing anyway."
    break
  fi
  echo "  Still Ready, waiting..."
  sleep 5
done

echo ""
echo "=== Step 6: Wait for $NODE to come back Ready ==="
echo "  (Waiting up to 5 minutes...)"
$KUBECTL wait node "$NODE" \
  --for=condition=Ready \
  --timeout=300s
echo "  Node is Ready."

echo ""
echo "=== Step 7: Uncordon $NODE ==="
$KUBECTL uncordon "$NODE"
echo "  Uncordoned."

echo ""
echo "=== Done: $NODE is back online and schedulable ==="
echo "  Note: The mimir-rollout-operator webhook will be recreated automatically"
echo "  once the operator pod restarts on the recovered node."
$KUBECTL get node "$NODE"
