#!/bin/bash
# attribution-guard.sh
# Blocks gh pr/issue create|edit|comment commands whose --title or --body
# contains AI/Claude attribution markers.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Enforces the "No AI/Claude attribution in commits, issues, or PRs" rule
# from commit-settings.md at the Bash tool boundary. Mirrors the
# commit-message-guard / pr-language-guard / merge-gate-guard enforcement
# model: a deterministic hook gate that catches drift in long-running batch
# workflows where Co-Authored-By or "Generated with Claude" markers
# occasionally leak into PR/issue text via the gh CLI.
#
# Sources shared validation rules from hooks/lib/validate-commit-message.sh,
# specifically the validate_no_attribution() helper. Both this hook and
# the commit-message validator use the same CMV_ATTRIBUTION_REGEX so a
# leak cannot slip through one channel while being blocked in another.
#
# NOTE on parsing limits: --body using $(...) command substitution, heredocs,
# and --body-file references cannot be parsed at the shell layer; the hook
# returns "allow" and defers to other safeguards in those cases.

set -uo pipefail

# --- Response helpers ---
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

# Inline fallback so the hook still works when the shared library is missing.
# Keep regex in sync with hooks/lib/validate-commit-message.sh.
if ! command -v validate_no_attribution >/dev/null 2>&1; then
    validate_no_attribution() {
        local text="$1"
        if [ -z "$text" ]; then
            return 0
        fi
        if printf '%s' "$text" | grep -iqE '(claude|anthropic|ai-assisted|co-authored-by:[[:space:]]*claude|generated[[:space:]]+with)'; then
            echo "Text contains AI/Claude attribution (claude, anthropic, ai-assisted, generated with, co-authored-by: claude). Remove attribution before submitting." >&2
            return 1
        fi
        return 0
    }
fi

# --- Read input from stdin ---
INPUT=$(cat)

# Empty input: fail open
if [ -z "$INPUT" ]; then
    allow_response
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || CMD=""
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# --- Scope: only validate gh pr|issue create|edit|comment commands ---
if ! echo "$CMD" | grep -qE 'gh[[:space:]]+(pr|issue)[[:space:]]+(create|edit|comment)'; then
    allow_response
fi

# --- Skip command-substitution / heredoc / file-based bodies ---
if echo "$CMD" | grep -qE -- '(--body|-b|--title|-t)[[:space:]=]+"\$\('; then
    allow_response
fi
if echo "$CMD" | grep -qE -- '--body-file[[:space:]=]+'; then
    allow_response
fi

# --- Extract a quoted argument value ---
# Tries double quotes first, then single quotes. Returns the first match
# on stdout, empty string if not found.
extract_quoted_value() {
    local cmd="$1"
    local long_flag="$2"
    local short_flag="$3"
    local val=""

    # Long flag, double-quoted: --title "value" or --title="value"
    val=$(printf '%s' "$cmd" | sed -nE "s/.*${long_flag}[[:space:]=]+\"([^\"]*)\".*/\1/p" | head -n1)
    if [ -n "$val" ]; then
        printf '%s' "$val"
        return
    fi

    # Long flag, single-quoted
    if [[ "$cmd" =~ ${long_flag}[[:space:]=]+\'([^\']*)\' ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return
    fi

    # Short flag (must be preceded by whitespace)
    if [ -n "$short_flag" ]; then
        val=$(printf '%s' "$cmd" | sed -nE "s/.*[[:space:]]${short_flag}[[:space:]]+\"([^\"]*)\".*/\1/p" | head -n1)
        if [ -n "$val" ]; then
            printf '%s' "$val"
            return
        fi
        if [[ "$cmd" =~ [[:space:]]${short_flag}[[:space:]]+\'([^\']*)\' ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return
        fi
    fi
}

TITLE=$(extract_quoted_value "$CMD" "--title" "-t")
BODY=$(extract_quoted_value "$CMD" "--body"  "-b")

# --- Validate ---
if [ -n "$TITLE" ]; then
    REASON=$(validate_no_attribution "$TITLE" 2>&1) || \
        deny_response "PR/issue --title rejected: $REASON"
fi

if [ -n "$BODY" ]; then
    REASON=$(validate_no_attribution "$BODY" 2>&1) || \
        deny_response "PR/issue --body rejected: $REASON"
fi

allow_response
