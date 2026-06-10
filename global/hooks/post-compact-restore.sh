#!/usr/bin/env bash
# post-compact-restore.sh
# Re-asserts the four core principles after automatic context compaction.
# Pairs with pre-compact-snapshot.sh (PreCompact event).
# Hook Type: SessionStart (matcher: compact, sync)
# Exit codes: 0 (always - silent no-op unless stdin source is "compact")
# Response format: hookSpecificOutput.additionalContext
# Fail policy: fails quiet - no JSON parser or non-compact source means no output

set -euo pipefail

INPUT=$(cat || true)

# Defense in depth (issue #720): the settings matcher ("compact") already
# filters SessionStart invocations, but stay silent if the hook is ever
# wired without a matcher so startup/resume/clear sessions are not spammed.
SOURCE=""
if [ -n "$INPUT" ]; then
    if command -v jq >/dev/null 2>&1; then
        SOURCE=$(printf '%s' "$INPUT" | jq -r '.source? // empty' 2>/dev/null) || SOURCE=""
    elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        PY=$(command -v python3 || command -v python)
        SOURCE=$(printf '%s' "$INPUT" | "$PY" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = d.get("source") if isinstance(d, dict) else None
if isinstance(v, str):
    sys.stdout.write(v)
' 2>/dev/null) || SOURCE=""
    fi
fi

if [ "$SOURCE" != "compact" ]; then
    exit 0
fi

# --- Logging (mirrors pre-compact-snapshot.sh contract) ---
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/compact-snapshots.log"
mkdir -p "$LOG_DIR"
{
    echo "=== Post-Compact Restore ==="
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Session: ${CLAUDE_SESSION_ID:-unknown}"
    echo "Working Dir: $(pwd 2>/dev/null || echo 'unknown')"
    echo "==========================="
} >> "$LOG_FILE"

# Fixed short digest (issue #720): the PostCompact event does not support
# hookSpecificOutput, so this hook listens on SessionStart (source ==
# "compact") - the official channel for injecting context after compaction.
# Keep the payload to a few lines and never read rule files into it.
# Must stay byte-equivalent to the digest in post-compact-restore.ps1.
DIGEST=$(cat <<'EOF'
## Post-Compaction Restore (digest)

Context was just compacted. Re-asserting the four core principles:

1. Think Before Acting - state assumptions explicitly; if uncertain, ask.
2. Minimize & Focus - minimum code that solves the problem; nothing speculative.
3. Surgical Precision - touch only what you must; clean up only your own mess.
4. Verify & Iterate - define success criteria; loop until verified.

Self-check: "Would a senior engineer say this diff is focused, minimal, and well-verified?"
EOF
)

# Emit JSON via jq if available (safe escaping); fall back to manual escaping.
if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ctx "$DIGEST" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
    ESCAPED=$(printf '%s' "$DIGEST" \
        | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
        | awk 'BEGIN{ORS="\\n"} {print}')
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
