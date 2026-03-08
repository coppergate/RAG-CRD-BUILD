#!/bin/bash
# audit-image-sources.sh - Report image references and external registry usage.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN_FILE="$ROOT_DIR/scripts/install-image-plan.sh"

tmp_all="$(mktemp)"
cleanup() { rm -f "$tmp_all"; }
trap cleanup EXIT

# 1) Dockerfiles FROM
find "$ROOT_DIR/rag-stack/services" -type f -name 'Dockerfile' -print0 2>/dev/null |
  xargs -0 awk 'toupper($1)=="FROM" {print $2}' >> "$tmp_all" || true

# 2) YAML image fields
find "$ROOT_DIR/rag-stack" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 2>/dev/null |
  xargs -0 sed -nE 's/^[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' >> "$tmp_all" || true

# 3) Shell kubectl run --image= refs
find "$ROOT_DIR" -type f -name '*.sh' ! -name 'audit-image-sources.sh' -print0 2>/dev/null |
  xargs -0 sed -nE 's/.*kubectl[^[:space:]]*[[:space:]]+run[[:space:]].*--image=([^"[:space:]]+).*/\1/p' >> "$tmp_all" || true

# 4) Go Image: refs
find "$ROOT_DIR/rag-stack" -type f -name '*.go' -print0 2>/dev/null |
  xargs -0 sed -nE 's/.*Image:[[:space:]]*"([^"]+)".*/\1/p' >> "$tmp_all" || true

# 5) install-image-plan groups
if [[ -f "$PLAN_FILE" ]]; then
  sed -nE 's/^IMAGE_GROUPS\[[^]]+\]="(.*)"/\1/p' "$PLAN_FILE" | tr ' ' '\n' >> "$tmp_all" || true
fi

# normalize and dedupe
mapfile -t images < <(sed 's/[[:space:]]\+$//' "$tmp_all" | sed '/^$/d' | sort -u)

echo "Image source audit"
echo "Root: $ROOT_DIR"
echo "Total unique refs: ${#images[@]}"
echo

dockerio_count=0
local_count=0
other_count=0

printf "%s\n" "Registry summary:"
for img in "${images[@]}"; do
  first="${img%%/*}"
  if [[ "$img" == "registry.hierocracy.home:5000/"* ]]; then
    ((local_count+=1))
  elif [[ "$first" == *.* || "$first" == *:* || "$first" == "localhost" ]]; then
    ((other_count+=1))
  else
    ((dockerio_count+=1))
  fi
done
printf "  local-registry: %d\n" "$local_count"
printf "  docker.io (implicit): %d\n" "$dockerio_count"
printf "  other explicit registries: %d\n" "$other_count"
echo

echo "Non-local image refs (need mirror or exception):"
for img in "${images[@]}"; do
  first="${img%%/*}"
  if [[ "$img" == "registry.hierocracy.home:5000/"* ]]; then
    continue
  fi
  if [[ "$first" == *.* || "$first" == *:* || "$first" == "localhost" ]]; then
    echo "$img"
  else
    echo "docker.io/$img"
  fi
done
