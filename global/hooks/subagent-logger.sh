#!/bin/bash
# Subagent Logger Hook
# Logs subagent start/stop events for monitoring
#
# Usage: subagent-logger.sh <start|stop>
#
# Environment variables available:
# - CLAUDE_SUBAGENT_TYPE: Type of subagent (e.g., "Bash", "Explore", "Plan")
# - CLAUDE_SESSION_ID: Current session ID

set -euo pipefail

ACTION="${1:-unknown}"
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/subagents.log"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SUBAGENT_TYPE="${CLAUDE_SUBAGENT_TYPE:-unknown}"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

echo "[${TIMESTAMP}] Session ${SESSION_ID}: Subagent ${ACTION} - ${SUBAGENT_TYPE}" >> "$LOG_FILE"

exit 0
