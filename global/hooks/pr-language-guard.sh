#!/bin/bash
# pr-language-guard.sh
# Blocks gh pr/issue create|edit|comment commands whose --title or --body
# contains non-ASCII characters.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Enforces the "All GitHub Issues and Pull Requests must be written in
# English" rule from commit-settings.md. Mirrors the commit-message-guard
# enforcement model that proved effective for commit messages: a hard hook
# gate at the Bash tool boundary catches drift in long-running batch
# workflows where the model occasionally lapses into non-English content.
#
# Sources shared validation rules from hooks/lib/validate-language.sh
# (single source of truth — see #291).
#
# NOTE on parsing limits: --body arguments using $(...) command substitution,
# heredocs, or --body-file references are not parseable at this layer.
# In such cases the hook returns "allow" and defers to other safeguards
# (server-side review, commit hooks for committed content).

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
if [ -f "$REPO_ROOT/hooks/lib/validate-language.sh" ]; then
    VALIDATOR="$REPO_ROOT/hooks/lib/validate-language.sh"
# Try 2: sibling lib/ directory (deployed to ~/.claude/hooks/)
elif [ -f "$SCRIPT_DIR/lib/validate-language.sh" ]; then
    VALIDATOR="$SCRIPT_DIR/lib/validate-language.sh"
fi

if [ -n "$VALIDATOR" ]; then
    # shellcheck source=../../hooks/lib/validate-language.sh
    . "$VALIDATOR"
fi

# Inline fallback so the hook still works when the shared library is missing.
# Keep rules in sync with hooks/lib/validate-language.sh. Default policy is
# "english" when CLAUDE_CONTENT_LANGUAGE is unset — byte-identical to the
# pre-dispatcher behavior.
if ! command -v validate_content_language >/dev/null 2>&1; then
    validate_content_language() {
        local text="$1"
        local policy="${CLAUDE_CONTENT_LANGUAGE:-english}"

        if [ -z "$text" ]; then
            return 0
        fi

        case "$policy" in
            any)
                return 0
                ;;
            korean_plus_english)
                if ! printf '%s' "$text" | perl -CSDA -ne '
                    exit 1 if /[^\x{09}-\x{0D}\x{20}-\x{7E}\x{AC00}-\x{D7A3}\x{1100}-\x{11FF}\x{3130}-\x{318F}]/
                ' 2>/dev/null; then
                    echo "Text contains characters outside the English+Korean policy. CLAUDE_CONTENT_LANGUAGE=korean_plus_english allows ASCII and Hangul only." >&2
                    return 1
                fi
                return 0
                ;;
            *)
                if printf '%s' "$text" | LC_ALL=C grep -q '[^[:print:][:space:]]'; then
                    local sample
                    sample=$(printf '%s' "$text" | LC_ALL=C grep -oE '[^[:print:][:space:]]+' | head -n1)
                    echo "Text contains non-ASCII characters (first run: '$sample'). GitHub Issues and Pull Requests must be written in English only — see commit-settings.md." >&2
                    return 1
                fi
                return 0
                ;;
        esac
    }
fi

# --- Read input from stdin ---
INPUT=$(cat)

# Empty input: fail open — nothing to validate.
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
# These cannot be parsed reliably at the shell layer.
if echo "$CMD" | grep -qE -- '(--body|-b|--title|-t)[[:space:]=]+"\$\('; then
    allow_response
fi
if echo "$CMD" | grep -qE -- '--body-file[[:space:]=]+'; then
    allow_response
fi

# --- Extract a quoted argument value ---
# Tries double quotes first, then single quotes. Returns the first match
# on stdout, empty string if not found. The longest-match-safe pattern
# [^"]* / [^']* prevents the regex from spanning subsequent arguments.
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

    # Long flag, single-quoted: --title 'value' or --title='value'
    if [[ "$cmd" =~ ${long_flag}[[:space:]=]+\'([^\']*)\' ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return
    fi

    # Short flag, double-quoted: -t "value" (require leading whitespace
    # to avoid matching inside other tokens)
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

# --- Validate (dispatches on CLAUDE_CONTENT_LANGUAGE, default english) ---
if [ -n "$TITLE" ]; then
    REASON=$(validate_content_language "$TITLE" 2>&1) || \
        deny_response "PR/issue --title rejected: $REASON"
fi

if [ -n "$BODY" ]; then
    REASON=$(validate_content_language "$BODY" 2>&1) || \
        deny_response "PR/issue --body rejected: $REASON"
fi

allow_response
