#!/bin/bash
TALOS_BIN="/home/k8s/talos/talosctl"
TALOS_CONFIG="/home/k8s/talos/config/talosconfig"
PATCH_FILE="/mnt/hegemon-share/share/code/complete-build/infrastructure/registry/talos-registry-patch.yaml"

# Standard nodes to patch
NODES=("172.20.0.100" "172.20.0.101" "172.20.0.102" "172.20.0.110" "172.20.0.111" "172.20.0.112" "172.20.0.113" "172.20.0.120" "172.20.0.121")

# If KUBECONFIG is available, try to get current node IPs dynamically to ensure full coverage
if [[ -f "$KUBECONFIG" ]]; then
  DYNAMIC_IPS=$($TALOS_BIN --talosconfig $TALOS_CONFIG config info --output jsonpath='{.nodes[*]}' 2>/dev/null || echo "")
  if [[ -n "$DYNAMIC_IPS" ]]; then
    NODES=($DYNAMIC_IPS)
  fi
fi

for ip in "${NODES[@]}"; do
  echo "Patching node $ip..."
  # Use YAML patch (most robust for multi-doc configs)
  TALOSCONFIG=$TALOS_CONFIG $TALOS_BIN -n $ip patch machineconfig --patch "@$PATCH_FILE"
done

echo "Registry patches applied. NOTE: Talos may require a node reboot for registry mirrors to take effect in containerd."
