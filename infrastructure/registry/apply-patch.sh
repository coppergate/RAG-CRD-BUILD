#!/bin/bash
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# Single source of truth for network + registry addressing (flat-LAN design).
source "$REPO_DIR/config/network.env"

TALOS_BIN="/home/k8s/talos/talosctl"
TALOS_CONFIG="/home/k8s/talos/config/talosconfig"
PATCH_FILE="/mnt/hegemon-share/share/code/kubernetes-setup/configs/talos-registry-patch.yaml"

# Standard nodes to patch (Control Plane + Workers), flat-LAN static IPs from
# config/network.env: control-0/1/2 = 192.168.5.11-13, worker-0..3 = .21-.24.
# The external GPU inference node (INFERENCE_IPS) is patched during enrollment.
NODES=(${CP_IPS} ${WORKER_IPS})

# If KUBECONFIG is available, try to get current node IPs dynamically to ensure full coverage
if [[ -f "$KUBECONFIG" ]]; then
  DYNAMIC_IPS=$($TALOS_BIN --talosconfig $TALOS_CONFIG config info --output jsonpath='{.nodes[*]}' 2>/dev/null || echo "")
  if [[ -n "$DYNAMIC_IPS" ]]; then
    NODES=($DYNAMIC_IPS)
  fi
fi

for ip in "${NODES[@]}"; do
  echo "Patching node $ip..."
  # Clear existing extraHostEntries to avoid duplicates/stale entries
  TALOSCONFIG=$TALOS_CONFIG $TALOS_BIN -n $ip patch machineconfig --patch '[{"op": "replace", "path": "/machine/network/extraHostEntries", "value": []}]'
  # Clear existing registries config to avoid duplicate endpoint accumulation on repeated runs
  TALOSCONFIG=$TALOS_CONFIG $TALOS_BIN -n $ip patch machineconfig --patch '[{"op": "replace", "path": "/machine/registries", "value": {}}]' 2>/dev/null || true
  # Apply the desired registry configuration
  TALOSCONFIG=$TALOS_CONFIG $TALOS_BIN -n $ip patch machineconfig --patch "@$PATCH_FILE"
done

echo "Registry patches applied. NOTE: Talos may require a node reboot for registry mirrors to take effect in containerd."
