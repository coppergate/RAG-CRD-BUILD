#!/bin/bash
cat <<EOF > /tmp/test-kind-patch.yaml
apiVersion: config.talos.dev/v1alpha1
kind: MachineConfigs
metadata:
  annotations:
    patched: "true"
EOF
/home/k8s/talos/talosctl --talosconfig /home/k8s/talos/config/talosconfig -n 10.0.0.200 patch MachineConfigs --patch-file /tmp/test-kind-patch.yaml
rm /tmp/test-kind-patch.yaml
