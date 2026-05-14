#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_TARGET=$(cd "$SCRIPT_DIR/.." && pwd)
TARGET_DIR="${1:-$DEFAULT_TARGET}"
SELINUX_TYPE="${SELINUX_TYPE:-public_content_rw_t}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "ERROR: target directory does not exist: $TARGET_DIR" >&2
  exit 1
fi

if [[ "$(basename "$TARGET_DIR")" != "complete-build" ]]; then
  echo "WARNING: target is not named 'complete-build': $TARGET_DIR" >&2
fi

run_privileged() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

echo "Applying broad POSIX permissions to: $TARGET_DIR"
chmod -R a+rwX "$TARGET_DIR"

echo "Ensuring directories remain traversable"
find "$TARGET_DIR" -type d -exec chmod a+rwx {} +

if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  if command -v chcon >/dev/null 2>&1; then
    echo "Applying SELinux context '$SELINUX_TYPE' recursively"
    run_privileged chcon -R -t "$SELINUX_TYPE" "$TARGET_DIR"
  else
    echo "WARNING: chcon is not installed; skipping SELinux relabel." >&2
  fi
else
  echo "SELinux is not enabled; skipping SELinux relabel."
fi

echo "Done."
