#!/bin/bash
# cache-registry-images.sh
# Backup and restore all images from the local registry to shared storage.
#
# Typical usage:
#   # Before shutdown
#   REGISTRY=registry.hierocracy.home:5000 \
#   CACHE_ROOT=/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/registry-cache \
#   bash scripts/cache-registry-images.sh backup
#
#   # After rebuild
#   REGISTRY=registry.hierocracy.home:5000 \
#   CACHE_ROOT=/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/registry-cache \
#   bash scripts/cache-registry-images.sh restore

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
MODE="${1:-}"

REGISTRY="${REGISTRY:-registry.hierocracy.home:5000}"
REGISTRY_API_SCHEME="${REGISTRY_API_SCHEME:-auto}" # auto|http|https
REGISTRY_API_INSECURE="${REGISTRY_API_INSECURE:-false}"
CACHE_ROOT="${CACHE_ROOT:-/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/registry-cache}"
BUNDLE_DIR="${BUNDLE_DIR:-}"
SKOPEO_TLS_VERIFY="${SKOPEO_TLS_VERIFY:-true}"
CACHE_CATALOG_PAGE_SIZE="${CACHE_CATALOG_PAGE_SIZE:-100}"
BACKUP_SKIP_EXISTING="${BACKUP_SKIP_EXISTING:-true}"
EFFECTIVE_API_SCHEME=""

log() {
  printf "[%s] %s\n" "$(date +'%F %T')" "$*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "required command missing: $c"
}

usage() {
  cat <<USAGE
Usage:
  $SCRIPT_NAME backup
  $SCRIPT_NAME restore [bundle-dir]
  $SCRIPT_NAME list

Env:
  REGISTRY=registry.hierocracy.home:5000
  REGISTRY_API_SCHEME=auto|http|https (default: auto)
  REGISTRY_API_INSECURE=true|false    (default: true)
  CACHE_ROOT=/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/registry-cache
  BUNDLE_DIR=/path/to/bundle          (optional for restore)
  SKOPEO_TLS_VERIFY=false             (set true if registry uses valid TLS)
  CACHE_CATALOG_PAGE_SIZE=100         Registry catalog page size for pagination
  BACKUP_SKIP_EXISTING=true|false     Reuse images from latest bundle when possible

Notes:
  - backup: exports every repo:tag in local registry into a timestamped bundle.
  - restore: imports all cached repo:tag refs back into the registry.
  - list: shows cached bundles under CACHE_ROOT.
USAGE
}

require_base_tools() {
  require_cmd skopeo
  require_cmd curl
  require_cmd jq
}

curl_common_opts() {
  local opts=("-fsS")
  if [[ "$REGISTRY_API_INSECURE" == "true" ]]; then
    opts+=("-k")
  elif [[ -f "/home/junie/.local/share/mkcert/rootCA.pem" ]]; then
    opts+=("--cacert" "/home/junie/.local/share/mkcert/rootCA.pem")
  fi
  printf '%s\n' "${opts[@]}"
}

detect_registry_scheme() {
  if [[ "$REGISTRY_API_SCHEME" == "http" || "$REGISTRY_API_SCHEME" == "https" ]]; then
    EFFECTIVE_API_SCHEME="$REGISTRY_API_SCHEME"
    return 0
  fi

  local opts
  mapfile -t opts < <(curl_common_opts)

  if curl "${opts[@]}" "https://${REGISTRY}/v2/" >/dev/null 2>&1; then
    EFFECTIVE_API_SCHEME="https"
    return 0
  fi
  if curl "${opts[@]}" "http://${REGISTRY}/v2/" >/dev/null 2>&1; then
    EFFECTIVE_API_SCHEME="http"
    return 0
  fi
  die "unable to reach registry API on https://${REGISTRY}/v2/ or http://${REGISTRY}/v2/"
}

registry_api() {
  local path="$1"
  [[ -n "$EFFECTIVE_API_SCHEME" ]] || detect_registry_scheme
  local opts
  mapfile -t opts < <(curl_common_opts)
  curl "${opts[@]}" "${EFFECTIVE_API_SCHEME}://${REGISTRY}${path}"
}

registry_api_with_headers() {
  local path="$1"
  local headers_file="$2"
  [[ -n "$EFFECTIVE_API_SCHEME" ]] || detect_registry_scheme
  local opts
  mapfile -t opts < <(curl_common_opts)
  curl "${opts[@]}" -D "$headers_file" "${EFFECTIVE_API_SCHEME}://${REGISTRY}${path}"
}

registry_catalog_all_json() {
  local next_path
  next_path="/v2/_catalog?n=${CACHE_CATALOG_PAGE_SIZE}"

  local repos_tmp
  repos_tmp="$(mktemp)"
  : > "$repos_tmp"

  while [[ -n "$next_path" ]]; do
    local headers_file body_json
    headers_file="$(mktemp)"
    body_json="$(registry_api_with_headers "$next_path" "$headers_file")"

    printf '%s' "$body_json" | jq -r '.repositories[]?' >> "$repos_tmp"

    local link next_link
    link="$(grep -i '^Link:' "$headers_file" | tr -d '\r' | sed -n 's/^Link: <\([^>]*\)>;.*$/\1/pI' | head -n1 || true)"
    rm -f "$headers_file"

    if [[ -z "$link" ]]; then
      next_path=""
      continue
    fi

    # Link may be absolute or relative.
    if [[ "$link" =~ ^https?:// ]]; then
      next_link="${link#*://}"
      next_link="/${next_link#*/}"
    else
      next_link="$link"
    fi
    next_path="$next_link"
  done

  sort -u "$repos_tmp" | jq -Rsc 'split("\n") | map(select(length > 0)) | {repositories: .}'
  rm -f "$repos_tmp"
}

latest_bundle_dir() {
  local latest
  latest="$(find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r | head -n1 || true)"
  [[ -n "$latest" ]] || return 1
  printf "%s/%s\n" "$CACHE_ROOT" "$latest"
}

backup_registry() {
  require_base_tools
  detect_registry_scheme

  mkdir -p "$CACHE_ROOT"

  local previous_bundle=""
  previous_bundle="$(latest_bundle_dir || true)"

  local ts bundle refs_file index_file repos_json repos_count
  ts="$(date -u +'%Y%m%dT%H%M%SZ')"
  bundle="$CACHE_ROOT/$ts"
  refs_file="$bundle/image-refs.tsv"
  index_file="$bundle/index.json"

  mkdir -p "$bundle/images"

  log "Registry: $REGISTRY"
  log "Registry API scheme: $EFFECTIVE_API_SCHEME (insecure_tls=$REGISTRY_API_INSECURE)"
  log "Skip existing images from latest bundle: $BACKUP_SKIP_EXISTING"
  if [[ -n "$previous_bundle" ]]; then
    log "Latest existing bundle: $previous_bundle"
  fi
  log "Bundle: $bundle"

  repos_json="$(registry_catalog_all_json)"
  repos_count="$(printf '%s' "$repos_json" | jq '.repositories | length')"

  if [[ "$repos_count" == "0" ]]; then
    die "registry catalog is empty; nothing to backup"
  fi

  printf '%s\n' "$repos_json" > "$bundle/catalog.json"

  : > "$refs_file"

  declare -A prev_ref_to_rel
  if [[ "$BACKUP_SKIP_EXISTING" == "true" ]] && [[ -n "$previous_bundle" ]] && [[ -f "$previous_bundle/image-refs.tsv" ]]; then
    while IFS=$'\t' read -r prev_ref prev_rel; do
      [[ -z "$prev_ref" || -z "$prev_rel" ]] && continue
      prev_ref_to_rel["$prev_ref"]="$prev_rel"
    done < "$previous_bundle/image-refs.tsv"
  fi

  while IFS= read -r repo; do
    [[ -z "$repo" ]] && continue

    local tags_json
    tags_json="$(registry_api "/v2/${repo}/tags/list")"
    printf '%s\n' "$tags_json" > "$bundle/tags-${repo//\//_}.json"

    while IFS= read -r tag; do
      [[ -z "$tag" ]] && continue

      local src rel dst
      src="${REGISTRY}/${repo}:${tag}"
      rel="images/${repo}/${tag}"
      dst="${bundle}/${rel}"

      local reused="false"
      if [[ "$BACKUP_SKIP_EXISTING" == "true" ]]; then
        local prev_rel prev_dir
        prev_rel="${prev_ref_to_rel["${repo}:${tag}"]:-}"
        prev_dir=""
        if [[ -n "$prev_rel" ]]; then
          prev_dir="${previous_bundle}/${prev_rel}"
        fi
        if [[ -n "$prev_dir" && -d "$prev_dir" ]]; then
          mkdir -p "$(dirname "$dst")"
          if cp -al "$prev_dir" "$dst" 2>/dev/null; then
            reused="true"
          elif cp -a "$prev_dir" "$dst" 2>/dev/null; then
            reused="true"
          fi
          if [[ "$reused" == "true" ]]; then
            log "Reused from previous bundle: $src"
          fi
        fi
      fi

      if [[ "$reused" != "true" ]]; then
        mkdir -p "$dst"
        log "Backing up: $src"
        skopeo copy --all --src-tls-verify="$SKOPEO_TLS_VERIFY" "docker://${src}" "dir:${dst}"
      fi

      printf '%s\t%s\n' "${repo}:${tag}" "$rel" >> "$refs_file"
    done < <(printf '%s' "$tags_json" | jq -r '.tags[]?')
  done < <(printf '%s' "$repos_json" | jq -r '.repositories[]?')

  jq -n \
    --arg created_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --arg registry "$REGISTRY" \
    --arg refs_file "image-refs.tsv" \
    '{created_at: $created_at, registry: $registry, refs_file: $refs_file}' > "$index_file"

  ln -sfn "$ts" "$CACHE_ROOT/latest"

  log "Backup complete."
  log "Refs: $refs_file"
  log "Latest symlink: $CACHE_ROOT/latest"
}

restore_registry() {
  require_base_tools
  detect_registry_scheme

  local bundle refs_file

  if [[ -n "$BUNDLE_DIR" ]]; then
    bundle="$BUNDLE_DIR"
  elif [[ -n "${1:-}" ]]; then
    bundle="$1"
  else
    bundle="$(latest_bundle_dir)" || die "no bundles found under $CACHE_ROOT"
  fi

  refs_file="$bundle/image-refs.tsv"

  [[ -d "$bundle" ]] || die "bundle directory not found: $bundle"
  [[ -f "$refs_file" ]] || die "missing refs file: $refs_file"

  log "Registry: $REGISTRY"
  log "Registry API scheme: $EFFECTIVE_API_SCHEME (insecure_tls=$REGISTRY_API_INSECURE)"
  log "Restore bundle: $bundle"

  while IFS=$'\t' read -r image_ref rel_path; do
    [[ -z "$image_ref" ]] && continue
    [[ -z "$rel_path" ]] && die "invalid refs row for $image_ref"

    local src dst
    src="dir:${bundle}/${rel_path}"
    dst="docker://${REGISTRY}/${image_ref}"

    [[ -d "${bundle}/${rel_path}" ]] || die "missing image data dir: ${bundle}/${rel_path}"

    log "Restoring: ${REGISTRY}/${image_ref}"
    skopeo copy --all --dest-tls-verify="$SKOPEO_TLS_VERIFY" "$src" "$dst"
  done < "$refs_file"

  log "Restore complete."
}

list_bundles() {
  mkdir -p "$CACHE_ROOT"
  find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r
}

main() {
  case "$MODE" in
    backup)
      backup_registry
      ;;
    restore)
      shift || true
      restore_registry "${1:-}"
      ;;
    list)
      list_bundles
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      usage
      die "unknown mode: $MODE"
      ;;
  esac
}

main "$@"
