#!/bin/bash
# run-on-hierophant.sh - Helper to run commands on hierophant via SSH
# Usage: ./run-on-hierophant.sh "command to run"

KEY_PATH="/mnt/hegemon-share/share/code/complete-build/.junie/hierophant_key"
HIEROPHANT_IP="192.168.1.101"

if [ ! -f "$KEY_PATH" ]; then
    echo "Error: Key file not found at $KEY_PATH"
    exit 1
fi

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 junie@$HIEROPHANT_IP "$@"
