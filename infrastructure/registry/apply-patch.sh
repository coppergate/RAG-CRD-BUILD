#!/bin/bash
TALOS_BIN="/home/k8s/talos/talosctl"
TALOS_CONFIG="/home/k8s/talos/config/talosconfig"
PATCH_FILE="/mnt/hegemon-share/share/code/complete-build/infrastructure/registry/talos-registry-patch.json"

# Standard nodes to patch (Control Plane + Workers + Inference)
NODES=("10.0.0.200" "10.0.0.201" "10.0.0.202" "10.0.0.110" "10.0.0.111" "10.0.0.112" "10.0.0.113" "10.0.0.120" "10.0.0.121")

# If KUBECONFIG is available, try to get current node IPs dynamically to ensure full coverage
if [[ -f "$KUBECONFIG" ]]; then
  DYNAMIC_IPS=$($TALOS_BIN --talosconfig $TALOS_CONFIG config info --output jsonpath='{.nodes[*]}' 2>/dev/null || echo "")
  if [[ -n "$DYNAMIC_IPS" ]]; then
    NODES=($DYNAMIC_IPS)
  fi
fi

for ip in "${NODES[@]}"; do
  echo "Patching node $ip..."
  # Use JSON patch (RFC 6902) which is more reliable for targeting specific config paths
  TALOSCONFIG=$TALOS_CONFIG $TALOS_BIN -n $ip patch machineconfig --patch "@$PATCH_FILE"
done

echo "Registry patches applied. NOTE: Talos may require a node reboot for registry mirrors to take effect in containerd."
