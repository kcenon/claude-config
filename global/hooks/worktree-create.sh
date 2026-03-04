#!/bin/bash
# WorktreeCreate Hook
# Creates an isolated worktree directory for non-git environments
#
# Hook Type: WorktreeCreate (synchronous, type: command only)
# Triggers when worktree isolation is requested outside a git repository
#
# IMPORTANT: Must print the absolute path of the created worktree to stdout.
# Non-zero exit code fails the worktree creation.
#
# Input (stdin): JSON with worktree creation context
# Output (stdout): Absolute path to the created worktree directory

set -euo pipefail

LOG_DIR="${HOME}/.claude/logs"
WORKTREE_BASE="${HOME}/.claude/worktrees"
mkdir -p "$LOG_DIR" "$WORKTREE_BASE"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
SOURCE_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Create unique worktree directory
WORKTREE_DIR="${WORKTREE_BASE}/${TIMESTAMP}_$$"
mkdir -p "$WORKTREE_DIR"

# Log creation event
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worktree created"
    echo "  Path: ${WORKTREE_DIR}"
    echo "  Source: ${SOURCE_DIR}"
    echo "  Session: ${SESSION_ID}"
} >> "${LOG_DIR}/worktrees.log"

# Output the created worktree path (REQUIRED by WorktreeCreate contract)
echo "$WORKTREE_DIR"
