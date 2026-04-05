#!/usr/bin/env bash
# registry-prune.sh — Prune old versions from the registry
#
# Keeps only the current versions listed in CURRENT_VERSION and the 'latest' tag.
# Everything else is deleted by digest.
#
# Usage (on hierophant):
#   ./scripts/registry-prune.sh [--dry-run]

set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Source of truth for versioning
if [[ ! -f "$BASE_DIR/CURRENT_VERSION" ]]; then
    echo "ERROR: CURRENT_VERSION file not found."
    exit 1
fi

REGISTRY="registry.hierocracy.home:5000"
REGISTRY_URL="docker://$REGISTRY"
TLS_FLAG="--tls-verify=false"

# Use jq to parse the JSON and get the map of service to version
SERVICES=$(jq -r 'keys[]' "$BASE_DIR/CURRENT_VERSION")

log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }

prune_repo() {
    local repo="$1"
    local current_v="$2"
    
    log "--- Pruning repo: $repo (Current: $current_v) ---"
    
    # Get all tags
    local tags
    tags=$(skopeo list-tags $TLS_FLAG "$REGISTRY_URL/$repo" | jq -r '.Tags[]') || {
        log "WARN: Failed to list tags for $repo"
        return
    }

    # Identify digests to keep
    local keep_digests=()
    
    # 1. Digest for current version
    local current_digest
    current_digest=$(skopeo inspect $TLS_FLAG "$REGISTRY_URL/$repo:$current_v" | jq -r '.Digest') || current_digest=""
    if [[ -n "$current_digest" ]]; then
        keep_digests+=("$current_digest")
        log "Keeping $current_v ($current_digest)"
    else
        log "WARN: Current version $current_v not found in registry for $repo"
    fi

    # 2. Digest for latest
    local latest_digest
    latest_digest=$(skopeo inspect $TLS_FLAG "$REGISTRY_URL/$repo:latest" | jq -r '.Digest') || latest_digest=""
    if [[ -n "$latest_digest" ]]; then
        if [[ "$latest_digest" != "$current_digest" ]]; then
            keep_digests+=("$latest_digest")
            log "Keeping latest ($latest_digest)"
        fi
    fi

    # 3. For all tags, check if their digest is in keep list
    # Use a map to track which digests we've checked/processed for this repo
    local processed_digests=()

    for tag in $tags; do
        # Always skip current and latest by name
        [[ "$tag" == "$current_v" ]] && continue
        [[ "$tag" == "latest" ]] && continue

        local tag_digest
        tag_digest=$(skopeo inspect $TLS_FLAG "$REGISTRY_URL/$repo:$tag" | jq -r '.Digest') || continue
        
        # Check if we should keep it
        local should_keep=false
        for k in "${keep_digests[@]}"; do
            [[ "$tag_digest" == "$k" ]] && should_keep=true && break
        done

        if [[ "$should_keep" == "true" ]]; then
            log "Skipping tag $tag as it points to a kept digest"
            continue
        fi

        # Check if we already deleted this digest in this run
        local already_processed=false
        for p in "${processed_digests[@]}"; do
            [[ "$tag_digest" == "$p" ]] && already_processed=true && break
        done
        [[ "$already_processed" == "true" ]] && continue

        # Deleting manifest
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would delete manifest for tag $tag ($tag_digest)"
        else
            log "Deleting manifest for tag $tag ($tag_digest)"
            skopeo delete $TLS_FLAG "$REGISTRY_URL/$repo@$tag_digest" || log "WARN: Failed to delete $tag_digest"
        fi
        processed_digests+=("$tag_digest")
    done
}

for svc in $SERVICES; do
    # Get version from JSON
    ver=$(jq -r ".\"$svc\".version" "$BASE_DIR/CURRENT_VERSION")
    prune_repo "$svc" "$ver"
done

log "Pruning complete."
