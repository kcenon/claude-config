#!/bin/bash
# Post Task/Agent Checkpoint Hook
# ================================
# Auto-commits working-tree changes after a Task or Agent tool call completes,
# preventing a later sub-agent from silently overwriting a prior agent's output.
#
# Hook Type: PostToolUse
# Matcher: Task|Agent
# Input: JSON via stdin with tool_name, tool_input, tool_response
# Decision: always fail-open (exit 0) — never block the workflow
#
# Behavior:
#   - Skips non-Task / non-Agent invocations silently
#   - No-op if not inside a git worktree
#   - No-op if the worktree is clean (avoids empty-commit spam)
#   - Otherwise: git add -A && git commit with --no-verify --allow-empty
#     The --no-verify bypass is intentional: WIP messages use `wip(agent):`
#     which the commit-msg validator would reject. These checkpoint commits
#     are throwaway and squashed at release time.

set -uo pipefail

# Read stdin (may be empty for synthetic invocations).
INPUT=$(cat 2>/dev/null || true)

# Fail-open if core tools missing.
command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# Only checkpoint after Task or Agent tool calls.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
case "$TOOL_NAME" in
    Task|Agent) ;;
    *) exit 0 ;;
esac

# Must be inside a git worktree.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Skip when the tree is clean.
if git diff --quiet 2>/dev/null \
   && git diff --cached --quiet 2>/dev/null \
   && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    exit 0
fi

# Extract agent name from tool input; prefer subagent_type, fall back to name.
AGENT_NAME=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // .tool_input.name // "agent"' 2>/dev/null || echo "agent")
# Sanitize: alphanumerics, dash, underscore only; clip to 64 chars.
AGENT_NAME=$(printf '%s' "$AGENT_NAME" | tr -cd '[:alnum:]_-' | cut -c1-64)
[ -z "$AGENT_NAME" ] && AGENT_NAME="agent"

TS=$(date '+%Y-%m-%d %H:%M:%S')

# Stage and commit. Suppress all output; fail-open on any error.
{
    git add -A
    git commit -m "wip(agent): ${AGENT_NAME} checkpoint ${TS}" --no-verify --allow-empty
} >/dev/null 2>&1 || true

exit 0
