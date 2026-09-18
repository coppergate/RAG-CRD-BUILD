#!/bin/bash
# audit-image-sources.sh - Audit consumed image refs and plan coverage.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN_FILE="$ROOT_DIR/scripts/install-image-plan.sh"
LOCAL_REGISTRY_PREFIX_BOOTSTRAP="registry.hierocracy.home:5000/"
LOCAL_REGISTRY_PREFIX_CLUSTER="registry.container-registry.svc.cluster.local:5000/"
# Flat-LAN host registry prefix (config/network.env REGISTRY_PREFIX). Rendered
# manifests carry this form, so it must be recognised as local — otherwise every
# rendered ref is reported as an uncovered upstream ref.
LOCAL_REGISTRY_PREFIX_HOST="hierophant.hierocracy.home:5000/"

TMP_CONSUMED_RAW="$(mktemp)"
TMP_CONSUMED_UPSTREAM="$(mktemp)"
TMP_PLAN="$(mktemp)"
cleanup() {
  rm -f "$TMP_CONSUMED_RAW" "$TMP_CONSUMED_UPSTREAM" "$TMP_PLAN"
}
trap cleanup EXIT

normalize_to_upstream() {
  local ref="$1"
  ref="${ref%\"}"
  ref="${ref#\"}"
  if [[ "$ref" == "$LOCAL_REGISTRY_PREFIX_BOOTSTRAP"* ]]; then
    echo "${ref#$LOCAL_REGISTRY_PREFIX_BOOTSTRAP}"
    return
  fi
  if [[ "$ref" == "$LOCAL_REGISTRY_PREFIX_CLUSTER"* ]]; then
    echo "${ref#$LOCAL_REGISTRY_PREFIX_CLUSTER}"
    return
  fi
  if [[ "$ref" == "$LOCAL_REGISTRY_PREFIX_HOST"* ]]; then
    echo "${ref#$LOCAL_REGISTRY_PREFIX_HOST}"
    return
  fi
  echo "$ref"
}

is_local_ref() {
  local ref="$1"
  [[ "$ref" == "$LOCAL_REGISTRY_PREFIX_BOOTSTRAP"* ]] ||
  [[ "$ref" == "$LOCAL_REGISTRY_PREFIX_CLUSTER"* ]] ||
  [[ "$ref" == "$LOCAL_REGISTRY_PREFIX_HOST"* ]]
}

is_local_exception_ref() {
  local ref="$1"
  # Bootstrap exception: the in-cluster registry deployment image itself.
  [[ "$ref" == "registry:2" ]] && return 0
  # Refs built from a shell variable ($INTERNAL_REGISTRY/..., $REGISTRY/...) are
  # already registry-local once expanded.
  [[ "$ref" == \$* ]] && return 0
  return 1
}

is_active_path() {
  local p="$1"
  [[ "$p" != "$ROOT_DIR/.git/"* ]] &&
  [[ "$p" != "/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/ai-changes/original/"* ]] &&
  [[ "$p" != "/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/image-source-cache/"* ]] &&
  [[ "$p" != "/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/registry-cache/"* ]] &&
  [[ "$p" != "$ROOT_DIR/research/"* ]]
}

# 1) Dockerfiles FROM (services + tests)
while IFS= read -r -d '' f; do
  while IFS= read -r line; do
    img="$(awk 'toupper($1)=="FROM" {print $2}' <<< "$line")"
    [[ -n "$img" ]] && echo "$img" >> "$TMP_CONSUMED_RAW"
  done < "$f"
done < <(find "$ROOT_DIR/rag-stack" -type f -name 'Dockerfile*' -print0 2>/dev/null)

# 2) YAML image-like fields
while IFS= read -r -d '' f; do
  is_active_path "$f" || continue
  sed -nE \
    -e 's/^[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' \
    -e 's/^[[:space:]]*imageName:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' \
    -e 's/.*--prometheus-config-reloader=([^"[:space:]]+).*/\1/p' \
    -e 's/.*-configmapServerImage=([^"[:space:]]+).*/\1/p' \
    -e 's/.*--acme-http01-solver-image=([^"[:space:]]+).*/\1/p' \
    -e '/OPERATOR_IMAGE_NAME/{n;s/^[[:space:]]*value:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p;}' \
    -e 's/^[[:space:]]*-[[:space:]]+((registry\.hierocracy\.home:5000|hierophant\.hierocracy\.home:5000|registry\.container-registry\.svc\.cluster\.local:5000|docker\.io|quay\.io|ghcr\.io|gcr\.io|registry\.k8s\.io|kubernetesui|apachepulsar|streamnative)\/[^"[:space:]]+).*/\1/p' \
    "$f" >> "$TMP_CONSUMED_RAW" || true
done < <(find "$ROOT_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 2>/dev/null)

# 2b) Helm-style split image refs: `repository:` plus a nearby `tag:`.
# The plain `image:` scan above misses these entirely, which is how the Ollama
# and Pulsar values files stayed invisible to this audit.
while IFS= read -r -d '' f; do
  is_active_path "$f" || continue
  awk '
    match($0, /^[[:space:]]*repository:[[:space:]]*"?[^"[:space:]]+"?[[:space:]]*$/) {
      line = $0
      sub(/^[[:space:]]*repository:[[:space:]]*/, "", line)
      gsub(/"/, "", line)
      repo = line
      pending = repo
      # a tag seen just above the repository line still belongs to it
      if (prev_tag != "" && NR - prev_tag_line <= 3) { print repo ":" prev_tag; pending = "" }
      next
    }
    match($0, /^[[:space:]]*tag:[[:space:]]*"?[^"[:space:]]*"?[[:space:]]*$/) {
      line = $0
      sub(/^[[:space:]]*tag:[[:space:]]*/, "", line)
      gsub(/"/, "", line)
      prev_tag = line
      prev_tag_line = NR
      if (pending != "" && line != "") { print pending ":" line; pending = "" }
      next
    }
  ' "$f" \
    | grep -Ev '\{\{|^\s*$' >> "$TMP_CONSUMED_RAW" || true
done < <(find "$ROOT_DIR" -type f \( -name 'values*.yaml' -o -name 'values*.yml' \) -print0 2>/dev/null)

# 3) Shell kubectl run --image= refs
while IFS= read -r -d '' f; do
  is_active_path "$f" || continue
  sed -nE 's/.*(kubectl|\$KUBECTL)[^[:space:]]*[[:space:]]+run[[:space:]].*--image=([^"[:space:]]+).*/\2/p' "$f" >> "$TMP_CONSUMED_RAW" || true
done < <(find "$ROOT_DIR" -type f -name '*.sh' ! -name 'audit-image-sources.sh' -print0 2>/dev/null)

# 4) Go Image: refs
while IFS= read -r -d '' f; do
  is_active_path "$f" || continue
  sed -nE 's/.*Image:[[:space:]]*"([^"]+)".*/\1/p' "$f" >> "$TMP_CONSUMED_RAW" || true
done < <(find "$ROOT_DIR/rag-stack" -type f -name '*.go' -print0 2>/dev/null)

# normalize consumed refs to upstream names
sort -u "$TMP_CONSUMED_RAW" | sed '/^$/d' | while read -r img; do
  normalize_to_upstream "$img"
done | sort -u > "$TMP_CONSUMED_UPSTREAM"

# read plan refs
if [[ -f "$PLAN_FILE" ]]; then
  sed -nE 's/^IMAGE_GROUPS\[[^]]+\]="(.*)"/\1/p' "$PLAN_FILE" \
    | tr ' ' '\n' \
    | sed '/^$/d' \
    | while read -r img; do normalize_to_upstream "$img"; done \
    | sort -u > "$TMP_PLAN"
fi

consumed_count="$(wc -l < "$TMP_CONSUMED_UPSTREAM" | tr -d ' ')"
plan_count="$(wc -l < "$TMP_PLAN" | tr -d ' ')"

local_consumed_count=0
nonlocal_consumed_count=0
while read -r img; do
  [[ -z "$img" ]] && continue
  if is_local_ref "$img"; then
    ((local_consumed_count+=1))
  fi
done < <(sort -u "$TMP_CONSUMED_RAW")

# direct non-local refs still present in manifests/scripts
DIRECT_NONLOCAL="$(mktemp)"
trap 'rm -f "$TMP_CONSUMED_RAW" "$TMP_CONSUMED_UPSTREAM" "$TMP_PLAN" "$DIRECT_NONLOCAL"' EXIT
sort -u "$TMP_CONSUMED_RAW" | while read -r img; do
  [[ -z "$img" ]] && continue
  if ! is_local_ref "$img"; then
    if is_local_exception_ref "$img"; then
      continue
    fi
    echo "$img"
  fi
done | sort -u > "$DIRECT_NONLOCAL"
nonlocal_consumed_count="$(wc -l < "$DIRECT_NONLOCAL" | tr -d ' ')"

echo "Image source audit"
echo "Root: $ROOT_DIR"
echo "Consumed refs (normalized): $consumed_count"
echo "Plan refs: $plan_count"
echo

echo "Direct non-local refs in active manifests/scripts: $nonlocal_consumed_count"
if [[ "$nonlocal_consumed_count" -gt 0 ]]; then
  cat "$DIRECT_NONLOCAL"
fi

echo
echo "Consumed refs missing from install-image-plan.sh:"
# Exemptions:
#   *:__VERSION__       locally built service images; the tag is substituted at
#                       deploy time from the build-processor version, so no
#                       literal tag can ever match the plan.
#   *:latest (local)    build-orchestrator is pushed as both :<tag> and :latest.
#   $VAR/...            refs assembled from a shell variable at runtime
#                       (e.g. $INTERNAL_REGISTRY/...), already registry-local.
comm -23 "$TMP_CONSUMED_UPSTREAM" "$TMP_PLAN" \
  | while read -r img; do normalize_to_upstream "$img"; done \
  | sort -u \
  | grep -Ev '^[A-Za-z0-9._/-]+:__VERSION__$' \
  | grep -Ev '^build-orchestrator:latest$' \
  | grep -Ev '^\$[A-Za-z_][A-Za-z0-9_]*/' || true
