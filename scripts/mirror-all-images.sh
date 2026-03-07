#!/bin/bash
# mirror-all-images.sh
# Mirror install/runtime images into local registry based on explicit dependency groups.
# Default mode is DRY RUN. Set APPLY=true to execute copies.

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLAN_FILE="${PLAN_FILE:-$SCRIPT_DIR/install-image-plan.sh}"
TARGET_REGISTRY="${TARGET_REGISTRY:-registry.hierocracy.home:5000}"
APPLY="${APPLY:-false}"
PARALLELISM="${PARALLELISM:-3}"
SKOPEO_TLS_VERIFY="${SKOPEO_TLS_VERIFY:-false}"
GROUPS_CSV="${MIRROR_GROUPS:-}"
STEP_NAME="${STEP:-}"
LIST_GROUPS="false"
LIST_STEPS="false"
TIMING_LOG="${TIMING_LOG:-$HOME/.complete-build/journal/mirror-all-images-timing.log}"

log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || {
    echo "ERROR: required command missing: $c" >&2
    exit 1
  }
}

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--group <name>]... [--step <step>] [--apply]
  $(basename "$0") --list-groups
  $(basename "$0") --list-steps

Env:
  APPLY=true|false                 Execute copy or dry-run (default false)
  MIRROR_GROUPS=g1,g2              Comma-separated groups (alternative to --group)
  STEP=<step-name>                 Pull images for an install step
  TARGET_REGISTRY=host:port        Destination registry prefix
  PARALLELISM=3                    xargs parallelism for apply mode
  SKOPEO_TLS_VERIFY=false          Destination TLS verify flag
  PLAN_FILE=.../install-image-plan.sh
  TIMING_LOG=.../mirror-timing.log Timing output log path
USAGE
}

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: PLAN_FILE not found: $PLAN_FILE" >&2
  exit 1
fi
source "$PLAN_FILE"

requested_groups=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --group)
      shift
      requested_groups+=("${1:-}")
      ;;
    --step)
      shift
      STEP_NAME="${1:-}"
      ;;
    --apply)
      APPLY="true"
      ;;
    --list-groups)
      LIST_GROUPS="true"
      ;;
    --list-steps)
      LIST_STEPS="true"
      ;;
    --help|-h)
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

if [[ "$LIST_GROUPS" == "true" ]]; then
  plan_groups
  exit 0
fi

if [[ "$LIST_STEPS" == "true" ]]; then
  plan_steps
  exit 0
fi

# collect from env GROUPS
if [[ -n "$GROUPS_CSV" ]]; then
  IFS=',' read -r -a env_groups <<< "$GROUPS_CSV"
  requested_groups+=("${env_groups[@]}")
fi

# collect from step mapping
if [[ -n "$STEP_NAME" ]]; then
  step_groups="$(plan_groups_for_step "$STEP_NAME")"
  if [[ -z "$step_groups" ]]; then
    echo "ERROR: no groups mapped for step '$STEP_NAME'" >&2
    exit 1
  fi
  for g in $step_groups; do
    requested_groups+=("$g")
  done
fi

# default: all groups except local-build-output
if [[ ${#requested_groups[@]} -eq 0 ]]; then
  while IFS= read -r g; do
    [[ "$g" == "local-build-output" ]] && continue
    requested_groups+=("$g")
  done < <(plan_groups)
fi

# validate/dedupe groups preserving order
groups=()
declare -A seen_group
for g in "${requested_groups[@]}"; do
  [[ -z "$g" ]] && continue
  if [[ -z "${IMAGE_GROUPS[$g]:-}" ]]; then
    echo "ERROR: unknown group '$g'" >&2
    exit 1
  fi
  if [[ -z "${seen_group[$g]:-}" ]]; then
    groups+=("$g")
    seen_group[$g]=1
  fi
done

# collect/dedupe images preserving order
images=()
declare -A seen_image
for g in "${groups[@]}"; do
  for img in ${IMAGE_GROUPS[$g]}; do
    [[ -z "$img" ]] && continue
    if [[ -z "${seen_image[$img]:-}" ]]; then
      images+=("$img")
      seen_image[$img]=1
    fi
  done
done

log "Plan file: $PLAN_FILE"
log "Target registry: $TARGET_REGISTRY"
log "Mode: $([[ "$APPLY" == "true" ]] && echo APPLY || echo DRY-RUN)"
log "Groups: ${groups[*]}"
log "Images: ${#images[@]}"

if [[ -n "$STEP_NAME" ]]; then
  next_step="$(plan_next_step "$STEP_NAME" || true)"
  if [[ -n "${next_step:-}" ]]; then
    next_groups="$(plan_groups_for_step "$next_step")"
    log "Next recommended prefetch: step=$next_step groups=${next_groups:-none}"
  else
    log "Next recommended prefetch: none (step '$STEP_NAME' is last in plan)"
  fi
fi

if [[ ${#images[@]} -eq 0 ]]; then
  log "No images selected."
  exit 0
fi

mkdir -p "$(dirname "$TIMING_LOG")"
touch "$TIMING_LOG"
chmod 600 "$TIMING_LOG" 2>/dev/null || true
run_start_epoch="$(date +%s)"
run_start_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf "timing|run_start|time=%s|mode=%s|groups=%s|images=%s\n" \
  "$run_start_iso" "$APPLY" "${groups[*]}" "${#images[@]}" >> "$TIMING_LOG"

copy_cmd() {
  local src="$1"
  local dst="$TARGET_REGISTRY/$src"
  echo "skopeo copy --all --dest-tls-verify=$SKOPEO_TLS_VERIFY docker://$src docker://$dst"
}

if [[ "$APPLY" != "true" ]]; then
  for img in "${images[@]}"; do
    copy_cmd "$img"
  done
  run_end_epoch="$(date +%s)"
  run_end_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf "timing|run_end|time=%s|mode=%s|duration_seconds=%s|status=dry-run\n" \
    "$run_end_iso" "$APPLY" "$((run_end_epoch - run_start_epoch))" >> "$TIMING_LOG"
  log "Timing log updated: $TIMING_LOG"
  exit 0
fi

require_cmd skopeo

timing_tmp_dir="$(mktemp -d)"
cleanup_tmp() { rm -rf "$timing_tmp_dir"; }
trap cleanup_tmp EXIT

set +e
printf '%s\n' "${images[@]}" | xargs -n1 -P "$PARALLELISM" -I{} bash -c '
  set -Eeuo pipefail
  src="$1"
  target_registry="$2"
  tls_verify="$3"
  timing_dir="$4"
  dst="$target_registry/$src"

  start_epoch="$(date +%s)"
  start_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  status="ok"
  err_msg=""

  if ! skopeo copy --all --dest-tls-verify="$tls_verify" "docker://$src" "docker://$dst"; then
    status="fail"
    err_msg="copy_failed"
  fi

  end_epoch="$(date +%s)"
  end_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  duration=$((end_epoch - start_epoch))
  printf "timing|image=%s|status=%s|start=%s|end=%s|duration_seconds=%s|error=%s\n" \
    "$src" "$status" "$start_iso" "$end_iso" "$duration" "$err_msg" \
    > "$timing_dir/${src//\//_}.timing"

  if [[ "$status" != "ok" ]]; then
    exit 1
  fi
' _ {} "$TARGET_REGISTRY" "$SKOPEO_TLS_VERIFY" "$timing_tmp_dir"
copy_rc=$?
set -e

for timing_file in "$timing_tmp_dir"/*.timing; do
  [[ -f "$timing_file" ]] || continue
  cat "$timing_file" >> "$TIMING_LOG"
done

run_end_epoch="$(date +%s)"
run_end_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
run_status="ok"
if [[ "$copy_rc" -ne 0 ]]; then
  run_status="fail"
fi
printf "timing|run_end|time=%s|mode=%s|duration_seconds=%s|status=%s\n" \
  "$run_end_iso" "$APPLY" "$((run_end_epoch - run_start_epoch))" "$run_status" >> "$TIMING_LOG"

log "Timing log updated: $TIMING_LOG"
log "Mirror run complete."
exit "$copy_rc"
