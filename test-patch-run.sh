#!/bin/bash
cat <<EOF > /tmp/test-patch.yaml
spec:
  machine:
    registries:
      config:
        test.home:
          insecure: true
EOF
/home/k8s/talos/talosctl --talosconfig /home/k8s/talos/config/talosconfig -n 10.0.0.200 patch machineconfig --patch-file /tmp/test-patch.yaml
rm /tmp/test-patch.yaml
