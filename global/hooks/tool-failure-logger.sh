#!/bin/bash
# Tool Failure Logger Hook
# Logs tool execution failures for debugging and analysis
#
# Environment variables available:
# - CLAUDE_TOOL_NAME: Name of the tool that failed
# - CLAUDE_TOOL_INPUT: Input provided to the tool (JSON)
# - CLAUDE_TOOL_ERROR: Error message from the tool
# - CLAUDE_SESSION_ID: Current session ID

set -euo pipefail

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/tool-failures.log"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TOOL_NAME="${CLAUDE_TOOL_NAME:-unknown}"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

{
    echo "=== Tool Failure at ${TIMESTAMP} ==="
    echo "Session: ${SESSION_ID}"
    echo "Tool: ${TOOL_NAME}"
    if [ -n "${CLAUDE_TOOL_ERROR:-}" ]; then
        echo "Error: ${CLAUDE_TOOL_ERROR}"
    fi
    echo "---"
} >> "$LOG_FILE"

exit 0
