#!/bin/bash
cat <<EOF > /tmp/test-patch-file.yaml
machine:
  registries:
    config:
      test3.home:
        insecure: true
EOF
/home/k8s/talos/talosctl --talosconfig /home/k8s/talos/config/talosconfig -n 10.0.0.200 patch machineconfig --patch-file /tmp/test-patch-file.yaml
rm /tmp/test-patch-file.yaml
