#!/bin/bash
# Pre-Compact Snapshot Hook
# Captures working state before automatic context compaction
#
# Hook Type: PreCompact (async)
# Triggers when context window reaches ~95% and auto-compaction begins
#
# Environment variables available:
# - CLAUDE_SESSION_ID: Current session ID

set -euo pipefail

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/compact-snapshots.log"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
WORKING_DIR="$(pwd 2>/dev/null || echo 'unknown')"

{
    echo "=== PreCompact Snapshot ==="
    echo "Time: ${TIMESTAMP}"
    echo "Session: ${SESSION_ID}"
    echo "Working Dir: ${WORKING_DIR}"
    echo "==========================="
} >> "$LOG_FILE"

exit 0
