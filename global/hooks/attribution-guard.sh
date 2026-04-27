#!/bin/bash
# attribution-guard.sh
# Blocks gh pr/issue/release commands whose user-facing text fields contain
# AI/Claude attribution markers. Scope (Issue #480 extended): pr
# create|edit|comment|review, issue create|edit|comment, release create|edit.
# Inspected fields: --title/-t, --body/-b, --notes/-n.
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
# Mirrors the three-pattern design in hooks/lib/validate-commit-message.sh —
# trailer-style at line start, bot emoji adjacent to Claude/Anthropic, and
# "Generated|Created|Authored {with|by|using} {Claude|Anthropic}" prose.
# Keep all three patterns in sync with the library when updating.
if ! command -v validate_no_attribution >/dev/null 2>&1; then
    validate_no_attribution() {
        local text="$1"
        if [ -z "$text" ]; then
            return 0
        fi
        if printf '%s' "$text" | grep -qE '^[[:space:]]*(Co-[Aa]uthored-[Bb]y|Co-[Aa]uthor|[Gg]enerated[- ]?[Bb]y|[Cc]reated[- ]?[Bb]y|[Aa]uthored[- ]?[Bb]y|[Ss]igned-[Oo]ff-[Bb]y|[Aa]ssisted-[Bb]y)[[:space:]]*:[[:space:]]*.*([Cc]laude|[Aa]nthropic|AI[- ]?[Aa]ssisted)'; then
            echo "Text contains AI/Claude attribution trailer. Remove the trailer before submitting." >&2
            return 1
        fi
        if printf '%s' "$text" | grep -qE '🤖[[:space:]]*[^[:space:]]*[[:space:]]*([Cc]laude|[Aa]nthropic)'; then
            echo "Text contains AI bot emoji adjacent to Claude/Anthropic attribution. Remove the marker before submitting." >&2
            return 1
        fi
        if printf '%s' "$text" | grep -qE '([Gg]enerated|[Cc]reated|[Aa]uthored|[Ww]ritten)[[:space:]]+(with|by|using)[[:space:]]+(Claude|Anthropic|AI[- ]?[Aa]ssistant)'; then
            echo "Text contains AI/Claude attribution prose. Remove the attribution before submitting." >&2
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

# --- Scope: gh pr|issue|release commands that emit human-authored text ---
# Issue #480 extended scope to cover gh pr review (review body) and
# gh release create|edit (release notes). Out-of-scope commands fall through
# to allow without inspection — server-side trailers and CI verification
# handle anything not gated here.
if ! echo "$CMD" | grep -qE 'gh[[:space:]]+(pr[[:space:]]+(create|edit|comment|review)|issue[[:space:]]+(create|edit|comment)|release[[:space:]]+(create|edit))'; then
    allow_response
fi

# --- Skip command-substitution / heredoc / file-based bodies ---
# These channels feed the body from another process or file, where the
# attribution check belongs to the upstream (commit-msg hook for files,
# command substitution opaque to us). Letting them through avoids false
# rejections while preserving the static-string gate.
if echo "$CMD" | grep -qE -- '(--body|-b|--title|-t|--notes|-n)[[:space:]=]+"\$\('; then
    allow_response
fi
if echo "$CMD" | grep -qE -- '(--body-file|--notes-file|-F)[[:space:]=]+'; then
    allow_response
fi

# --- Extract a quoted argument value ---
# Tries double quotes first, then single quotes. Returns the first match
# on stdout, empty string if not found.
#
# Uses bash native [[ =~ ]] for all branches so multi-line body strings
# (gh pr create --body "line1\n\nline2") match correctly. The earlier sed-
# based path silently dropped multi-line values because sed's `.*` does not
# cross newlines.
extract_quoted_value() {
    local cmd="$1"
    local long_flag="$2"
    local short_flag="$3"

    # Long flag, double-quoted: --title "value" or --title="value"
    local long_dq="${long_flag}[[:space:]=]+\"([^\"]*)\""
    if [[ "$cmd" =~ $long_dq ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return
    fi

    # Long flag, single-quoted
    local long_sq="${long_flag}[[:space:]=]+'([^']*)'"
    if [[ "$cmd" =~ $long_sq ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return
    fi

    # Short flag (must be preceded by whitespace)
    if [ -n "$short_flag" ]; then
        local short_dq="[[:space:]]${short_flag}[[:space:]]+\"([^\"]*)\""
        if [[ "$cmd" =~ $short_dq ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return
        fi
        local short_sq="[[:space:]]${short_flag}[[:space:]]+'([^']*)'"
        if [[ "$cmd" =~ $short_sq ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return
        fi
    fi
}

TITLE=$(extract_quoted_value "$CMD" "--title" "-t")
BODY=$(extract_quoted_value "$CMD" "--body"  "-b")
NOTES=$(extract_quoted_value "$CMD" "--notes" "-n")

# --- Validate ---
if [ -n "$TITLE" ]; then
    REASON=$(validate_no_attribution "$TITLE" 2>&1) || \
        deny_response "--title rejected: $REASON"
fi

if [ -n "$BODY" ]; then
    REASON=$(validate_no_attribution "$BODY" 2>&1) || \
        deny_response "--body rejected: $REASON"
fi

if [ -n "$NOTES" ]; then
    REASON=$(validate_no_attribution "$NOTES" 2>&1) || \
        deny_response "release --notes rejected: $REASON"
fi

allow_response
