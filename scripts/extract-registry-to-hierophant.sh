#!/bin/bash
# extract-registry-to-hierophant.sh
# Copies all images from the in-cluster registry to the hierophant bootstrap registry.
# Run this on hierophant after a completed cluster build.
#
# Usage:
#   ./extract-registry-to-hierophant.sh [--dry-run] [--parallelism N] [--skip-tls-verify]
#
# Env overrides:
#   SRC_REGISTRY    default: registry.hierocracy.home:5000
#   DST_REGISTRY    default: 10.0.0.1:5000
#   KUBECTL         default: /home/k8s/kube/kubectl
#   PARALLELISM     default: 4
#   KUBECONFIG      default: /home/k8s/kube/config/kubeconfig

set -Eeuo pipefail

SRC_REGISTRY="${SRC_REGISTRY:-registry.hierocracy.home:5000}"
DST_REGISTRY="${DST_REGISTRY:-10.0.0.1:5000}"
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"
PARALLELISM="${PARALLELISM:-4}"
DRY_RUN=false
SKIP_TLS_VERIFY=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)          DRY_RUN=true ;;
    --skip-tls-verify)  SKIP_TLS_VERIFY=true ;;
    --parallelism=*)    PARALLELISM="${arg#*=}" ;;
    --parallelism)      shift; PARALLELISM="${1:-4}" ;;
  esac
done

# ── Temp dirs / cleanup ───────────────────────────────────────────────────────
WORK_DIR="$(mktemp -d /tmp/registry-extract-XXXXXX)"
CA_FILE="$WORK_DIR/ca.crt"
IMAGE_LIST="$WORK_DIR/images.txt"
trap 'rm -rf "$WORK_DIR"' EXIT

log()  { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
die()  { log "ERROR: $*" >&2; exit 1; }

# ── 1. Extract CA cert from cluster ──────────────────────────────────────────
log "Extracting registry CA from cluster secret..."

$KUBECTL get secret in-cluster-registry-tls -n container-registry \
  -o jsonpath='{.data.ca\.crt}' 2>/dev/null \
  | base64 -d > "$CA_FILE" 2>/dev/null || true

if [[ ! -s "$CA_FILE" ]]; then
  log "ca.crt key empty — trying tls.crt..."
  $KUBECTL get secret in-cluster-registry-tls -n container-registry \
    -o jsonpath='{.data.tls\.crt}' \
    | base64 -d > "$CA_FILE"
fi

[[ -s "$CA_FILE" ]] || die "Could not extract CA cert from in-cluster-registry-tls secret"
log "CA cert extracted ($(wc -c < "$CA_FILE") bytes)"

# Build skopeo TLS flags
if [[ "$SKIP_TLS_VERIFY" == "true" ]]; then
  TLS_FLAGS="--src-tls-verify=false --dest-tls-verify=false"
else
  SRC_CERT_DIR="$WORK_DIR/src-certs"
  DST_CERT_DIR="$WORK_DIR/dst-certs"
  mkdir -p "$SRC_CERT_DIR" "$DST_CERT_DIR"
  cp "$CA_FILE" "$SRC_CERT_DIR/ca.crt"
  cp "$CA_FILE" "$DST_CERT_DIR/ca.crt"
  TLS_FLAGS="--src-cert-dir=$SRC_CERT_DIR --dest-cert-dir=$DST_CERT_DIR"
fi

# ── 2. List all repos from the v2 catalog API (paginated) ─────────────────────
# The registry enforces REGISTRY_CATALOG_MAXENTRIES (often 100); we page through
# all results by following the Link header until it's absent.
log "Querying catalog from https://${SRC_REGISTRY}/v2/_catalog (paginated)..."
PAGE_SIZE=100
CATALOG_FILE="$WORK_DIR/catalog.txt"
HEADERS_FILE="$WORK_DIR/headers.txt"
> "$CATALOG_FILE"
last=""

while true; do
  url="https://${SRC_REGISTRY}/v2/_catalog?n=${PAGE_SIZE}"
  [[ -n "$last" ]] && url="${url}&last=${last}"

  http_code=$(curl -sSf --cacert "$CA_FILE" \
    -D "$HEADERS_FILE" \
    -o "$WORK_DIR/page.json" \
    -w "%{http_code}" \
    "$url" 2>/dev/null) || true

  if [[ "$http_code" != "200" ]]; then
    die "Catalog page request returned HTTP $http_code (url=$url)"
  fi

  python3 -c "
import sys, json
with open('$WORK_DIR/page.json') as f:
    repos = json.load(f).get('repositories', [])
for r in repos:
    print(r)
" >> "$CATALOG_FILE" || die "Failed to parse catalog page JSON"

  # Stop if this page had fewer entries than the page size (last page)
  page_count=$(python3 -c "
import json
with open('$WORK_DIR/page.json') as f:
    print(len(json.load(f).get('repositories', [])))
")
  if [[ "$page_count" -lt "$PAGE_SIZE" ]]; then
    break
  fi

  # Extract last= from Link header for next page
  last=$(grep -i '^link:' "$HEADERS_FILE" 2>/dev/null \
    | sed -n 's/.*[?&]last=\([^&>]*\).*/\1/p' | head -1)
  [[ -n "$last" ]] || break
done

CATALOG=$(sort < "$CATALOG_FILE")
[[ -n "$CATALOG" ]] || die "Catalog returned empty — is the registry running and reachable?"

REPO_COUNT=$(echo "$CATALOG" | wc -l)
log "Found $REPO_COUNT repositories. Enumerating tags..."

# ── 3. Build full image:tag list ──────────────────────────────────────────────
> "$IMAGE_LIST"

while IFS= read -r repo; do
  tags_json=$(curl -sSf --cacert "$CA_FILE" \
    "https://${SRC_REGISTRY}/v2/${repo}/tags/list" 2>/dev/null || echo '{}')
  tags=$(echo "$tags_json" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); [print(t) for t in sorted(d.get('tags') or [])]" \
    2>/dev/null || true)
  if [[ -z "$tags" ]]; then
    log "  SKIP $repo (no tags)"
    continue
  fi
  while IFS= read -r tag; do
    printf '%s:%s\n' "$repo" "$tag" >> "$IMAGE_LIST"
  done <<< "$tags"
done <<< "$CATALOG"

TOTAL=$(wc -l < "$IMAGE_LIST")
log "Total images: $TOTAL"

# ── 4. Dry-run output ─────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN — would copy $TOTAL images from $SRC_REGISTRY → $DST_REGISTRY:"
  awk -v src="$SRC_REGISTRY" -v dst="$DST_REGISTRY" \
    '{printf "  docker://%s/%s  →  docker://%s/%s\n", src, $0, dst, $0}' "$IMAGE_LIST"
  exit 0
fi

# ── 5. Copy in parallel ───────────────────────────────────────────────────────
log "Copying $TOTAL images: $SRC_REGISTRY → $DST_REGISTRY (parallelism=$PARALLELISM)"

copy_one() {
  local img="$1"
  local src_reg="$2"
  local dst_reg="$3"
  local tls_flags="$4"
  local output rc

  # Ollama model blobs use a custom OCI media type (application/vnd.ollama.image.model)
  # that skopeo does not understand.  They must be backed up via the Ollama CLI separately.
  # Detect them by repo path: ollama/* except ollama/ollama (the container image itself).
  local repo="${img%%:*}"
  if [[ "$repo" == ollama/* && "$repo" != "ollama/ollama" ]]; then
    printf "SKIP-OLLAMA  %s\n" "$img"
    return 0
  fi

  # shellcheck disable=SC2086
  output=$(skopeo copy \
      $tls_flags \
      "docker://${src_reg}/${img}" \
      "docker://${dst_reg}/${img}" 2>&1)
  rc=$?
  echo "$output"
  if [[ $rc -eq 0 ]]; then
    printf "OK  %s\n" "$img"
  else
    printf "ERR %s\n" "$img"
  fi
}

export -f copy_one
export SRC_REGISTRY DST_REGISTRY TLS_FLAGS

PASS_COUNT=0
FAIL_COUNT=0

# xargs gives us the image name; copy_one does the work.
# Capture per-line results to count OK/ERR.
RESULTS=$(xargs -P "$PARALLELISM" -I{} \
  bash -c 'copy_one "$@"' _ {} "$SRC_REGISTRY" "$DST_REGISTRY" "$TLS_FLAGS" \
  < "$IMAGE_LIST")

echo "$RESULTS"

PASS_COUNT=$(echo "$RESULTS" | grep -c '^OK' || true)
FAIL_COUNT=$(echo "$RESULTS" | grep -c '^ERR' || true)
SKIP_COUNT=$(echo "$RESULTS" | grep -c '^SKIP-OLLAMA' || true)

log "Skopeo pass done. OK=$PASS_COUNT  ERR=$FAIL_COUNT  SKIP-OLLAMA=$SKIP_COUNT"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  log "WARNING: $FAIL_COUNT image(s) failed skopeo copy — continuing to Ollama pass."
fi

# ── 6. Copy Ollama model artifacts via temporary Ollama container ─────────────
# Skopeo cannot handle the application/vnd.ollama.image.model OCI media type.
# We start a short-lived Ollama container, pull each model from SRC_REGISTRY,
# then push it to DST_REGISTRY.
OLLAMA_OK=0
OLLAMA_ERR=0

if [[ "$SKIP_COUNT" -gt 0 ]]; then
  OLLAMA_MODEL_LIST=$(echo "$RESULTS" | awk '/^SKIP-OLLAMA/ {print $2}')

  # Reuse the model store from push-models-to-cluster.sh if present.
  OLLAMA_STORE="${OLLAMA_MODEL_STORE:-/mnt/storage/ollama-models}"
  mkdir -p "$OLLAMA_STORE"

  # Build a combined CA bundle the container can use to trust both registries.
  COMBINED_CA="$WORK_DIR/combined-ca.crt"
  HOST_CA_BUNDLE="/etc/pki/tls/certs/ca-bundle.crt"
  [[ -f "$HOST_CA_BUNDLE" ]] || HOST_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
  cat "$HOST_CA_BUNDLE" "$CA_FILE" > "$COMBINED_CA"

  OLLAMA_IMAGE="${SRC_REGISTRY}/ollama/ollama:0.15.6"
  CONTAINER_NAME="ollama-extract-$$"

  log "Starting Ollama container for $SKIP_COUNT model artifact(s)..."
  sudo podman run -d \
    --name "$CONTAINER_NAME" \
    -v "$OLLAMA_STORE:/ollama-models:z" \
    -v "$COMBINED_CA:/etc/ssl/certs/ca-certificates.crt:z" \
    -e OLLAMA_MODELS=/ollama-models \
    -e OLLAMA_LLM_LIBRARY=cpu \
    --replace "$OLLAMA_IMAGE"

  log "Waiting for Ollama to start..."
  ollama_ready=false
  for _i in {1..30}; do
    if sudo podman exec "$CONTAINER_NAME" ollama list >/dev/null 2>&1; then
      log "Ollama is ready."
      ollama_ready=true
      break
    fi
    sleep 2
  done

  if [[ "$ollama_ready" != "true" ]]; then
    log "ERROR: Ollama container failed to start."
    sudo podman logs "$CONTAINER_NAME" >&2 || true
    sudo podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    OLLAMA_ERR=$SKIP_COUNT
  else
    while IFS= read -r img; do
      [[ -n "$img" ]] || continue
      src_path="${SRC_REGISTRY}/${img}"
      dst_path="${DST_REGISTRY}/${img}"
      log "Ollama model: $img"

      if ! sudo podman exec -e OLLAMA_MODELS=/ollama-models \
              "$CONTAINER_NAME" ollama pull "$src_path"; then
        log "  ERROR: pull failed for $src_path"
        (( OLLAMA_ERR++ )) || true
        continue
      fi

      if ! sudo podman exec -e OLLAMA_MODELS=/ollama-models \
              "$CONTAINER_NAME" ollama cp "$src_path" "$dst_path"; then
        log "  ERROR: cp failed $src_path -> $dst_path"
        (( OLLAMA_ERR++ )) || true
        continue
      fi

      if ! sudo podman exec -e OLLAMA_MODELS=/ollama-models \
              "$CONTAINER_NAME" ollama push "$dst_path"; then
        log "  ERROR: push failed for $dst_path"
        (( OLLAMA_ERR++ )) || true
        continue
      fi

      log "  OK: $img"
      (( OLLAMA_OK++ )) || true
    done <<< "$OLLAMA_MODEL_LIST"

    log "Stopping Ollama container..."
    sudo podman stop "$CONTAINER_NAME" >/dev/null
    sudo podman rm   "$CONTAINER_NAME" >/dev/null
  fi

  log "Ollama pass done. OK=$OLLAMA_OK  ERR=$OLLAMA_ERR"
fi

# ── Final status ──────────────────────────────────────────────────────────────
log "All done. skopeo OK=$PASS_COUNT ERR=$FAIL_COUNT | ollama OK=$OLLAMA_OK ERR=$OLLAMA_ERR"
if [[ "$FAIL_COUNT" -gt 0 || "$OLLAMA_ERR" -gt 0 ]]; then
  log "Re-run the script to retry failures (both skopeo and ollama passes are idempotent)."
  exit 1
fi