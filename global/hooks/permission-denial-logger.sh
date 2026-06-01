#!/bin/bash
# permission-denial-logger.sh
# Appends a redacted JSONL audit record for every denied tool call.
# Hook Type: PermissionDenied
# Exit codes: 0 (always — passive logger, never alters the permission decision)
# Response format: none (observation-only event; no JSON emitted, never blocks)
# Fail policy: best-effort; logging failures are swallowed and never surface
#
# Behavior:
#   Reads the official PermissionDenied payload from stdin
#   ({ tool_name, tool_input, permission_suggestions }), redacts secrets from
#   tool_input, and appends one JSON line to
#   ${CLAUDE_LOG_DIR:-$HOME/.claude/logs}/permission-denials.jsonl.
#   The hook is purely passive: it emits no permission-altering output and
#   always exits 0, mirroring the logging-style hooks (config-change-logger,
#   tool-failure-logger) rather than the gating guards.
#
# Opt-out:
#   Set CLAUDE_PERMISSION_LOGGER=0 to disable (early no-op exit).
#
# Privacy / security:
#   Secrets in tool_input (tokens, API keys, Authorization headers, URL
#   credentials, ~/.ssh/ key contents, etc.) are scrubbed before the write so
#   raw tool_input never reaches disk. The log is tail-rotated at 10 MB via
#   lib/rotate.sh to bound growth (see docs/design/permission-event-hooks.md).

set -euo pipefail

# Opt-out switch: a single "0" disables the logger entirely.
if [ "${CLAUDE_PERMISSION_LOGGER:-1}" = "0" ]; then
    exit 0
fi

LOG_DIR="${CLAUDE_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/permission-denials.jsonl"

# Redact secrets from an arbitrary string. The pattern set targets the high-risk
# shapes that show up in tool_input: bearer/authorization headers, common
# token/key/secret/password assignments (env-style and JSON-style), URL inline
# credentials, AWS-style access keys, GitHub PATs, and private-key PEM blocks.
# A self-contained scrubber is used because there is no shared redaction library
# in the repo to reuse yet (see PR notes / issue #691); keep it conservative —
# over-redaction is preferable to leaking a credential.
redact_secrets() {
    sed -E \
        -e 's/(authorization)([[:space:]:=]+)(bearer|token|basic)?[[:space:]]*[A-Za-z0-9._~+/=-]+/\1\2<REDACTED>/Ig' \
        -e 's/(bearer)([[:space:]]+)[A-Za-z0-9._~+/=-]+/\1\2<REDACTED>/Ig' \
        -e 's/((api[_-]?key|access[_-]?key|secret|token|password|passwd|pwd|client[_-]?secret|refresh[_-]?token)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?)[^"'"'"'[:space:],}&]+/\1<REDACTED>/Ig' \
        -e 's#(://[^/[:space:]:@]+):[^/[:space:]@]+@#\1:<REDACTED>@#g' \
        -e 's/\b(AKIA|ASIA)[A-Z0-9]{16}\b/\1<REDACTED>/g' \
        -e 's/\b(gh[pousr]_)[A-Za-z0-9]{20,}/\1<REDACTED>/g' \
        -e 's/-----BEGIN[^-]*PRIVATE KEY-----[^-]*-----END[^-]*PRIVATE KEY-----/<REDACTED PRIVATE KEY>/g'
}

# Best-effort log writer. Never fail the (already-made) permission decision on a
# logging error — every disk touch is guarded.
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

# Tail-rotate at 10 MB so the audit trail cannot grow unbounded.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
if [ -f "$LIB_DIR/rotate.sh" ]; then
    # shellcheck source=lib/rotate.sh
    . "$LIB_DIR/rotate.sh"
    rotate_log "$LOG_FILE" 10 5 2>/dev/null || true
fi

INPUT=$(cat 2>/dev/null || true)

TS=$(date +"%Y-%m-%dT%H:%M:%S%z")

# Without jq we cannot safely parse or re-emit JSON; record a minimal marker
# rather than risk writing a malformed or unredacted line.
if ! command -v jq >/dev/null 2>&1; then
    printf '{"ts":"%s","tool_name":"unknown","note":"jq unavailable — payload not parsed"}\n' \
        "$TS" >>"$LOG_FILE" 2>/dev/null || true
    exit 0
fi

# Empty / unparseable stdin: log a marker line and exit cleanly.
if [ -z "$INPUT" ] || ! echo "$INPUT" | jq -e . >/dev/null 2>&1; then
    jq -cn --arg ts "$TS" \
        '{ts:$ts, tool_name:"unknown", note:"empty or unparseable hook input"}' \
        >>"$LOG_FILE" 2>/dev/null || true
    exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")

# Redact secrets inside tool_input. The value is serialized to a compact JSON
# string, scrubbed textually, then re-parsed. If re-parsing fails (e.g. the
# scrub disturbed the structure), fall back to a flat redacted string so the
# record is always valid JSON and never carries a raw secret.
TOOL_INPUT_RAW=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null || echo '{}')
TOOL_INPUT_REDACTED=$(printf '%s' "$TOOL_INPUT_RAW" | redact_secrets)

SUGGESTIONS=$(echo "$INPUT" | jq -c '.permission_suggestions // []' 2>/dev/null || echo '[]')

if echo "$TOOL_INPUT_REDACTED" | jq -e . >/dev/null 2>&1; then
    jq -cn \
        --arg ts "$TS" \
        --arg session_id "$SESSION_ID" \
        --arg tool_name "$TOOL_NAME" \
        --argjson tool_input_redacted "$TOOL_INPUT_REDACTED" \
        --argjson permission_suggestions "$SUGGESTIONS" \
        '{ts:$ts, session_id:$session_id, tool_name:$tool_name, tool_input_redacted:$tool_input_redacted, permission_suggestions:$permission_suggestions}' \
        >>"$LOG_FILE" 2>/dev/null || true
else
    jq -cn \
        --arg ts "$TS" \
        --arg session_id "$SESSION_ID" \
        --arg tool_name "$TOOL_NAME" \
        --arg tool_input_redacted "$TOOL_INPUT_REDACTED" \
        --argjson permission_suggestions "$SUGGESTIONS" \
        '{ts:$ts, session_id:$session_id, tool_name:$tool_name, tool_input_redacted:$tool_input_redacted, permission_suggestions:$permission_suggestions}' \
        >>"$LOG_FILE" 2>/dev/null || true
fi

exit 0
