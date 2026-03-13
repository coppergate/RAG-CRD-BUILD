#!/bin/bash
ROOT_CA_PEM=$(ssh -i ~/.ssh/id_hierophant_access junie@hierophant "cat /home/junie/certs/rootCA.crt")
ROOT_CA_B64=$(ssh -i ~/.ssh/id_hierophant_access junie@hierophant "cat /home/junie/certs/rootCA.crt | base64 -w 0")

cat <<EOF > /tmp/fixed-talos-patch.yaml
machine:
  install:
    extraCerts:
      - |
$(echo "$ROOT_CA_PEM" | sed 's/^/        /')
  network:
    extraHostEntries:
      - ip: 10.0.0.1
        aliases:
          - hierophant.hierocracy.home
          - registry.hierocracy.home
          - hierophant
  registries:
    mirrors:
      docker.io:
        endpoints:
          - https://10.0.0.1:5000
          - https://registry-1.docker.io
      quay.io:
        endpoints:
          - https://10.0.0.1:5000
          - https://quay.io
      registry.k8s.io:
        endpoints:
          - https://10.0.0.1:5000
          - https://registry.k8s.io
      ghcr.io:
        endpoints:
          - https://10.0.0.1:5000
          - https://ghcr.io
      10.0.0.1:5000:
        endpoints:
          - https://10.0.0.1:5000
      hierophant.hierocracy.home:5000:
        endpoints:
          - https://10.0.0.1:5000
      registry.hierocracy.home:5000:
        endpoints:
          - https://10.0.0.1:5000
    config:
      10.0.0.1:5000:
        tls:
          ca: $ROOT_CA_B64
      hierophant.hierocracy.home:5000:
        tls:
          ca: $ROOT_CA_B64
      registry.hierocracy.home:5000:
        tls:
          ca: $ROOT_CA_B64
EOF

# Use cat and ssh to write the file back to hierophant at the correct location
cat /tmp/fixed-talos-patch.yaml | ssh -i ~/.ssh/id_hierophant_access junie@hierophant "cat > /mnt/hegemon-share/share/code/complete-build/infrastructure/registry/talos-registry-patch.yaml"
rm /tmp/fixed-talos-patch.yaml
