#!/bin/bash
# session-logger.sh
# Logs session start/end events
# Hook Type: SessionStart, SessionEnd, Stop
# Usage: session-logger.sh [start|end|stop]
# Response format: hookSpecificOutput (modern format)

LOG_FILE="${HOME}/.claude/session.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

case "${1:-}" in
    start)
        echo "[Session] Claude Code session started: $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null
        ;;
    end)
        echo "[Session] Claude Code session ended: $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null
        ;;
    stop)
        echo "[Stop] Claude Code task stopped: $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null
        ;;
    *)
        echo "[Session] Claude Code event: $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null
        ;;
esac

# Output modern response format
cat <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
EOF
exit 0
