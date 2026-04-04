#!/bin/bash
# cleanup.sh
# Cleans up temporary files created during session
# Hook Type: SessionEnd
# Exit codes: 0=success
# Response format: none (lifecycle event, no JSON output needed)

# Clean up temporary Claude files (older than 60 minutes)
find "${TMPDIR:-/tmp}" -maxdepth 1 -name "claude_*" -mmin +60 -delete 2>/dev/null
find "${TMPDIR:-/tmp}" -maxdepth 1 -name "tmp.*" -user "$(whoami)" -mmin +60 -delete 2>/dev/null

# Rotate logs
source "$(dirname "$0")/lib/rotate.sh"
rotate_log "$HOME/.claude/session.log" 5 3
rotate_log "$HOME/.claude/logs/subagents.log" 5 3
rotate_log "$HOME/.claude/logs/tasks.log" 5 3
rotate_log "$HOME/.claude/logs/tool-failures.log" 5 3

exit 0
