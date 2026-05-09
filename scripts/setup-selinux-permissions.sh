#!/bin/bash
# scripts/setup-selinux-permissions.sh
# Purpose: Pin SELinux contexts and DAC permissions for build files on hierophant.
# To be executed on: hierophant (Ideally with sudo/root privileges)

set -e

# Target paths
CURRENT_VERSION="/mnt/hegemon-share/share/code/complete-build/CURRENT_VERSION"
LOCK_FILES=(
    "/tmp/rag-stack-build.lock"
    "/tmp/rag-stack-build-ledger.json"
    "/tmp/rag-stack-build-heartbeat"
)
JOURNAL_DIR="/tmp/.build_journal_junie"

echo "Step 1: Checking sudo privileges..."
if sudo -n true 2>/dev/null; then
    HAS_SUDO=true
    echo "Sudo privileges detected."
else
    HAS_SUDO=false
    echo "Warning: Sudo privileges not detected. Some steps will be skipped."
    echo "To fully 'pin' SELinux contexts, please run this script as root."
fi

echo "Step 2: Defining SELinux contexts (semanage)..."
if [ "$HAS_SUDO" = true ]; then
    sudo semanage fcontext -a -t public_content_rw_t "$CURRENT_VERSION" 2>/dev/null || \
    sudo semanage fcontext -m -t public_content_rw_t "$CURRENT_VERSION" 2>/dev/null || echo "Notice: semanage rule already exists or failed for CURRENT_VERSION"
    
    for lock in "${LOCK_FILES[@]}"; do
        sudo semanage fcontext -a -t public_content_rw_t "$lock" 2>/dev/null || \
        sudo semanage fcontext -m -t public_content_rw_t "$lock" 2>/dev/null || echo "Notice: semanage rule already exists or failed for $lock"
    done
    
    sudo semanage fcontext -a -t public_content_rw_t "$JOURNAL_DIR(/.*)?" 2>/dev/null || \
    sudo semanage fcontext -m -t public_content_rw_t "$JOURNAL_DIR(/.*)?" 2>/dev/null || echo "Notice: semanage rule already exists or failed for journal dir"
    
    echo "Step 3: Applying contexts (restorecon)..."
    sudo restorecon -v "$CURRENT_VERSION" || echo "Warning: restorecon failed for CURRENT_VERSION"
    for lock in "${LOCK_FILES[@]}"; do
        touch "$lock" 2>/dev/null || true
        sudo restorecon -v "$lock" || echo "Warning: restorecon failed for $lock"
    done
    sudo restorecon -Rv "$JOURNAL_DIR" || echo "Warning: restorecon failed for $JOURNAL_DIR"
else
    echo "SKIPPING Step 2 & 3: sudo/semanage required."
fi

echo "Step 4: Setting Default ACLs for DAC persistence..."
# We can do this for the journal dir if we own it
mkdir -p "$JOURNAL_DIR"
if setfacl -m d:g:super-user:rw,g:super-user:rw "$JOURNAL_DIR" 2>/dev/null; then
    echo "Applied Default ACLs to $JOURNAL_DIR"
else
    echo "Failed to set ACLs on $JOURNAL_DIR (Try running as root)"
fi

for lock in "${LOCK_FILES[@]}"; do
    if setfacl -m g:super-user:rw "$lock" 2>/dev/null; then
        echo "Applied ACL to $lock"
    else
        echo "Failed to set ACL for $lock (Try running as root)"
    fi
done

# Ensure group stickiness on journal dir
chgrp super-user "$JOURNAL_DIR" 2>/dev/null || true
chmod g+s "$JOURNAL_DIR" 2>/dev/null || true

echo "Step 5: Verification..."
ls -lZ "$CURRENT_VERSION"
ls -lZ "${LOCK_FILES[@]}" 2>/dev/null || echo "Some lock files missing"
ls -ldZ "$JOURNAL_DIR"
getfacl "$JOURNAL_DIR" 2>/dev/null || echo "getfacl not available or failed"

echo "Permissions setup script finished."
