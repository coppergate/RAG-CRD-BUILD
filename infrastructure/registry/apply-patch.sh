#!/bin/bash
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# Single source of truth for network + registry addressing (flat-LAN design).
source "$REPO_DIR/config/network.env"

TALOS_BIN="/home/k8s/talos/talosctl"
TALOS_CONFIG="/home/k8s/talos/config/talosconfig"
# The patch applied here MUST be the one maintained by the live build path.
# new-setup-external-gpu is the only current build (confirmed 2026-09-13), and
# its copy is the maintained one: correct registry IP, no dead 10.0.0.1:5000
# mirrors, and TLS via insecureSkipVerify so a regenerated bootstrap cert can
# never break pulls.
#
# kubernetes-setup/configs/talos-registry-patch.yaml was used here until
# 2026-09-13 and still pins the PRE-FLAT-LAN registry IP 172.20.1.26. Because
# this script clears extraHostEntries and machine.registries before applying,
# running it with that file actively WROTE the dead IP onto every control plane
# and worker, and every image pull then timed out on 172.20.1.26:5000. That file
# is still read elsewhere for its `ca:` field (in-cluster registry-ca-cm trust),
# so it is left in place — just not applied to nodes.
PATCH_FILE="/mnt/hegemon-share/share/code/kubernetes-setup/new-setup-external-gpu/configs/talos-registry-patch.yaml"

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
