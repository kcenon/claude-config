#!/bin/bash
# Config Change Logger Hook
# Logs configuration file changes during session
#
# Hook Type: ConfigChange
# Input: JSON via stdin with source, file_path
# Response format: none (lifecycle event, no JSON output needed)

set -euo pipefail

INPUT=$(cat)

SOURCE=$(echo "$INPUT" | jq -r '.source // "unknown"')
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/session.log"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[${TIMESTAMP}] Session ${SESSION_ID}: CONFIG_CHANGED source=${SOURCE} file=${FILE_PATH}" >> "$LOG_FILE"

exit 0
