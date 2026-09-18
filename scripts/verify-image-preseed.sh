#!/bin/bash
# ==============================================================================
# verify-image-preseed.sh — is every image in the install plan actually present
#                           in the local registry, at the exact tag?
#
# scripts/verify-registry-tags.sh checks only the locally BUILT service images.
# This script checks the other direction: every upstream image the install and
# the Kaniko builds depend on, tag by tag, so a rebuild cannot discover a
# missing base image halfway through a step.
#
# Read-only. Prints the mirror command for whatever is missing; never pushes.
#
# Usage:
#   bash scripts/verify-image-preseed.sh                  # all upstream groups
#   bash scripts/verify-image-preseed.sh --group build-bases --group ollama
#   bash scripts/verify-image-preseed.sh --step rag-images
#   VERSION=2.4.11 bash scripts/verify-image-preseed.sh --include-local
#
# Env:
#   REGISTRY=host:port     Registry to probe (default: REGISTRY_PREFIX from
#                          config/network.env)
#   REGISTRY_SCHEME=https  http|https
#   REGISTRY_INSECURE=true Accept the registry's self-signed cert
#   VERSION=x.y.z          Tag substituted for __VERSION__ with --include-local
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../config/network.env
source "$BASE_DIR/config/network.env"

PLAN_FILE="${PLAN_FILE:-$SCRIPT_DIR/install-image-plan.sh}"
# shellcheck source=./install-image-plan.sh
source "$PLAN_FILE"

REGISTRY="${REGISTRY:-$REGISTRY_PREFIX}"
REGISTRY_SCHEME="${REGISTRY_SCHEME:-https}"
REGISTRY_INSECURE="${REGISTRY_INSECURE:-true}"
INCLUDE_LOCAL="false"
QUIET="false"
requested_groups=()

ACCEPT_HEADER='application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--group <name>]... [--step <step>] [--include-local] [--quiet]
  $(basename "$0") --list-groups

Exit status: 0 = every checked image present, 1 = at least one missing.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --group) shift; requested_groups+=("${1:?--group needs a value}") ;;
    --step)
      shift
      step="${1:?--step needs a value}"
      step_groups="$(plan_groups_for_step "$step")"
      [[ -n "$step_groups" ]] || { echo "ERROR: no groups mapped for step '$step'" >&2; exit 1; }
      for g in $step_groups; do requested_groups+=("$g"); done
      ;;
    --include-local) INCLUDE_LOCAL="true" ;;
    --quiet) QUIET="true" ;;
    --list-groups) plan_groups; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift || true
done

# default: every group except the locally built output (unless asked for)
if [[ ${#requested_groups[@]} -eq 0 ]]; then
  while IFS= read -r g; do
    [[ "$g" == "local-build-output" && "$INCLUDE_LOCAL" != "true" ]] && continue
    requested_groups+=("$g")
  done < <(plan_groups)
fi

curl_opts=(-sS -o /dev/null --max-time 20 -H "Accept: $ACCEPT_HEADER")
[[ "$REGISTRY_INSECURE" == "true" ]] && curl_opts+=(-k)

# Split "<repo>:<tag>" / "<repo>@sha256:<digest>" honouring registry ports in
# the repo part (e.g. registry.hierocracy.home:5000/llm-gateway:2.4.11).
split_ref() {
  local ref="$1"
  if [[ "$ref" == *@sha256:* ]]; then
    REF_REPO="${ref%@*}"; REF_TAG="${ref##*@}"
  elif [[ "${ref##*/}" == *:* ]]; then
    REF_REPO="${ref%:*}"; REF_TAG="${ref##*:}"
  else
    REF_REPO="$ref"; REF_TAG="latest"
  fi
  # A plan entry may already carry a registry prefix (local-build-output does).
  # Probing is always against $REGISTRY, so strip any leading host:port/.
  if [[ "$REF_REPO" == *:*/* ]]; then
    REF_REPO="${REF_REPO#*/}"
  fi
}

missing=()
present=0
for g in "${requested_groups[@]}"; do
  [[ -n "${IMAGE_GROUPS[$g]:-}" ]] || { echo "ERROR: unknown group '$g'" >&2; exit 1; }
  for img in ${IMAGE_GROUPS[$g]}; do
    [[ -z "$img" ]] && continue
    if [[ "$img" == *__VERSION__* ]]; then
      if [[ -z "${VERSION:-}" ]]; then
        [[ "$QUIET" == "true" ]] || printf 'SKIP    %-70s (no VERSION set)\n' "$img"
        continue
      fi
      img="${img//__VERSION__/$VERSION}"
    fi
    split_ref "$img"
    code="$(curl "${curl_opts[@]}" -w '%{http_code}' \
      "$REGISTRY_SCHEME://$REGISTRY/v2/$REF_REPO/manifests/$REF_TAG" || echo 000)"
    if [[ "$code" == "200" ]]; then
      present=$((present + 1))
      [[ "$QUIET" == "true" ]] || printf 'OK      %-70s [%s]\n' "$img" "$g"
    else
      missing+=("$img")
      printf 'MISSING %-70s [%s] http=%s\n' "$img" "$g" "$code"
    fi
  done
done

echo
echo "Registry: $REGISTRY_SCHEME://$REGISTRY"
echo "Groups:   ${requested_groups[*]}"
echo "Present:  $present"
echo "Missing:  ${#missing[@]}"

if [[ ${#missing[@]} -gt 0 ]]; then
  mirror_groups=()
  local_missing="false"
  models_missing="false"
  for g in "${requested_groups[@]}"; do
    case "$g" in
      local-build-output) local_missing="true" ;;
      ollama-models)      models_missing="true" ;;
      *)                  mirror_groups+=("$g") ;;
    esac
  done
  if [[ ${#mirror_groups[@]} -gt 0 ]]; then
    echo
    echo "Mirror the upstream gaps (run on hierophant, where skopeo and the cache live):"
    echo "  APPLY=true MIRROR_GROUPS=$(IFS=,; echo "${mirror_groups[*]}") \\"
    echo "    bash scripts/mirror-all-images.sh"
  fi
  if [[ "$local_missing" == "true" ]]; then
    echo
    echo "local-build-output images are not mirrored — they come from the Kaniko"
    echo "pipeline. Build them instead:"
    echo "  bash ./rag-stack/build.sh --mode cluster --wait"
  fi
  if [[ "$models_missing" == "true" ]]; then
    echo
    echo "ollama-models are not mirrored by skopeo — they are pulled from upstream"
    echo "Ollama and pushed as OCI artifacts. Run this on hierophant BEFORE the"
    echo "install, while internet access is still in play:"
    echo "  bash rag-stack/infrastructure/ollama/push-models-to-cluster.sh"
  fi
  exit 1
fi

echo "All checked images are pre-seeded."
