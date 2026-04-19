#!/bin/bash
# pre-edit-read-guard.sh
# Enforces the "Read before Edit/Write" tool contract.
#
# Registered under TWO hook entries in global/settings.json:
#   1. PreToolUse  matcher "Edit|Write" → guard mode (deny when tracker lacks file_path)
#   2. PostToolUse matcher "Read"       → track mode (record file_path in tracker)
#
# The single script branches on .tool_name so only one binary ships.
#
# Tracker: $TMPDIR/claude-read-set-<session-id>
#   - One absolute path per line
#   - Cleared naturally when $TMPDIR is rotated between sessions
#   - Fail-open if absent (first-run safety; see deny_or_fail_open below)
#
# Exit codes: always 0. Decision is encoded in the JSON response for PreToolUse
# events; PostToolUse emits no JSON and is best-effort.

set -uo pipefail

# --- helpers ----------------------------------------------------------------

allow_response() {
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
    exit 0
}

deny_response() {
    local reason="$1"
    # Escape backslashes and double-quotes so the reason survives raw embedding.
    reason="${reason//\\/\\\\}"
    reason="${reason//\"/\\\"}"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
    exit 0
}

# --- parse input -------------------------------------------------------------

INPUT=$(cat 2>/dev/null || true)

# Fail-open on totally empty input — better to let the user through than to
# block every tool call when the harness has not wired stdin yet.
if [ -z "$INPUT" ]; then
    exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Resolve session id (env var preferred; fall back to JSON field).
SESSION_ID="${CLAUDE_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
fi

# Use $TMPDIR so every platform gets a writable spot; default to /tmp.
TRACKER_DIR="${TMPDIR:-/tmp}"
TRACKER="${TRACKER_DIR%/}/claude-read-set-${SESSION_ID}"

# --- branch on event ---------------------------------------------------------

case "$TOOL_NAME" in
    Read)
        # Track mode: append the Read path. Best-effort, no JSON output.
        [ -z "$FILE_PATH" ] && exit 0
        # Resolve to absolute path when possible.
        if command -v realpath >/dev/null 2>&1; then
            RESOLVED=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
        else
            RESOLVED="$FILE_PATH"
        fi
        mkdir -p "$TRACKER_DIR" 2>/dev/null || exit 0
        # Deduplicate: only append if not already present.
        if [ -f "$TRACKER" ] && grep -Fxq "$RESOLVED" "$TRACKER" 2>/dev/null; then
            exit 0
        fi
        echo "$RESOLVED" >> "$TRACKER" 2>/dev/null || true
        exit 0
        ;;

    Edit|Write)
        # Guard mode: deny unless the target has been Read this session.
        [ -z "$FILE_PATH" ] && allow_response

        if command -v realpath >/dev/null 2>&1; then
            RESOLVED=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
        else
            RESOLVED="$FILE_PATH"
        fi

        # First-run safety: if the tracker does not exist yet, allow. This
        # covers fresh sessions and harnesses that have not fired a Read yet.
        if [ ! -f "$TRACKER" ]; then
            allow_response
        fi

        # Exempt genuinely new files — Write creates them so Read is impossible.
        # Applies to Write only; Edit requires an existing file by contract.
        if [ "$TOOL_NAME" = "Write" ] && [ ! -e "$RESOLVED" ]; then
            allow_response
        fi

        # Tracker hit → allow.
        if grep -Fxq "$RESOLVED" "$TRACKER" 2>/dev/null; then
            allow_response
        fi

        # Tracker miss → deny with actionable reason.
        deny_response "Cannot ${TOOL_NAME} '${FILE_PATH}' without reading it first in this session. Call Read on '${FILE_PATH}' and retry. (Session ${SESSION_ID}, tracker ${TRACKER}.)"
        ;;

    *)
        # Unknown tool — allow to avoid interfering with other matchers.
        allow_response
        ;;
esac
