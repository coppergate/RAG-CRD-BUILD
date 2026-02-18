#!/bin/bash

# journal-helper.sh - Helper functions for journaling installation steps

# Use /tmp for journal files to ensure they are writable regardless of mount permissions
JOURNAL_FILE_DIR="/tmp"
JOURNAL_FILE="$JOURNAL_FILE_DIR/.install_journal"

function init_journal() {
    local script_name=$(basename "$0")
    JOURNAL_FILE="$JOURNAL_FILE_DIR/.${script_name}_journal"
    
    if [[ -f "$JOURNAL_FILE" ]]; then
        echo "Journal file '$JOURNAL_FILE' exists from a previous run."
        if [[ "$FRESH_INSTALL" == "true" ]]; then
            rm "$JOURNAL_FILE"
            echo "FRESH_INSTALL=true detected. Starting fresh..."
        else
            echo "Continuing from last failure (Set FRESH_INSTALL=true to start fresh)..."
        fi
    fi
}

function is_step_done() {
    local step_name="$1"
    if [[ -f "$JOURNAL_FILE" ]] && grep -q "^$step_name$" "$JOURNAL_FILE"; then
        echo "Skipping already completed step: $step_name"
        return 0
    fi
    return 1
}

function mark_step_done() {
    local step_name="$1"
    echo "$step_name" >> "$JOURNAL_FILE"
    echo "Completed step: $step_name"
}

function clear_journal() {
    if [[ -f "$JOURNAL_FILE" ]]; then
        rm "$JOURNAL_FILE"
        echo "Installation complete. Journal cleared."
    fi
}
