#!/usr/bin/env bash

read_current_version() {
  local file="$1"
  local service="${2:-}"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  if jq . "$file" >/dev/null 2>&1; then
    if [[ -n "$service" ]]; then
      jq -r --arg svc "$service" '.[$svc].version // empty' "$file"
      return 0
    fi

    local fallback
    fallback=$(jq -r '.["build-orchestrator"].version // (. | to_entries | sort_by(.key) | .[0].value.version // empty)' "$file")
    if [[ -n "$fallback" && "$fallback" != "null" ]]; then
      printf '%s\n' "$fallback"
      return 0
    fi
  fi

  tr -d '[:space:]' < "$file"
}
