#!/bin/bash
# setup-host-trust.sh - Configure host to trust the registry CA
# To be executed on host: hierophant
#
# Trust source priority:
#   1. Live cert fetched directly from the bootstrap registry (127.0.0.1:5000)
#   2. CA extracted from the talos registry patch (mkcert CA, used for in-cluster registry)
# Both are installed so the host trusts the bootstrap AND in-cluster registries.

set -uo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Single source of truth for network + registry addressing (flat-LAN design).
source "$REPO_DIR/config/network.env"

PATCH_FILE="/mnt/hegemon-share/share/code/kubernetes-setup/configs/talos-registry-patch.yaml"
CERT_DIR="$HOME/.config/containers/certs.d"
HOSTS=("$REGISTRY_PREFIX" "hierophant:5000" "registry.hierocracy.home:5000" \
       "${REGISTRY_LB_IP}:5000" "127.0.0.1:5000" "localhost:5000")

echo "--- Configuring Host Trust for current user ---"

# --- Source 1: Live cert from the bootstrap registry ---
echo ""
echo "Fetching live cert from bootstrap registry (127.0.0.1:5000)..."
BOOTSTRAP_CERT=""
if openssl s_client -connect 127.0.0.1:5000 -showcerts </dev/null 2>/dev/null \
     | openssl x509 -out /tmp/bootstrap-registry.crt 2>/dev/null; then
  BOOTSTRAP_CERT=/tmp/bootstrap-registry.crt
  echo "  Got: $(openssl x509 -noout -subject -issuer -in $BOOTSTRAP_CERT)"
else
  echo "  Bootstrap registry not reachable — skipping live cert fetch."
fi

# --- Source 2: mkcert CA from talos patch (for in-cluster registry) ---
echo ""
echo "Extracting mkcert CA from talos patch..."
MKCERT_CERT=""
if [[ -f "$PATCH_FILE" ]]; then
  CA_DATA=$(grep -oP 'ca: \K[A-Za-z0-9+/=]+' "$PATCH_FILE" | head -n 1 || true)
  if [[ -n "$CA_DATA" ]]; then
    if echo "$CA_DATA" | base64 -d > /tmp/mkcert-ca.crt; then
      MKCERT_CERT=/tmp/mkcert-ca.crt
      CERT_INFO=$(openssl x509 -noout -subject -issuer -in "$MKCERT_CERT" 2>&1 || echo "  (could not parse cert)")
      echo "  Got: $CERT_INFO"
    else
      echo "  base64 decode failed — skipping mkcert CA."
    fi
  else
    echo "  No CA data found in patch file."
  fi
else
  echo "  Patch file not found: $PATCH_FILE"
fi

if [[ -z "$BOOTSTRAP_CERT" && -z "$MKCERT_CERT" ]]; then
  echo "ERROR: No certificates found from any source." >&2
  exit 1
fi

# --- Install to per-user containers cert dirs ---
echo ""
echo "Installing to user cert dirs ($CERT_DIR)..."
for host in "${HOSTS[@]}"; do
  mkdir -p "$CERT_DIR/$host"
  # Write bootstrap cert first (self-signed), then append mkcert CA if present
  if [[ -n "$BOOTSTRAP_CERT" ]]; then
    cp "$BOOTSTRAP_CERT" "$CERT_DIR/$host/ca.crt"
  fi
  if [[ -n "$MKCERT_CERT" ]]; then
    cat "$MKCERT_CERT" >> "$CERT_DIR/$host/ca.crt"
  fi
  echo "  Configured $CERT_DIR/$host/ca.crt"
done

# --- Install to system-wide trust store ---
echo ""
echo "Installing to system-wide cert dirs and trust store..."
for host in "${HOSTS[@]}"; do
  sudo mkdir -p "/etc/containers/certs.d/$host"
  sudo cp "$CERT_DIR/$host/ca.crt" "/etc/containers/certs.d/$host/ca.crt"
  echo "  Configured /etc/containers/certs.d/$host/ca.crt"
done
# Bundle both certs into the system anchor
{
  [[ -n "$BOOTSTRAP_CERT" ]] && cat "$BOOTSTRAP_CERT"
  [[ -n "$MKCERT_CERT" ]]    && cat "$MKCERT_CERT"
} | sudo tee /etc/pki/ca-trust/source/anchors/hierocracy-registry.crt
sudo update-ca-trust
echo "System trust store updated."

# Cleanup temp files
rm -f /tmp/bootstrap-registry.crt /tmp/mkcert-ca.crt

echo ""
echo "Host trust configuration complete."
