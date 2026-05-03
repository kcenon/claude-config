#!/bin/bash
# session-logger.sh
# Logs session start/end events
# Hook Type: SessionStart, SessionEnd, Stop, TeammateIdle
# Usage: session-logger.sh [start|end|stop|teammate-idle]
# Response format: none (lifecycle event, no JSON output needed)

set -euo pipefail

LOG_FILE="${HOME}/.claude/session.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Ensure log directory exists. Logging is best-effort — never block teardown.
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

case "${1:-}" in
    start)
        echo "[Session] Claude Code session started: $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null || true
        ;;
    end)
        echo "[Session] Claude Code session ended: $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null || true
        ;;
    stop)
        echo "[Stop] Claude Code task stopped: $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null || true
        ;;
    teammate-idle)
        echo "[TeammateIdle] Teammate went idle: $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null || true
        ;;
    *)
        echo "[Session] Claude Code event: $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null || true
        ;;
esac

exit 0
