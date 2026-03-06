#!/usr/bin/env bash
# verify-registry-tags.sh — Final post-build check for service images in the registry
#
# Verifies that all expected image:tag pairs exist in the container registry and
# (optionally) that the manifest digests match across multiple endpoints (DNS/IP).
#
# Usage (on hierophant):
#   export VERSION=1.0.0
#   ./scripts/verify-registry-tags.sh
#
# Optional env vars:
#   SERVICES           Space-separated list of repos (default: common RAG services)
#   VERSION            Tag to verify (default: 1.0.0)
#   REGISTRY_DNS       Default: registry.container-registry.svc.cluster.local:5000
#   REGISTRY_IP        Default: 172.20.1.26:5000
#   REGISTRY_ENDPOINTS Comma-separated endpoints to compare (default: "$REGISTRY_DNS,$REGISTRY_IP")
#   REGISTRY_SCHEME    http or https (default: http)

set -Eeuo pipefail

SERVICES=${SERVICES:-"rag-test-runner rag-worker rag-ingestion rag-web-ui llm-gateway db-adapter qdrant-adapter object-store-mgr"}
VERSION=${VERSION:-"1.0.0"}
REGISTRY_CANON=${REGISTRY_CANON:-"registry.hierocracy.home:5000"}
REGISTRY_DNS=${REGISTRY_DNS:-"registry.container-registry.svc.cluster.local:5000"}
REGISTRY_IP=${REGISTRY_IP:-"172.20.1.26:5000"}
# By default, check only the canonical endpoint; you may add others for comparison
REGISTRY_ENDPOINTS=${REGISTRY_ENDPOINTS:-"$REGISTRY_CANON"}
REGISTRY_SCHEME=${REGISTRY_SCHEME:-"http"}

log()  { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
warn() { log "WARN: $*"; }
fail() { log "ERROR: $*"; exit 1; }

curl_json() {
  local url="$1"
  curl -fsSL --connect-timeout 5 --max-time 10 "$url"
}

get_digest() {
  # Returns the Docker-Content-Digest for repo:tag at endpoint, or empty on failure
  local endpoint="$1" repo="$2" tag="$3"
  local url="$REGISTRY_SCHEME://$endpoint/v2/$repo/manifests/$tag"
  # HEAD may return the digest; fall back to GET headers if needed
  local digest
  digest=$(curl -fsSI --connect-timeout 5 --max-time 10 \
           -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
           "$url" 2>/dev/null | awk -F': ' 'tolower($1)=="docker-content-digest"{gsub(/\r/,"",$2);print $2; exit}') || true
  echo -n "$digest"
}

has_tag() {
  local endpoint="$1" repo="$2" tag="$3"
  local url="$REGISTRY_SCHEME://$endpoint/v2/$repo/tags/list"
  curl_json "$url" | grep -q '"name"' || return 1
  curl_json "$url" | grep -q '"'"$tag"'"'
}

main() {
  log "Verifying image tags for services: $SERVICES"
  log "Endpoints: $REGISTRY_ENDPOINTS (scheme=$REGISTRY_SCHEME), tag=$VERSION"

  local overall_ok=true
  IFS=',' read -r -a eps <<<"$REGISTRY_ENDPOINTS"

  for svc in $SERVICES; do
    local repo="$svc"
    log "--- $repo:$VERSION ---"
    local ep_ok=true
    local first_digest=""
    for ep in "${eps[@]}"; do
      if has_tag "$ep" "$repo" "$VERSION"; then
        local d
        d=$(get_digest "$ep" "$repo" "$VERSION")
        if [[ -z "$d" ]]; then
          # Some registries may omit Docker-Content-Digest on HEAD/GET; treat presence as OK
          warn "$repo:$VERSION present on $ep but digest header not reported"
        else
          log "Found on $ep with digest: $d"
          if [[ -z "$first_digest" ]]; then
            first_digest="$d"
          elif [[ "$d" != "$first_digest" ]]; then
            warn "Digest mismatch between endpoints for $repo:$VERSION"
            ep_ok=false
          fi
        fi
      else
        warn "$repo:$VERSION NOT found on $ep"
        ep_ok=false
      fi
    done
    if [[ "$ep_ok" == true ]]; then
      log "OK: $repo:$VERSION present and consistent across endpoints"
    else
      overall_ok=false
    fi
  done

  if [[ "$overall_ok" == true ]]; then
    log "All images verified successfully."
    exit 0
  else
    fail "One or more images missing or inconsistent across endpoints."
  fi
}

main "$@"
