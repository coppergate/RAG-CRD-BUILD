#!/bin/bash
cat <<EOF > /tmp/test-type-patch.yaml
kind: MachineConfigs.config.talos.dev
metadata:
  annotations:
    patched: "true"
EOF
/home/k8s/talos/talosctl --talosconfig /home/k8s/talos/config/talosconfig -n 10.0.0.200 patch MachineConfigs --patch-file /tmp/test-type-patch.yaml
rm /tmp/test-type-patch.yaml
