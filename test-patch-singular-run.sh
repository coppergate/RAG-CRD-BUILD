#!/bin/bash
cat <<EOF > /tmp/test-patch-singular.yaml
machine:
  registries:
    config:
      test4.home:
        insecure: true
EOF
/home/k8s/talos/talosctl --talosconfig /home/k8s/talos/config/talosconfig -n 10.0.0.200 patch MachineConfig --patch-file /tmp/test-patch-singular.yaml
rm /tmp/test-patch-singular.yaml
