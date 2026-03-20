#!/bin/bash
# run-on-hierophant.sh - Helper to run commands on hierophant via SSH
# Usage: ./run-on-hierophant.sh "command to run"

# Using the recommended private key from guidelines
KEY_PATH="$HOME/.ssh/id_hierophant_access"
HIEROPHANT_IP="192.168.1.101"

if [ ! -f "$KEY_PATH" ]; then
    echo "Error: Key file not found at $KEY_PATH"
    exit 1
fi

# Always use non-interactive flags (BatchMode=yes) and disable GSSAPI to prevent hangs.
ssh -i "$KEY_PATH" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o GSSAPIAuthentication=no \
    -o ConnectTimeout=10 \
    junie@$HIEROPHANT_IP "$@"
