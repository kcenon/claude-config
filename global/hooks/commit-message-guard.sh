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

set -euo pipefail

# --- Response helpers (match dangerous-command-guard.sh pattern) ---
# Use jq -nc --arg reason ... so the JSON library handles all escaping
# (quotes, backslashes, newlines, tabs, carriage returns, etc.). This closes
# the historical injection class where a crafted reason string concatenated
# into the heredoc could flip the decision (issue #567 / sub-issue #578).
deny_response() {
    local reason="$1"
    jq -nc \
        --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    exit 0
}

allow_response() {
    jq -nc \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
    exit 0
}

# --- Source shared validation library (fail-closed) ---
# All install paths (development checkout, terminal install, plugin marketplace,
# plugin-lite) MUST bundle the canonical validator. If it cannot be sourced the
# hook refuses rather than silently falling back to a drifted inline copy
# (#568). The previous inline fallback drifted from the canonical and shipped
# strictly weaker enforcement for plugin marketplace users.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR=""

# Try 1: repo-relative path (development / CI testing)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"
if [ -f "$REPO_ROOT/hooks/lib/validate-commit-message.sh" ]; then
    VALIDATOR="$REPO_ROOT/hooks/lib/validate-commit-message.sh"
# Try 2: sibling lib/ directory (deployed to ~/.claude/hooks/ and plugin trees)
elif [ -f "$SCRIPT_DIR/lib/validate-commit-message.sh" ]; then
    VALIDATOR="$SCRIPT_DIR/lib/validate-commit-message.sh"
fi

if [ -z "$VALIDATOR" ]; then
    echo "commit-message-guard: canonical validator not found at \$REPO_ROOT/hooks/lib/validate-commit-message.sh nor \$SCRIPT_DIR/lib/validate-commit-message.sh. Reinstall claude-config so hooks/lib/ is bundled alongside global/hooks/." >&2
    exit 1
fi

# shellcheck source=../../hooks/lib/validate-commit-message.sh
. "$VALIDATOR"

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

# --- Deny --no-verify / -n (issue #782) ---
# `git commit --no-verify` (and its short form `-n`) skips the commit-msg git
# hook, the terminal-side half of the attribution/format defense. Deny both so
# the PreToolUse layer cannot be bypassed on the way to the git hook. Strip
# quoted substrings first so a flag inside the message (e.g. -m "fix -n bug")
# cannot false-trigger. Short-flag cluster: for git commit only `-n` carries an
# 'n', so any single-dash cluster containing 'n' is --no-verify.
_DEQUOTED=$(printf '%s' "$CMD" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")
if printf '%s' "$_DEQUOTED" | grep -qE '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
    deny_response "git commit --no-verify is blocked: it skips the commit-msg hook that enforces the commit-message policy (no attribution, Conventional Commits). Commit without --no-verify."
fi
if printf '%s' "$_DEQUOTED" | grep -qE '(^|[[:space:]])-[A-Za-z]*n[A-Za-z]*([[:space:]]|$)'; then
    deny_response "git commit -n (--no-verify) is blocked: it skips the commit-msg hook that enforces the commit-message policy. Commit without -n."
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
# Single-quoted forms (issue #782): -m '...', -am '...', --message='...'.
# Single quotes suppress shell expansion, so there is no command-substitution
# case to skip here — the content is literal and safe to validate.
if [ -z "$MSG" ]; then
    MSG=$(printf '%s' "$CMD" | sed -nE "s/.*[[:space:]]-m[[:space:]]+'([^']*)'.*/\1/p" | head -n1)
fi
if [ -z "$MSG" ]; then
    MSG=$(printf '%s' "$CMD" | sed -nE "s/.*[[:space:]]-am[[:space:]]+'([^']*)'.*/\1/p" | head -n1)
fi
if [ -z "$MSG" ]; then
    MSG=$(printf '%s' "$CMD" | sed -nE "s/.*--message[[:space:]=]+'([^']*)'.*/\1/p" | head -n1)
fi

# If no -m argument found, git will open $EDITOR — nothing to validate here.
if [ -z "$MSG" ]; then
    allow_response
fi

# --- Validate using shared library (canonical SSOT, see #568) ---
REASON=$(validate_commit_message "$MSG" 2>&1) || deny_response "$REASON"

# All rules passed
allow_response
