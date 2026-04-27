#!/bin/bash
# cleanup-old-images.sh - Cleanup podman images older than 7 days on hierophant
# Usage: ./cleanup-old-images.sh [--force]

set -e

DRY_RUN=true
if [[ "${1:-}" == "--force" ]]; then
    DRY_RUN=false
fi

echo "===================================================="
echo "Cleaning up Podman images older than 7 days (168h)"
echo "===================================================="

if [[ "$DRY_RUN" == "true" ]]; then
    echo "--- DRY RUN MODE (listing only) ---"
    echo "Run with --force to actually remove these images."
    echo ""
    # Filter images by creation date > 168h and show them
    podman images --filter "until=168h" --format "table {{.Repository}} {{.Tag}} {{.ID}} {{.Created}}"
    echo ""
    echo "Total images to be evaluated for pruning (excluding those in use):"
    podman images --filter "until=168h" -q | wc -l
else
    echo "--- ACTUAL PRUNE MODE ---"
    echo "Removing all unused images created more than 168 hours ago..."
    # 'prune -a' removes all unused images (not just dangling) that meet the filter
    podman image prune -a --force --filter "until=168h"
    echo ""
    echo "Cleanup complete."
fi
