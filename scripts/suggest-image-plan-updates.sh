#!/bin/bash
# suggest-image-plan-updates.sh
#
# Check image tags in install-image-plan.sh against upstream registries,
# propose newer versions, and interactively apply approved updates.

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLAN_FILE_DEFAULT="$SCRIPT_DIR/install-image-plan.sh"
PLAN_FILE="${PLAN_FILE:-$PLAN_FILE_DEFAULT}"
UPDATE_RELATED="${UPDATE_RELATED:-ask}"   # ask|yes|no
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
LATEST_ONLY="${LATEST_ONLY:-false}"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--plan-file <path>] [--update-related ask|yes|no] [--non-interactive] [--latest-only]

Options:
  --plan-file <path>          Path to install-image-plan.sh
  --update-related <mode>     Whether to update matching fixed refs in other files
                              ask (default), yes, no
  --non-interactive           Do not prompt; print suggestions only
  --latest-only               Only process refs currently tagged :latest
  -h, --help                  Show help

Env:
  PLAN_FILE                   Same as --plan-file
  UPDATE_RELATED=ask|yes|no
  NON_INTERACTIVE=true|false
  LATEST_ONLY=true|false

Requirements:
  skopeo, jq, sort, grep, sed
USAGE
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || {
    echo "ERROR: required command missing: $c" >&2
    exit 1
  }
}

escape_sed_repl() {
  echo "$1" | sed -e 's/[\\&]/\\&/g' -e 's/#/\\#/g'
}

is_semver_like() {
  local t="$1"
  [[ "$t" =~ ^v?[0-9]+(\.[0-9]+){1,3}$ ]]
}

norm_ver() {
  local t="$1"
  echo "${t#v}"
}

latest_semver_tag() {
  local repo="$1"
  local current_tag="$2"

  local tags_json
  if ! tags_json="$(skopeo list-tags "docker://$repo" 2>/dev/null)"; then
    return 1
  fi

  local rows
  rows="$(printf '%s' "$tags_json" | jq -r '.Tags[]?' | while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    [[ "$tag" == "latest" ]] && continue
    if is_semver_like "$tag"; then
      printf '%s|%s\n' "$(norm_ver "$tag")" "$tag"
    fi
  done)"

  [[ -n "$rows" ]] || return 1

  printf '%s\n' "$rows" | sort -t'|' -k1,1V | tail -n1 | cut -d'|' -f2
}

parse_refs_from_plan() {
  # Extract IMAGE_GROUPS values and split by whitespace.
  # shellcheck disable=SC2016
  grep -E '^IMAGE_GROUPS\[[^]]+\]="' "$PLAN_FILE" \
    | sed -E 's/^[^=]+="(.*)"$/\1/' \
    | tr ' ' '\n' \
    | sed '/^$/d'
}

update_ref_in_file() {
  local file="$1"
  local old_ref="$2"
  local new_ref="$3"
  local old_esc new_esc
  old_esc="$(escape_sed_repl "$old_ref")"
  new_esc="$(escape_sed_repl "$new_ref")"
  sed -i "s#${old_esc}#${new_esc}#g" "$file"
}

find_related_files() {
  local old_ref="$1"
  grep -RIl \
    --exclude-dir=.git \
    --exclude "$(basename "$PLAN_FILE")" \
    -- "$old_ref" . || true
}

prompt_yes_no() {
  local q="$1"
  local default_no="${2:-true}"
  local reply

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    return 1
  fi

  if [[ -r /dev/tty ]]; then
    read -r -p "$q " reply < /dev/tty
  else
    # Fallback when no controlling tty exists.
    read -r -p "$q " reply
  fi
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    *)
      if [[ "$default_no" == "true" ]]; then
        return 1
      fi
      return 0
      ;;
  esac
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan-file)
        shift
        PLAN_FILE="${1:-}"
        ;;
      --update-related)
        shift
        UPDATE_RELATED="${1:-ask}"
        ;;
      --non-interactive)
        NON_INTERACTIVE="true"
        ;;
      --latest-only)
        LATEST_ONLY="true"
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

  [[ -f "$PLAN_FILE" ]] || {
    echo "ERROR: PLAN_FILE not found: $PLAN_FILE" >&2
    exit 1
  }

  require_cmd skopeo
  require_cmd jq
  require_cmd sort
  require_cmd grep
  require_cmd sed

  echo "Plan file: $PLAN_FILE"
  echo "Checking image tags against upstream registries..."

  local refs
  refs="$(parse_refs_from_plan | sort -u)"

  local total=0 suggestions=0 applied=0 related_updates=0 skipped=0 latest_refs_scanned=0

  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    total=$((total + 1))

    # Skip local build placeholders
    if [[ "$ref" == *"__VERSION__"* ]]; then
      continue
    fi
    if [[ "$ref" == registry.hierocracy.home:5000/* ]]; then
      continue
    fi
    if [[ "$ref" != *":"* ]]; then
      continue
    fi

    local repo tag
    repo="${ref%:*}"
    tag="${ref##*:}"

    if [[ "$LATEST_ONLY" == "true" && "$tag" != "latest" ]]; then
      continue
    fi

    if [[ "$tag" != "latest" ]] && ! is_semver_like "$tag"; then
      continue
    fi

    local latest_tag
    if ! latest_tag="$(latest_semver_tag "$repo" "$tag")"; then
      echo "- WARN: unable to fetch/resolve tags for $repo (current: $tag)"
      continue
    fi
    if [[ "$tag" == "latest" ]]; then
      latest_refs_scanned=$((latest_refs_scanned + 1))
    fi

    local current_norm latest_norm
    current_norm="$(norm_ver "$tag")"
    latest_norm="$(norm_ver "$latest_tag")"

    if [[ "$tag" != "latest" ]]; then
      if [[ "$current_norm" == "$latest_norm" ]]; then
        continue
      fi

      # latest is newer if it sorts after current
      if [[ "$(printf '%s\n%s\n' "$current_norm" "$latest_norm" | sort -V | tail -n1)" != "$latest_norm" ]]; then
        continue
      fi
    fi

    suggestions=$((suggestions + 1))
    local new_ref="${repo}:${latest_tag}"

    echo ""
    echo "Suggestion $suggestions:"
    echo "  $ref"
    echo "  -> $new_ref"

    local do_update=1
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
      if ! prompt_yes_no "Apply this update? [y/N]" true; then
        do_update=0
      fi
    else
      do_update=0
    fi

    if [[ "$do_update" -eq 0 ]]; then
      skipped=$((skipped + 1))
      continue
    fi

    update_ref_in_file "$PLAN_FILE" "$ref" "$new_ref"
    applied=$((applied + 1))

    local related_files
    related_files="$(find_related_files "$ref")"
    if [[ -n "$related_files" ]]; then
      local update_related_now=0
      case "$UPDATE_RELATED" in
        yes) update_related_now=1 ;;
        no) update_related_now=0 ;;
        ask)
          if prompt_yes_no "Also update matching fixed refs in other files? [y/N]" true; then
            update_related_now=1
          fi
          ;;
        *) update_related_now=0 ;;
      esac

      if [[ "$update_related_now" -eq 1 ]]; then
        while IFS= read -r f; do
          [[ -z "$f" ]] && continue
          update_ref_in_file "$f" "$ref" "$new_ref"
          related_updates=$((related_updates + 1))
          echo "  updated: $f"
        done <<< "$related_files"
      fi
    fi
  done <<< "$refs"

  echo ""
  echo "Done."
  echo "  Images scanned:      $total"
  echo "  Suggestions found:   $suggestions"
  echo "  Updates applied:     $applied"
  echo "  Latest refs scanned: $latest_refs_scanned"
  echo "  Related files updated: $related_updates"
  echo "  Suggestions skipped: $skipped"

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    echo "(Non-interactive mode: suggestions only; no file changes applied.)"
  fi
}

main "$@"
