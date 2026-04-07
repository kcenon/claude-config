#!/bin/bash
# commit-message-guard.sh
# Deterministic git commit message validator
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Replaces the non-deterministic type:"prompt" validator (see #241).
# Same input always yields same output — safe as a validation gate.
#
# Sources shared validation rules from hooks/lib/validate-commit-message.sh
# (single source of truth shared with the git commit-msg hook — see #242).
#
# NOTE on parsing limits: -m arguments using $(...) command substitution or
# containing embedded double quotes are not reliably parseable at this layer.
# In such cases the hook returns "allow" and defers to the git commit-msg
# hook (see #242) as the terminal enforcement layer.

set -uo pipefail

# --- Response helpers (match dangerous-command-guard.sh pattern) ---
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

# --- Source shared validation library ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR=""

# Try 1: repo-relative path (development / CI testing)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"
if [ -f "$REPO_ROOT/hooks/lib/validate-commit-message.sh" ]; then
    VALIDATOR="$REPO_ROOT/hooks/lib/validate-commit-message.sh"
# Try 2: sibling lib/ directory (deployed to ~/.claude/hooks/)
elif [ -f "$SCRIPT_DIR/lib/validate-commit-message.sh" ]; then
    VALIDATOR="$SCRIPT_DIR/lib/validate-commit-message.sh"
fi

if [ -n "$VALIDATOR" ]; then
    # shellcheck source=../../hooks/lib/validate-commit-message.sh
    . "$VALIDATOR"
fi

# --- Read input from stdin ---
INPUT=$(cat)

# Empty input: fail open (other guards fail closed, but message guard has
# nothing to validate without a message, and the commit-msg git hook is the
# authoritative gate).
if [ -z "$INPUT" ]; then
    allow_response
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || CMD=""
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# --- Scope: only validate git commit commands ---
if ! echo "$CMD" | grep -qE 'git[[:space:]]+commit'; then
    allow_response
fi

# --- Skip command substitution cases ---
# Example: git commit -m "$(cat <<'EOF' ... EOF\n)"
# These cannot be parsed reliably with regex — defer to commit-msg hook (#242).
if echo "$CMD" | grep -qE -- '-a?m[[:space:]]+"\$\('; then
    allow_response
fi

# --- Extract -m / -am / --message value ---
MSG=""
MSG=$(printf '%s' "$CMD" | sed -nE 's/.*[[:space:]]-m[[:space:]]+"([^"]*)".*/\1/p' | head -n1)
if [ -z "$MSG" ]; then
    MSG=$(printf '%s' "$CMD" | sed -nE 's/.*[[:space:]]-am[[:space:]]+"([^"]*)".*/\1/p' | head -n1)
fi
if [ -z "$MSG" ]; then
    MSG=$(printf '%s' "$CMD" | sed -nE 's/.*--message[[:space:]=]+"([^"]*)".*/\1/p' | head -n1)
fi

# If no -m argument found, git will open $EDITOR — nothing to validate here.
if [ -z "$MSG" ]; then
    allow_response
fi

# --- Validate using shared library (if available) or inline fallback ---
if [ -n "$VALIDATOR" ]; then
    REASON=$(validate_commit_message "$MSG" 2>&1) || deny_response "$REASON"
else
    # Inline fallback when the shared library is not available.
    # Keep rules in sync with hooks/lib/validate-commit-message.sh.
    if ! printf '%s' "$MSG" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|security)(\([a-z0-9._-]+\))?: .+'; then
        deny_response "Commit message must follow Conventional Commits: 'type(scope): description' or 'type: description'. Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, security."
    fi

    DESC=$(printf '%s' "$MSG" | sed -E 's/^[^:]*:[[:space:]]*//')
    FIRST_CHAR=$(printf '%s' "$DESC" | head -c1)
    case "$FIRST_CHAR" in
        a|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z) ;;
        *) deny_response "Commit message description must start with a lowercase letter." ;;
    esac

    case "$DESC" in
        *.) deny_response "Commit message description must not end with a period." ;;
    esac

    if printf '%s' "$MSG" | grep -iqE '(claude|anthropic|ai-assisted|co-authored-by:[[:space:]]*claude|generated[[:space:]]+with)'; then
        deny_response "Commit message must not contain AI/Claude attribution (claude, anthropic, ai-assisted, generated with, co-authored-by: claude)."
    fi

    if ! printf '%s' "$MSG" | perl -CSD -ne 'exit 1 if /[\x{1F300}-\x{1F9FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}\x{1F1E0}-\x{1F1FF}]/' 2>/dev/null; then
        deny_response "Commit message must not contain emojis."
    fi
fi

# All rules passed
allow_response
