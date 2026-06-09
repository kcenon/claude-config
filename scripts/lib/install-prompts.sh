#!/bin/bash

# scripts/lib/install-prompts.sh
# Shared installer language-policy machinery: prompts, value mappings,
# and policy-to-phrase rendering for the four CLAUDE_CONTENT_LANGUAGE
# values. Sourced by bootstrap.sh, scripts/install.sh, and
# tests/scripts/test-language-policy-drift.sh.
#
# Single source of truth: prompt strings, default values, value mappings,
# and the policy phrase table all live here. The PowerShell counterpart
# at scripts/lib/InstallPrompts.psm1 mirrors this file; drift between
# the two is guarded by tests/scripts/test-installer-prompt-drift.sh.
#
# Mapping rationale:
#   Agent Conversation Language fixes the language of Claude's dialogue.
#     English -> english
#     Korean  -> korean
#   Content Language fixes the language of artifacts (commits, PRs,
#   issues, comments, generated documents).
#     English -> english             (ASCII only, no Hangul)
#     Korean  -> exclusive_bilingual (per-artifact strict, no inline mix)
#   Legacy values korean_plus_english and any are not surfaced in the
#   simplified UI; advanced users may set them directly in settings.json.

if [ -n "${INSTALL_PROMPTS_SH_LOADED:-}" ]; then
    return 0
fi
INSTALL_PROMPTS_SH_LOADED=1

: "${BLUE:=$'\033[0;34m'}"
: "${YELLOW:=$'\033[1;33m'}"
: "${NC:=$'\033[0m'}"

# Portable function-detection: `type -t name` returns 'function' in both
# bash and zsh when name is a defined shell function. `declare -F` is
# bash-specific (zsh treats `-F` as filter for floating-point variables).
_prompts_is_function() {
    [ "$(type -t "$1" 2>/dev/null)" = "function" ]
}

_prompts_info() {
    if _prompts_is_function info; then
        info "$1"
    else
        printf "%bℹ️  %s%b\n" "$BLUE" "$1" "$NC"
    fi
}

_prompts_warn() {
    if _prompts_is_function warning; then
        warning "$1"
    else
        printf "%b⚠️  %s%b\n" "$YELLOW" "$1" "$NC"
    fi
}

# prompt_agent_language
# Sets:
#   AGENT_LANGUAGE      english | korean
#   AGENT_DISPLAY_LANG  English | Korean
prompt_agent_language() {
    echo ""
    _prompts_info "Select Agent Conversation Language:"
    echo "  1) English"
    echo "  2) Korean"
    echo ""
    read -r -p "Selection (1-2) [default: 2]: " _agent_lang_type
    _agent_lang_type=${_agent_lang_type:-2}

    case "$_agent_lang_type" in
        1)
            AGENT_LANGUAGE="english"
            AGENT_DISPLAY_LANG="English"
            ;;
        2)
            AGENT_LANGUAGE="korean"
            AGENT_DISPLAY_LANG="Korean"
            ;;
        *)
            _prompts_warn "Unknown selection: $_agent_lang_type. Falling back to korean."
            AGENT_LANGUAGE="korean"
            AGENT_DISPLAY_LANG="Korean"
            ;;
    esac
}

# prompt_content_language
# Sets:
#   CONTENT_LANGUAGE  english | exclusive_bilingual
prompt_content_language() {
    echo ""
    _prompts_info "Select Content Language (artifact validation scope):"
    _prompts_info "  Locks the language of generated documents, commits, PRs, issues, and comments."
    echo "  1) English (ASCII only - no Hangul allowed in artifacts)"
    echo "  2) Korean  (per-artifact strict - Hangul or English document, no inline mixing)"
    echo ""
    read -r -p "Selection (1-2) [default: 1]: " _content_lang_type
    _content_lang_type=${_content_lang_type:-1}

    case "$_content_lang_type" in
        1) CONTENT_LANGUAGE="english" ;;
        2) CONTENT_LANGUAGE="exclusive_bilingual" ;;
        *)
            _prompts_warn "Unknown selection: $_content_lang_type. Falling back to english."
            CONTENT_LANGUAGE="english"
            ;;
    esac
}

# get_policy_phrase [policy]
# Maps a CLAUDE_CONTENT_LANGUAGE value to the short phrase substituted
# into rule documents at install time (issue #411).
# Reads CONTENT_LANGUAGE from the environment when no argument is given.
# All four policies are accepted - the validator still supports them all,
# even though the simplified UI only surfaces english and exclusive_bilingual.
get_policy_phrase() {
    local policy="${1:-${CONTENT_LANGUAGE:-english}}"
    case "$policy" in
        english)             echo "English" ;;
        korean_plus_english) echo "English or Korean" ;;
        exclusive_bilingual) echo "English or Korean (document-exclusive)" ;;
        any)                 echo "any language" ;;
        *)                   echo "English" ;;
    esac
}

# all_policy_values
# Emits the four canonical CLAUDE_CONTENT_LANGUAGE values, one per line.
# Used by the drift test to iterate without hard-coding the list.
all_policy_values() {
    cat <<'EOF'
english
korean_plus_english
exclusive_bilingual
any
EOF
}

# read_settings_content_language <settings_json_path>
# Echoes the current CLAUDE_CONTENT_LANGUAGE value stored in settings.json,
# or empty string when absent / unparseable. Uses jq when available, else
# a portable grep+sed fallback.
read_settings_content_language() {
    local file="${1:-}"
    [ -f "$file" ] || { echo ""; return 0; }
    if command -v jq >/dev/null 2>&1; then
        jq -r '.env.CLAUDE_CONTENT_LANGUAGE // empty' "$file" 2>/dev/null
    else
        grep -oE '"CLAUDE_CONTENT_LANGUAGE"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" 2>/dev/null \
            | sed -E 's/.*"CLAUDE_CONTENT_LANGUAGE"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
            | head -1
    fi
}

# warn_legacy_settings_value <settings_json_path>
# Prints a warning when the existing settings.json holds a legacy
# CLAUDE_CONTENT_LANGUAGE value that the simplified UI no longer surfaces.
# Returns 0 when a warning was emitted, 1 otherwise.
# The installer continues with the operator's new selection regardless;
# this is informational only.
warn_legacy_settings_value() {
    local file="${1:-}"
    local current
    current="$(read_settings_content_language "$file")"
    detect_legacy_content_language "$current" || return 1

    _prompts_warn "Legacy CLAUDE_CONTENT_LANGUAGE detected: '$current'"
    _prompts_warn "  This value is still accepted by the validator but is no"
    _prompts_warn "  longer surfaced in the installer UI. Your new selection"
    _prompts_warn "  ('${CONTENT_LANGUAGE:-english}') will replace it. To keep"
    _prompts_warn "  '$current', cancel now and edit ~/.claude/settings.json"
    _prompts_warn "  directly without rerunning the installer."
    return 0
}

# detect_legacy_content_language [value]
# Returns 0 (true) if the given value is a legacy policy not surfaced in
# the simplified UI. Used by installers to warn on existing settings.json
# values that the operator may not realize are legacy.
detect_legacy_content_language() {
    case "${1:-}" in
        korean_plus_english|any) return 0 ;;
        *)                       return 1 ;;
    esac
}
