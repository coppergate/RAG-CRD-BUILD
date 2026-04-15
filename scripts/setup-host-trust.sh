#!/bin/bash
# setup-host-trust.sh - Configure host to trust the registry CA
# To be executed on host: hierophant

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PATCH_FILE="/mnt/hegemon-share/share/code/kubernetes-setup/configs/talos-registry-patch.yaml"

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "ERROR: Patch file not found at $PATCH_FILE" >&2
  exit 1
fi

echo "--- Configuring Host Trust for current user ---"

# Extract CA from patch file (first occurrence of ca: field)
# We use grep and head to find the base64 string
CA_DATA=$(grep -oP 'ca: \K[A-Za-z0-9+/=]+' "$PATCH_FILE" | head -n 1)

if [[ -z "$CA_DATA" ]]; then
  echo "ERROR: Could not find CA data in $PATCH_FILE" >&2
  exit 1
fi

CERT_DIR="$HOME/.config/containers/certs.d"
HOSTS=("10.0.0.1:5000" "hierophant:5000" "hierophant.hierocracy.home:5000" "registry.hierocracy.home:5000" "172.20.1.26:5000" "127.0.0.1:5000" "localhost:5000")

for host in "${HOSTS[@]}"; do
  mkdir -p "$CERT_DIR/$host"
  echo "$CA_DATA" | base64 -d > "$CERT_DIR/$host/ca.crt"
  echo "Configured $CERT_DIR/$host/ca.crt"
done

# Also try system trust store if sudo is available (non-interactive check)
if sudo -n true 2>/dev/null; then
  echo "--- Configuring system-wide trust store ---"
  echo "$CA_DATA" | base64 -d > /tmp/hierocracy-root-ca.crt
  sudo cp /tmp/hierocracy-root-ca.crt /etc/pki/ca-trust/source/anchors/
  sudo update-ca-trust
  rm /tmp/hierocracy-root-ca.crt
  echo "System trust store updated."
else
  echo "Skipping system trust store (requires sudo password-less access)."
  echo "User-specific trust in $CERT_DIR should suffice for skopeo and podman."
fi

echo "Host trust configuration complete."
