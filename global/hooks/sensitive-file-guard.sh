#!/bin/bash
# sensitive-file-guard.sh
# Blocks access to sensitive files
# Hook Type: PreToolUse (Edit|Write|Read)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName

set -euo pipefail

# Source the shared path-utils helper (resolve_path).
# Issue #569 — consolidate canonicalization with bash-write-guard.sh.
# shellcheck source=lib/path-utils.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/path-utils.sh"

# Helper function for deny response
deny_response() {
    local reason="$1"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
    exit 0
}

# Helper function for allow response
allow_response() {
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
    exit 0
}

# Read input from stdin (Claude Code passes JSON via stdin)
INPUT=$(cat)

# Fail-closed: deny if input is empty or unparseable
if [ -z "$INPUT" ]; then
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

JQ_RC=0
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || JQ_RC=$?
if [ "$JQ_RC" -ne 0 ]; then
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

# Fallback to environment variable for backward compatibility
if [ -z "$FILE" ]; then
    FILE="${CLAUDE_FILE_PATH:-}"
fi

# Skip if no file path provided (allow by default)
if [ -z "$FILE" ]; then
    allow_response
fi

# Resolve the path so symlinks, ~, $HOME, and macOS /var → /private/var
# all canonicalize. resolve_path is purely string-transforming for
# non-existent targets, so newly-created files still flow through.
TARGET=$(resolve_path "$FILE")

# Lowercased basename with surrounding whitespace stripped. The strip
# defends against ".env " (trailing space) and similar whitespace-padded
# bypasses; case folding defends against ".ENV" / ".Env" variants.
BASENAME_RAW=$(basename -- "$TARGET")
BASENAME_TRIMMED="${BASENAME_RAW#"${BASENAME_RAW%%[![:space:]]*}"}"
BASENAME_TRIMMED="${BASENAME_TRIMMED%"${BASENAME_TRIMMED##*[![:space:]]}"}"
BASENAME_LOWER=$(printf '%s' "$BASENAME_TRIMMED" | tr '[:upper:]' '[:lower:]')

# Pattern set covers env files, credential containers, SSH private keys,
# and AWS credential files. NUL-byte truncation is handled implicitly
# because bash variables cannot carry NUL bytes — the path is truncated
# at the first NUL before reaching this check.
case "$BASENAME_LOWER" in
    .env|.env.*|.envrc)
        deny_response "Access to sensitive file blocked: $FILE (env file)"
        ;;
    *.pem|*.key|*.p12|*.pfx)
        deny_response "Access to sensitive file blocked: $FILE (credential file)"
        ;;
    id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|id_ecdsa|id_ecdsa.*|id_dsa|id_dsa.*)
        deny_response "Access to sensitive file blocked: $FILE (SSH private key)"
        ;;
    credentials|config)
        case "$TARGET" in
            */.aws/*)
                deny_response "Access to sensitive file blocked: $FILE (AWS credentials)"
                ;;
        esac
        ;;
esac

# Check sensitive directories (case-insensitive)
if echo "$FILE" | grep -qiE '(secrets|credentials|passwords)[/\\]'; then
    deny_response "Access to sensitive directory blocked: $FILE (protected path)"
fi

allow_response
