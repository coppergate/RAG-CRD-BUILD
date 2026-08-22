#!/bin/bash

# journal-helper.sh - Helper functions for journaling installation steps
# Goal:
# - Avoid permission issues and collisions between different scripts with the same name (e.g., install.sh)
# - Prefer per-user writable location, overridable via INSTALL_JOURNAL_DIR

# Determine journal directory (override with INSTALL_JOURNAL_DIR, else global dir)
GLOBAL_JOURNAL_ROOT="$HOME/.complete-build/journal"
JOURNAL_FILE_DIR="${INSTALL_JOURNAL_DIR:-$GLOBAL_JOURNAL_ROOT}"

# Determine a safe temporary directory for the user (override with INSTALL_TMP_DIR)
# Prefer per-user /tmp directory to avoid permission issues in shared environments
SAFE_TMP_DIR="${INSTALL_TMP_DIR:-/tmp/k8s-setup-${USER:-junie}}"
export SAFE_TMP_DIR
export TMPDIR="$SAFE_TMP_DIR"

# Ensure directory exists and is shared
mkdir -p "$JOURNAL_FILE_DIR" "$SAFE_TMP_DIR"
chmod 777 "$JOURNAL_FILE_DIR" "$SAFE_TMP_DIR" 2>/dev/null || true

# Resolve the calling script path for uniqueness (works when sourced)
# BASH_SOURCE[0] = this file, BASH_SOURCE[1] = caller when sourced; fall back to $0
__caller_ref="${BASH_SOURCE[1]:-${0}}"
# Try to canonicalize the path; if not possible, keep as-is
if command -v readlink >/dev/null 2>&1; then
  __caller_abs="$(readlink -f "${__caller_ref}" 2>/dev/null || echo "${__caller_ref}")"
else
  __caller_abs="${__caller_ref}"
fi
__script_name="$(basename "${__caller_abs}")"
# Short unique suffix from the absolute path to avoid collisions across identically named scripts
__script_id="$(echo -n "${__caller_abs}" | sha256sum 2>/dev/null | cut -c1-12)"
JOURNAL_FILE="${JOURNAL_FILE_DIR}/${__script_name}-${__script_id}.journal"

function init_journal() {
    if [[ -f "$JOURNAL_FILE" ]]; then
        echo "Journal file '$JOURNAL_FILE' exists from a previous run."
        if [[ "${FRESH_INSTALL:-false}" == "true" ]]; then
            rm -f "$JOURNAL_FILE"
            echo "FRESH_INSTALL=true detected. Starting fresh..."
        else
            echo "Continuing from last failure (Set FRESH_INSTALL=true to start fresh)..."
        fi
    fi
    echo "Using journal: $JOURNAL_FILE"
}

# is_step_done <step_name> [verify_command...]
#
# Returns 0 (skip the step) only when the journal says the step ran AND — if a
# verify command is supplied — that command still succeeds.
#
# WHY THE VERIFY ARGUMENT EXISTS
# The journal is a write-ahead record of intent: mark_step_done appends a line
# and nothing ever checks that the step's output still exists. The journal lives
# in $HOME, but the thing it describes lives in the cluster, and the two have
# independent lifetimes. Rebuild the cluster (or wipe a namespace) while the
# journal survives, and every step is skipped against infrastructure that is no
# longer there.
#
# That is not hypothetical. On 2026-08-09 the cluster had cert-manager, Rook and
# the registry all marked done in the journal while the cluster had no Rook CRDs,
# no StorageClasses, and empty rook-ceph / container-registry namespaces. The
# visible symptom was several layers downstream: the Pulsar install failing on
# missing cert-manager CRDs, then on a namespace that was never created.
#
# Passing a cheap read-only check makes the journal self-correcting: if the
# output is gone, the marker is ignored and the step re-runs.
#
#   is_step_done "cert-manager" $KUBECTL get crd certificates.cert-manager.io
#
# Steps called without a verify command keep the old trust-the-marker behaviour,
# so this is backward compatible.
function is_step_done() {
    local step_name="$1"
    shift || true

    if [[ ! -f "$JOURNAL_FILE" ]] || ! grep -q "^$step_name$" "$JOURNAL_FILE"; then
        return 1
    fi

    # Marker present and no verification requested — legacy behaviour.
    if [[ $# -eq 0 ]]; then
        echo "Skipping already completed step: $step_name"
        return 0
    fi

    if "$@" >/dev/null 2>&1; then
        echo "Skipping already completed step: $step_name (verified)"
        return 0
    fi

    echo "WARNING: step '$step_name' is marked done but its output is missing." >&2
    echo "         verify command failed: $*" >&2
    echo "         Re-running the step and clearing the stale journal entry." >&2
    # Drop the stale marker so mark_step_done does not create a duplicate line.
    if [[ -w "$JOURNAL_FILE" ]]; then
        sed -i "/^${step_name//\//\\/}$/d" "$JOURNAL_FILE" 2>/dev/null || true
    fi
    return 1
}

function mark_step_done() {
    local step_name="$1"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Ensure file exists with shared write perms to allow multiple users to continue
    touch "$JOURNAL_FILE"
    chmod 666 "$JOURNAL_FILE" 2>/dev/null || true
    echo "$step_name" >> "$JOURNAL_FILE"
    echo "Completed step: $step_name [$ts]"
}

function clear_journal() {
    if [[ -f "$JOURNAL_FILE" ]]; then
        rm -f "$JOURNAL_FILE"
        echo "Installation complete. Journal cleared."
    fi
}

function clear_all_journals() {
    # Clears all journal artifacts (including sub-journal directories like pulsar/)
    # under the configured journal root. Intended for FRESH_INSTALL=true flows.
    if [[ -d "$JOURNAL_FILE_DIR" ]]; then
        rm -rf "${JOURNAL_FILE_DIR:?}/"*
        echo "Cleared all journals under: $JOURNAL_FILE_DIR"
    fi
}
