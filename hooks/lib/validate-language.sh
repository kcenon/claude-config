#!/bin/bash
# validate-language.sh
# Shared text language validation library.
# Single source of truth for the content-language rule applied to GitHub
# Issue and Pull Request titles and bodies created via the gh CLI.
#
# Sourced by:
#   - global/hooks/pr-language-guard.sh (PreToolUse — Claude-side feedback loop)
#
# The default rule mirrors commit-settings.md: "All GitHub Issues and Pull
# Requests must be written in English." The terminal-side enforcement layer
# for git commits lives in validate-commit-message.sh; this library is the
# analogous gate for gh pr/issue commands intercepted at the Bash tool
# boundary.
#
# The CLAUDE_CONTENT_LANGUAGE environment variable selects the policy
# (see validate_content_language below). See issue #410 for the design.
#
# Usage:
#   . /path/to/validate-language.sh
#   if ! validate_content_language "$body"; then
#       echo "invalid" >&2
#   fi
#
# The legacy validate_english_only entry point is preserved for callers
# that want the default policy explicitly, independent of the env var.

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

# validate_english_or_korean <text>
# Returns 0 on valid, 1 on invalid. On failure, prints reason to stderr.
#
# Accepts:
#   - ASCII printable (U+0020-U+007E) and ASCII whitespace (U+0009-U+000D)
#   - Hangul Syllables (U+AC00-U+D7A3)
#   - Hangul Jamo (U+1100-U+11FF)
#   - Hangul Compatibility Jamo (U+3130-U+318F)
#
# Anything else — accented Latin, CJK outside Hangul, emoji, general
# symbols — fails. perl -CSDA forces UTF-8 input decoding regardless of
# locale. Exit 1 inside the perl one-liner signals a match was found.
validate_english_or_korean() {
    local text="$1"

    if [ -z "$text" ]; then
        return 0
    fi

    if ! printf '%s' "$text" | perl -CSDA -ne '
        exit 1 if /[^\x{09}-\x{0D}\x{20}-\x{7E}\x{AC00}-\x{D7A3}\x{1100}-\x{11FF}\x{3130}-\x{318F}]/
    ' 2>/dev/null; then
        local sample
        sample=$(printf '%s' "$text" | perl -CSDA -ne '
            while (/([^\x{09}-\x{0D}\x{20}-\x{7E}\x{AC00}-\x{D7A3}\x{1100}-\x{11FF}\x{3130}-\x{318F}]+)/g) {
                print $1; exit;
            }
        ' 2>/dev/null)
        echo "Text contains characters outside the English+Korean policy (first run: '$sample'). CLAUDE_CONTENT_LANGUAGE=korean_plus_english allows ASCII and Hangul only." >&2
        return 1
    fi

    return 0
}

# validate_content_language <text>
# Dispatcher — selects the validator based on CLAUDE_CONTENT_LANGUAGE:
#   - english (default, unset, or empty) → validate_english_only
#   - korean_plus_english → validate_english_or_korean
#   - any → skip validation (always returns 0)
#
# NOTE: This dispatcher does NOT control AI/Claude attribution enforcement.
# attribution-guard.{sh,ps1} and validate_no_attribution remain active for
# every policy value — attribution blocking is a hard rule, not a language
# concern. See issue #410 for the scope boundary.
validate_content_language() {
    local text="$1"
    local policy="${CLAUDE_CONTENT_LANGUAGE:-english}"

    case "$policy" in
        ""|english)
            validate_english_only "$text"
            ;;
        korean_plus_english)
            validate_english_or_korean "$text"
            ;;
        any)
            return 0
            ;;
        *)
            echo "CLAUDE_CONTENT_LANGUAGE has unknown value '$policy'. Valid values: english, korean_plus_english, any." >&2
            validate_english_only "$text"
            ;;
    esac
}
