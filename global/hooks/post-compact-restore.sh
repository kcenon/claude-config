#!/usr/bin/env bash
# post-compact-restore.sh
# Re-injects core/principles.md after automatic context compaction.
# Pairs with pre-compact-snapshot.sh (PreCompact event).
# Hook Type: PostCompact (sync)
# Exit codes: 0 (always — context delivered via JSON)
# Response format: hookSpecificOutput.additionalContext

set -euo pipefail

# --- Logging (mirrors pre-compact-snapshot.sh contract) ---
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/compact-snapshots.log"
mkdir -p "$LOG_DIR"
{
    echo "=== PostCompact Restore ==="
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Session: ${CLAUDE_SESSION_ID:-unknown}"
    echo "Working Dir: $(pwd 2>/dev/null || echo 'unknown')"
    echo "==========================="
} >> "$LOG_FILE"

# --- Locate core/principles.md (try common installation paths) ---
PRINCIPLES_TEXT=""
for candidate in \
    "${CLAUDE_PROJECT_DIR:-}/.claude/rules/core/principles.md" \
    "${HOME}/.claude/rules/core/principles.md" \
    "$(pwd)/.claude/rules/core/principles.md" \
    "$(pwd)/../.claude/rules/core/principles.md"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
        PRINCIPLES_TEXT="$(cat "$candidate")"
        break
    fi
done

if [ -z "$PRINCIPLES_TEXT" ]; then
    PRINCIPLES_TEXT=$(cat <<'EOF'
# Core Principles

1. **Think Before Acting** — State assumptions explicitly. If uncertain, ask.
2. **Minimize & Focus** — Minimum code that solves the problem. Nothing speculative.
3. **Surgical Precision** — Touch only what you must. Clean up only your own mess.
4. **Verify & Iterate** — Define success criteria. Loop until verified.

## Behavioral Guardrails

- Stay focused on the user's original request. Note unrelated issues at the end without acting on them.
- If the same approach fails 3 times, stop and propose alternatives rather than retrying blindly.
- Bias toward execution — start making changes immediately when asked to update or edit documents.
EOF
)
fi

CONTEXT=$(cat <<EOF
## Post-Compaction Restore (auto-injected)

Context was just compacted. Re-asserting core principles to prevent drift:

${PRINCIPLES_TEXT}
EOF
)

if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ctx "$CONTEXT" '{hookSpecificOutput: {hookEventName: "PostCompact", additionalContext: $ctx}}'
else
    ESCAPED=$(printf '%s' "$CONTEXT" \
        | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
        | awk 'BEGIN{ORS="\\n"} {print}')
    printf '{"hookSpecificOutput":{"hookEventName":"PostCompact","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
