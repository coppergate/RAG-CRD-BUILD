#!/bin/bash
# Script to generate a JSON patch for Talos registries with TLS.
# Must be run on hierophant to access the Root CA.

ROOT_CA_PEM=$(cat /home/junie/certs/rootCA.crt)
# The 'ca' field in registries.config.tls.ca expects base64 of the PEM.
ROOT_CA_B64=$(cat /home/junie/certs/rootCA.crt | base64 -w 0)

# Build the JSON patch as an RFC 6902 JSON array.
# Using 'replace' for /machine/registries as it's cleaner.
# Using 'add' for arrays like extraCerts or extraHostEntries to set them entirely.
cat <<EOF > /tmp/talos-registry-patch.json
[
  {
    "op": "replace",
    "path": "/machine/install/extraCerts",
    "value": [
      $(echo "$ROOT_CA_PEM" | jq -Rs .)
    ]
  },
  {
    "op": "replace",
    "path": "/machine/network/extraHostEntries",
    "value": [
      {"ip": "10.0.0.1", "aliases": ["hierophant.hierocracy.home", "registry.hierocracy.home", "hierophant"]}
    ]
  },
  {
    "op": "replace",
    "path": "/machine/registries",
    "value": {
      "mirrors": {
        "docker.io": {"endpoints": ["https://10.0.0.1:5000", "https://registry-1.docker.io"]},
        "quay.io": {"endpoints": ["https://10.0.0.1:5000", "https://quay.io"]},
        "registry.k8s.io": {"endpoints": ["https://10.0.0.1:5000", "https://registry.k8s.io"]},
        "ghcr.io": {"endpoints": ["https://10.0.0.1:5000", "https://ghcr.io"]},
        "10.0.0.1:5000": {"endpoints": ["https://10.0.0.1:5000"]},
        "hierophant.hierocracy.home:5000": {"endpoints": ["https://10.0.0.1:5000"]},
        "registry.hierocracy.home:5000": {"endpoints": ["https://10.0.0.1:5000"]}
      },
      "config": {
        "10.0.0.1:5000": {"tls": {"ca": "$ROOT_CA_B64"}},
        "hierophant.hierocracy.home:5000": {"tls": {"ca": "$ROOT_CA_B64"}},
        "registry.hierocracy.home:5000": {"tls": {"ca": "$ROOT_CA_B64"}}
      }
    }
  }
]
EOF

# Move it to the project directory.
mv /tmp/talos-registry-patch.json /mnt/hegemon-share/share/code/complete-build/infrastructure/registry/talos-registry-patch.json
