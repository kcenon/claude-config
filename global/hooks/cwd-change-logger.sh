#!/bin/bash
# Cwd Change Logger Hook
# Logs working-directory changes during a session for audit trails.
#
# Hook Type: CwdChanged
# Input: JSON via stdin with session_id, cwd, transcript_path, hook_event_name
# Response format: none (observation-only event; CwdChanged cannot block, exit 2 only shows stderr)

set -euo pipefail

INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/session.log"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[${TIMESTAMP}] Session ${SESSION_ID}: CWD_CHANGED cwd=${CWD}" >> "$LOG_FILE"

exit 0
