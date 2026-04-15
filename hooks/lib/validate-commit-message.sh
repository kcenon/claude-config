#!/bin/bash
# validate-commit-message.sh
# Shared commit message validation library
# Single source of truth for commit message rules.
#
# Sourced by:
#   - hooks/commit-msg          (git hook — terminal-side gate)
#   - global/hooks/commit-message-guard.sh (PreToolUse — Claude-side feedback loop)
#
# Usage:
#   . /path/to/validate-commit-message.sh
#   if ! validate_commit_message "feat: add feature"; then
#       echo "invalid" >&2
#   fi

# Allowed commit types (Conventional Commits)
readonly CMV_TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|security"

# AI attribution regex — single source of truth shared with attribution-guard
# (PR/issue body checks). Same pattern enforced across commit messages, PR
# titles/bodies, and issue titles/bodies so an attribution leak cannot slip
# through one channel while being blocked in another.
readonly CMV_ATTRIBUTION_REGEX='(claude|anthropic|ai-assisted|co-authored-by:[[:space:]]*claude|generated[[:space:]]+with)'

# validate_no_attribution <text>
# Returns 0 if text contains no AI/Claude attribution, 1 if attribution is found.
# On failure, prints reason to stderr.
#
# Used by both validate_commit_message (this file) and attribution-guard.sh
# (the PR/issue body PreToolUse hook) so the regex stays in one place.
validate_no_attribution() {
    local text="$1"

    if [ -z "$text" ]; then
        return 0
    fi

    if printf '%s' "$text" | grep -iqE "$CMV_ATTRIBUTION_REGEX"; then
        echo "Text contains AI/Claude attribution (claude, anthropic, ai-assisted, generated with, co-authored-by: claude). Remove attribution before submitting." >&2
        return 1
    fi

    return 0
}

# validate_commit_message <message>
# Returns 0 on valid, 1 on invalid.
# On failure, prints reason to stderr.
validate_commit_message() {
    local msg="$1"

    # Rule 1: Conventional Commits format — type(scope)?: description
    if ! printf '%s' "$msg" | grep -qE "^($CMV_TYPES)(\([a-z0-9._-]+\))?: .+"; then
        echo "Commit message must follow Conventional Commits: 'type(scope): description' or 'type: description'. Allowed types: ${CMV_TYPES//|/, }." >&2
        return 1
    fi

    # Extract description (everything after the first ': ')
    local desc
    desc=$(printf '%s' "$msg" | sed -E 's/^[^:]*:[[:space:]]*//')

    # Rule 2: Description starts with a lowercase ASCII letter
    local first_char
    first_char=$(printf '%s' "$desc" | head -c1)
    case "$first_char" in
        a|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z) ;;
        *)
            echo "Commit message description must start with a lowercase letter." >&2
            return 1
            ;;
    esac

    # Rule 3: No trailing period
    case "$desc" in
        *.)
            echo "Commit message description must not end with a period." >&2
            return 1
            ;;
    esac

    # Rule 4: No AI/Claude attribution (delegates to shared helper for SSOT)
    if ! validate_no_attribution "$msg" 2>/dev/null; then
        echo "Commit message must not contain AI/Claude attribution (claude, anthropic, ai-assisted, generated with, co-authored-by: claude)." >&2
        return 1
    fi

    # Rule 5: No emojis
    # perl exits 1 when a match is found; 0 otherwise.
    if ! printf '%s' "$msg" | perl -CSD -ne 'exit 1 if /[\x{1F300}-\x{1F9FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}\x{1F1E0}-\x{1F1FF}]/' 2>/dev/null; then
        echo "Commit message must not contain emojis." >&2
        return 1
    fi

    return 0
}
