#!/bin/bash
# fill-missing-backup-images.sh
#
# Compare install-image-plan images to a registry backup bundle, pull only missing
# images, push them to local registry, then optionally run a new backup.

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLAN_FILE="${PLAN_FILE:-$SCRIPT_DIR/install-image-plan.sh}"
BACKUP_SCRIPT="${BACKUP_SCRIPT:-$SCRIPT_DIR/cache-registry-images.sh}"

REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
CACHE_ROOT="${CACHE_ROOT:-/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/registry-cache}"
SOURCE_CACHE_ROOT="${SOURCE_CACHE_ROOT:-/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/image-source-cache}"
BUNDLE_DIR="${BUNDLE_DIR:-}"

SKOPEO_DEST_TLS_VERIFY="${SKOPEO_DEST_TLS_VERIFY:-false}"
SKOPEO_SRC_TLS_VERIFY="${SKOPEO_SRC_TLS_VERIFY:-true}"

RUN_FINAL_BACKUP="${RUN_FINAL_BACKUP:-true}"
BACKUP_REGISTRY_API_SCHEME="${BACKUP_REGISTRY_API_SCHEME:-http}"
BACKUP_REGISTRY_API_INSECURE="${BACKUP_REGISTRY_API_INSECURE:-true}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

usage() {
  cat <<USAGE
Usage:
  $(basename "$0")
  $(basename "$0") --bundle-dir /path/to/bundle [--no-final-backup]

Env:
  PLAN_FILE=.../scripts/install-image-plan.sh
  BACKUP_SCRIPT=.../scripts/cache-registry-images.sh
  REGISTRY=registry.hierocracy.home:5000
  CACHE_ROOT=.../registry-cache
  SOURCE_CACHE_ROOT=.../image-source-cache
  BUNDLE_DIR=/path/to/backup-bundle
  SKOPEO_DEST_TLS_VERIFY=false
  SKOPEO_SRC_TLS_VERIFY=true
  RUN_FINAL_BACKUP=true|false
  BACKUP_REGISTRY_API_SCHEME=http|https|auto
  BACKUP_REGISTRY_API_INSECURE=true|false

Behavior:
  1) Reads plan images from install-image-plan.sh
  2) Compares with bundle image-refs.tsv
  3) Pulls/pushes only missing images
  4) Optionally runs a new backup bundle
USAGE
}

log() {
  printf "[%s] %s\n" "$(date +'%F %T')" "$*"
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || {
    echo "ERROR: required command missing: $c" >&2
    exit 1
  }
}

latest_bundle_dir() {
  if [[ -L "$CACHE_ROOT/latest" ]]; then
    readlink -f "$CACHE_ROOT/latest"
    return 0
  fi

  local latest
  latest="$(find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r | head -n1 || true)"
  [[ -n "$latest" ]] || return 1
  printf "%s/%s\n" "$CACHE_ROOT" "$latest"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bundle-dir)
        shift
        BUNDLE_DIR="${1:-}"
        ;;
      --no-final-backup)
        RUN_FINAL_BACKUP="false"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift || true
  done
}

extract_plan_images() {
  grep -E '^IMAGE_GROUPS\[[^]]+\]="' "$PLAN_FILE" \
    | sed -E 's/^[^=]+="(.*)"$/\1/' \
    | tr ' ' '\n' \
    | sed '/^$/d;/__VERSION__/d;/^registry\.hierocracy\.home:5000\//d' \
    | sort -u
}

cache_dir_for_image() {
  local img="$1"
  local last_path_part repo tag
  last_path_part="${img##*/}"
  if [[ "$last_path_part" == *:* ]]; then
    repo="${img%:*}"
    tag="${img##*:}"
  else
    repo="$img"
    tag="latest"
  fi
  printf "%s/images/%s/%s\n" "$SOURCE_CACHE_ROOT" "$repo" "$tag"
}

ensure_in_registry() {
  local img="$1"
  local dst="docker://$REGISTRY/$img"

  if skopeo inspect --tls-verify="$SKOPEO_DEST_TLS_VERIFY" "$dst" >/dev/null 2>&1; then
    log "Already in registry: $img"
    return 0
  fi

  local cache_dir tmp_cache
  cache_dir="$(cache_dir_for_image "$img")"

  if [[ ! -f "$cache_dir/.cached" ]]; then
    log "Cache miss; pulling upstream: $img"
    mkdir -p "$(dirname "$cache_dir")"
    tmp_cache="${cache_dir}.tmp.$$"
    rm -rf "$tmp_cache"
    mkdir -p "$tmp_cache"
    skopeo copy --all --src-tls-verify="$SKOPEO_SRC_TLS_VERIFY" "docker://$img" "dir:$tmp_cache"
    rm -rf "$cache_dir"
    mv "$tmp_cache" "$cache_dir"
    printf "%s\n" "$img" > "$cache_dir/.cached"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$cache_dir/.cached_at"
  else
    log "Cache hit: $img"
  fi

  log "Pushing to registry: $img"
  skopeo copy --all --dest-tls-verify="$SKOPEO_DEST_TLS_VERIFY" "dir:$cache_dir" "$dst"
}

main() {
  parse_args "$@"

  require_cmd skopeo
  require_cmd grep
  require_cmd sed
  require_cmd sort
  require_cmd comm
  require_cmd awk

  [[ -f "$PLAN_FILE" ]] || { echo "ERROR: PLAN_FILE not found: $PLAN_FILE" >&2; exit 1; }
  [[ -x "$BACKUP_SCRIPT" ]] || { echo "ERROR: BACKUP_SCRIPT not executable: $BACKUP_SCRIPT" >&2; exit 1; }

  if [[ -z "$BUNDLE_DIR" ]]; then
    BUNDLE_DIR="$(latest_bundle_dir)" || {
      echo "ERROR: no backup bundle found under $CACHE_ROOT" >&2
      exit 1
    }
  fi
  [[ -d "$BUNDLE_DIR" ]] || { echo "ERROR: bundle dir not found: $BUNDLE_DIR" >&2; exit 1; }
  [[ -f "$BUNDLE_DIR/image-refs.tsv" ]] || { echo "ERROR: missing $BUNDLE_DIR/image-refs.tsv" >&2; exit 1; }

  log "Plan file: $PLAN_FILE"
  log "Bundle dir: $BUNDLE_DIR"
  log "Registry: $REGISTRY"

  extract_plan_images > "$TMP_DIR/plan-images.txt"
  awk -F'\t' '{print $1}' "$BUNDLE_DIR/image-refs.tsv" | sed '/^$/d' | sort -u > "$TMP_DIR/bundle-images.txt"
  comm -23 "$TMP_DIR/plan-images.txt" "$TMP_DIR/bundle-images.txt" > "$TMP_DIR/missing-images.txt"

  local missing_count
  missing_count="$(wc -l < "$TMP_DIR/missing-images.txt" | tr -d ' ')"
  log "Missing images vs bundle: $missing_count"

  if [[ "$missing_count" -gt 0 ]]; then
    log "Missing image list:"
    sed -n '1,200p' "$TMP_DIR/missing-images.txt"
  fi

  local pulled=0 failed=0
  while IFS= read -r img; do
    [[ -z "$img" ]] && continue
    if ensure_in_registry "$img"; then
      pulled=$((pulled + 1))
    else
      failed=$((failed + 1))
      log "FAILED image: $img"
    fi
  done < "$TMP_DIR/missing-images.txt"

  log "Image fill summary: processed=$missing_count success=$pulled failed=$failed"

  if [[ "$failed" -ne 0 ]]; then
    echo "ERROR: some images failed to process; not running final backup" >&2
    exit 1
  fi

  if [[ "$RUN_FINAL_BACKUP" == "true" ]]; then
    log "Running final backup to include newly filled images..."
    REGISTRY="$REGISTRY" \
    REGISTRY_API_SCHEME="$BACKUP_REGISTRY_API_SCHEME" \
    REGISTRY_API_INSECURE="$BACKUP_REGISTRY_API_INSECURE" \
    CACHE_ROOT="$CACHE_ROOT" \
    "$BACKUP_SCRIPT" backup
  else
    log "RUN_FINAL_BACKUP=false; skipping backup step."
  fi

  log "Done."
}

main "$@"
