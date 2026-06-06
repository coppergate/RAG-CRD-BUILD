#!/bin/bash
# fix-storage-permissions.sh
# Run on hierophant as a user with sudo.
# Permanently fixes /mnt/storage permissions and SELinux contexts so all files
# and directories are accessible to everyone regardless of who created them.
# Installs a systemd service (using inotifywait) to propagate permissions to
# any newly created files/directories automatically going forward.
set -euo pipefail

TARGET="${STORAGE_TARGET:-/mnt/storage}"
SERVICE_NAME="storage-perm-watcher"
INOTIFY_SCRIPT="/usr/local/sbin/${SERVICE_NAME}.sh"

echo "=== Storage Permissions Fix ==="
echo "Target: $TARGET"
echo ""

# ---------------------------------------------------------------------------
# 1. Immediate fix — permissions, ACLs, SELinux on all existing content
# ---------------------------------------------------------------------------
echo "[1/4] Setting ownership and permissions on all existing files..."
sudo chown -R root:super-user "$TARGET"
sudo chmod -R a+rwX "$TARGET"          # files: rw for all; dirs: rwx for all
sudo find "$TARGET" -type d -exec chmod a+rwx,g+s {} \;   # setgid on all dirs so new files inherit group

echo "[1/4] Setting default ACLs so new files/dirs inherit open permissions..."
sudo find "$TARGET" -type d -exec setfacl -m d:u::rwx,d:g::rwx,d:o::rwx {} \;
sudo setfacl -R -m u::rwx,g::rwx,o::rwx "$TARGET"

echo "[1/4] Fixing SELinux contexts..."
# container_file_t allows podman/containers to read and write.
# public_content_rw_t is used for shared public content (e.g. NFS/FTP roots).
# We set container_file_t recursively so all container volume mounts work.
if command -v semanage &>/dev/null; then
  sudo semanage fcontext -a -t container_file_t "${TARGET}(/.*)?" || \
    sudo semanage fcontext -m -t container_file_t "${TARGET}(/.*)?";
fi
if command -v restorecon &>/dev/null; then
  sudo restorecon -Rv "$TARGET"
fi

echo ""
echo "[1/4] Done. Current state:"
ls -laZ "$TARGET"

# ---------------------------------------------------------------------------
# 2. Install inotifywait if missing
# ---------------------------------------------------------------------------
echo ""
echo "[2/4] Checking for inotify-tools..."
if ! command -v inotifywait &>/dev/null; then
  echo "  Installing inotify-tools..."
  sudo dnf install -y inotify-tools || sudo apt-get install -y inotify-tools
else
  echo "  inotifywait already installed."
fi

# ---------------------------------------------------------------------------
# 3. Write the watcher script
# ---------------------------------------------------------------------------
echo ""
echo "[3/4] Writing watcher script to $INOTIFY_SCRIPT..."
sudo tee "$INOTIFY_SCRIPT" > /dev/null <<WATCHER
#!/bin/bash
# ${SERVICE_NAME}.sh — auto-applied by systemd; do not edit manually.
# Watches TARGET for new files/dirs and immediately applies open permissions
# and the correct SELinux context.
TARGET="${TARGET}"
inotifywait -m -r -e create -e moved_to --format '%w%f' "\$TARGET" | while read -r PATH_NEW; do
  if [ -d "\$PATH_NEW" ]; then
    chmod a+rwx,g+s "\$PATH_NEW"
    setfacl -m d:u::rwx,d:g::rwx,d:o::rwx "\$PATH_NEW"
    setfacl -m u::rwx,g::rwx,o::rwx "\$PATH_NEW"
  else
    chmod a+rw "\$PATH_NEW"
    setfacl -m u::rwx,g::rwx,o::rwx "\$PATH_NEW"
  fi
  chcon -t container_file_t "\$PATH_NEW" 2>/dev/null || true
done
WATCHER
sudo chmod +x "$INOTIFY_SCRIPT"

# ---------------------------------------------------------------------------
# 4. Install and enable the systemd service
# ---------------------------------------------------------------------------
echo ""
echo "[4/4] Installing systemd service ${SERVICE_NAME}..."
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<SERVICE
[Unit]
Description=Storage permission watcher — auto-apply open perms to ${TARGET}
After=local-fs.target
Wants=local-fs.target

[Service]
Type=simple
ExecStart=${INOTIFY_SCRIPT}
Restart=on-failure
RestartSec=5
# Run as root so chown/chcon work without sudo
User=root

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable --now "${SERVICE_NAME}.service"
sudo systemctl status "${SERVICE_NAME}.service" --no-pager

echo ""
echo "=== Done ==="
echo "Existing files: fixed."
echo "New files:      ${SERVICE_NAME}.service will fix them automatically."
echo ""
echo "To re-run the immediate fix at any time:"
echo "  sudo bash ${0}"
echo ""
echo "To force a specific subtree:"
echo "  STORAGE_TARGET=/mnt/storage/ollama-models sudo bash ${0}"
