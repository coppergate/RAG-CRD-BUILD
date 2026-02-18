#!/bin/bash
TALOS_BIN="/home/k8s/talos/talosctl"
TALOS_CONFIG="/home/k8s/talos/config/talosconfig"
PATCH_FILE="/mnt/hegemon-share/share/code/complete-build/infrastructure/registry/talos-registry-patch.yaml"

NODES=("172.20.0.100" "172.20.0.101" "172.20.0.102" "172.20.0.110" "172.20.0.111" "172.20.0.112" "172.20.0.113" "172.20.0.120" "172.20.0.121")

for ip in "${NODES[@]}"; do
  echo "Patching node $ip..."
  TALOSCONFIG=$TALOS_CONFIG $TALOS_BIN -n $ip patch machineconfig --patch "@$PATCH_FILE"
done
