#!/bin/bash
# WorktreeRemove Hook
# Cleans up and logs worktree removal events
#
# Hook Type: WorktreeRemove (async, type: command only)
# Triggers when a worktree is being removed/cleaned up
# Cannot block removal — cleanup and logging only
#
# Input (stdin): JSON with worktree_path field

set -euo pipefail

LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR"

# Read worktree path from stdin JSON if available
WORKTREE_PATH=""
if read -t 1 INPUT 2>/dev/null; then
    WORKTREE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('worktree_path',''))" 2>/dev/null || echo "")
fi
WORKTREE_PATH="${WORKTREE_PATH:-${CLAUDE_WORKTREE_PATH:-unknown}}"

# Log removal event
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worktree removed"
    echo "  Path: ${WORKTREE_PATH}"
} >> "${LOG_DIR}/worktrees.log"

exit 0
