#!/bin/bash
# validate-language.sh
# Shared text language validation library.
# Single source of truth for the "English-only" rule applied to GitHub
# Issue and Pull Request titles and bodies created via the gh CLI.
#
# Sourced by:
#   - global/hooks/pr-language-guard.sh (PreToolUse — Claude-side feedback loop)
#
# The rule mirrors commit-settings.md: "All GitHub Issues and Pull Requests
# must be written in English." The terminal-side enforcement layer for git
# commits lives in validate-commit-message.sh; this library is the analogous
# gate for gh pr/issue commands intercepted at the Bash tool boundary.
#
# Usage:
#   . /path/to/validate-language.sh
#   if ! validate_english_only "$body"; then
#       echo "invalid" >&2
#   fi

# validate_english_only <text>
# Returns 0 on valid (English-only or empty), 1 on invalid.
# On failure, prints reason to stderr.
#
# Definition of "English-only":
#   - Empty strings are treated as valid (nothing to validate).
#   - All bytes must fall within ASCII printable range (0x20-0x7E) or be
#     ASCII whitespace (space, tab, newline, carriage return, form feed,
#     vertical tab). LC_ALL=C forces grep to interpret character classes
#     as 7-bit ASCII regardless of the user's locale.
#   - Any byte outside that set — accented Latin, CJK, emoji, symbols —
#     fails validation.
validate_english_only() {
    local text="$1"

    if [ -z "$text" ]; then
        return 0
    fi

    if printf '%s' "$text" | LC_ALL=C grep -q '[^[:print:][:space:]]'; then
        local sample
        sample=$(printf '%s' "$text" | LC_ALL=C grep -oE '[^[:print:][:space:]]+' | head -n1)
        echo "Text contains non-ASCII characters (first run: '$sample'). GitHub Issues and Pull Requests must be written in English only — see commit-settings.md." >&2
        return 1
    fi

    return 0
}
