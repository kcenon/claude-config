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

# validate_korean_with_tech_terms <text>
# Returns 0 on valid, 1 on invalid. On failure, prints reason to stderr.
#
# Korean-mode branch of the exclusive_bilingual policy (issue #447). The
# rule: after stripping the four allowed ASCII containers below, the
# residual text must contain zero [A-Za-z] characters. Bare English
# tokens inline with Korean prose are rejected with a remediation hint.
#
# Allowed ASCII containers (strip in this order — see issue #447):
#   1. Fenced code blocks — triple backticks.
#   2. Inline code — single backticks.
#   3. URLs — https?://... runs of non-whitespace.
#   4. Parenthesized ASCII immediately preceded by a Hangul run —
#      the 한국어(English) translation form.
#
# Strip ordering matters: fenced first so nested backticks inside fences
# are not mis-stripped; then inline code so parenthesized content inside
# backticks is preserved inside the code; then URLs; finally the
# translation form.
validate_korean_with_tech_terms() {
    local text="$1"
    [ -z "$text" ] && return 0

    local stripped
    stripped=$(printf '%s' "$text" | perl -CSDA -0777 -pe '
        s/```[\s\S]*?```//g;
        s/`[^`\n]*`//g;
        s{https?://\S+}{}g;
        s/[\x{AC00}-\x{D7A3}]+\s*\([^)\n]*\)//g;
    ' 2>/dev/null)

    if printf '%s' "$stripped" | LC_ALL=C grep -qE '[A-Za-z]'; then
        local sample
        sample=$(printf '%s' "$stripped" | LC_ALL=C grep -oE '[A-Za-z]+' | head -n1)
        echo "Korean-mode policy violation: bare English token '$sample' detected. Wrap in backticks or use the '한국어(English)' form. CLAUDE_CONTENT_LANGUAGE=exclusive_bilingual requires document-level language exclusivity." >&2
        return 1
    fi
    return 0
}

# validate_content_language <text>
# Dispatcher — selects the validator based on CLAUDE_CONTENT_LANGUAGE:
#   - english (default, unset, or empty) → validate_english_only
#   - korean_plus_english → validate_english_or_korean
#   - exclusive_bilingual → english_only when text has no Hangul syllables,
#                           otherwise validate_korean_with_tech_terms
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
        exclusive_bilingual)
            # Hangul syllable detection routes the document to the
            # appropriate mode. No Hangul = English mode = strict ASCII
            # whitelist. Any Hangul = Korean mode = strip-then-scan.
            if printf '%s' "$text" | perl -CSDA -ne 'exit 1 if /[\x{AC00}-\x{D7A3}]/' 2>/dev/null; then
                validate_english_only "$text"
            else
                validate_korean_with_tech_terms "$text"
            fi
            ;;
        any)
            return 0
            ;;
        *)
            echo "CLAUDE_CONTENT_LANGUAGE has unknown value '$policy'. Valid values: english, korean_plus_english, exclusive_bilingual, any." >&2
            validate_english_only "$text"
            ;;
    esac
}
