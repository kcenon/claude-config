#!/bin/bash
# Task Completed Logger Hook
# Logs task completion events for audit trail
#
# Hook Type: TaskCompleted
# Input: JSON via stdin with task_id, task_subject, task_description
# Decision control: exit code (0=allow, 2=block)

set -euo pipefail

INPUT=$(cat)

TASK_ID=$(echo "$INPUT" | jq -r '.task_id // "unknown"')
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/tasks.log"

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[${TIMESTAMP}] Session ${SESSION_ID}: Task #${TASK_ID} completed - ${TASK_SUBJECT}" >> "$LOG_FILE"

exit 0
