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

# prompt_language_profile
# Sets:
#   AGENT_LANGUAGE      english | korean
#   AGENT_DISPLAY_LANG  English | Korean
#   CONTENT_LANGUAGE    english | exclusive_bilingual
#
# Non-interactive override: set AGENT_LANGUAGE and/or CONTENT_LANGUAGE before
# calling to skip or partially skip the prompt. Each var is honored
# INDEPENDENTLY (issue #762): presetting only one still suppresses the prompt
# only when both are set; the still-unset half falls back to the Hybrid default
# (AGENT_LANGUAGE=korean / CONTENT_LANGUAGE=english) rather than being clobbered.
prompt_language_profile() {
    # Capture which vars the caller preset BEFORE the prompt may overwrite them.
    local _agent_preset="" _content_preset=""
    [ -n "${AGENT_LANGUAGE:-}" ]   && _agent_preset="$AGENT_LANGUAGE"
    [ -n "${CONTENT_LANGUAGE:-}" ] && _content_preset="$CONTENT_LANGUAGE"

    # Run the interactive block only when BOTH are unset.
    if [ -z "$_agent_preset" ] && [ -z "$_content_preset" ]; then
        echo ""
        _prompts_info "Select Language Profile Preset:"
        echo "  1) English Unified (Dialogue & Documents both in English)"
        echo "  2) Korean Unified  (Dialogue & Documents both in Korean - exclusive)"
        echo "  3) Hybrid Mode     (Dialogue in Korean, Documents in English - default)"
        echo ""
        read -r -p "Selection (1-3) [default: 3]: " _profile_type
        _profile_type=${_profile_type:-3}

        case "$_profile_type" in
            1) AGENT_LANGUAGE="english"; CONTENT_LANGUAGE="english" ;;
            2) AGENT_LANGUAGE="korean";  CONTENT_LANGUAGE="exclusive_bilingual" ;;
            3) AGENT_LANGUAGE="korean";  CONTENT_LANGUAGE="english" ;;
            *)
                _prompts_warn "Unknown selection: $_profile_type. Falling back to Hybrid Mode."
                AGENT_LANGUAGE="korean"; CONTENT_LANGUAGE="english"
                ;;
        esac
    fi

    # Re-apply presets over whatever the prompt set, then fill the still-unset
    # half from the Hybrid default. Each var is honored independently.
    [ -n "$_agent_preset" ]   && AGENT_LANGUAGE="$_agent_preset"
    [ -n "$_content_preset" ] && CONTENT_LANGUAGE="$_content_preset"
    AGENT_LANGUAGE="${AGENT_LANGUAGE:-korean}"
    CONTENT_LANGUAGE="${CONTENT_LANGUAGE:-english}"

    # Derive Display from the final AGENT_LANGUAGE via the single existing case.
    case "$AGENT_LANGUAGE" in
        english) AGENT_DISPLAY_LANG="English" ;;
        korean)  AGENT_DISPLAY_LANG="Korean"  ;;
        *)       AGENT_DISPLAY_LANG="Korean"  ;;
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

# 함수: .tmpl 파일을 읽어 {{CONTENT_LANGUAGE_POLICY}}를 phrase로 치환한 뒤 대상에 기록
# 사용법: render_policy_tmpl <src.tmpl> <dest.md>
# get_policy_phrase에 의존하며 ambient CONTENT_LANGUAGE/AGENT_DISPLAY_LANG/
# AGENT_LANGUAGE를 읽는다(미설정 시 안전 기본값). install.sh와 bootstrap.sh
# 양쪽이 동일하게 호출하도록 단일 출처(이 lib)에 둔다 (issue #760).
render_policy_tmpl() {
    local src="$1"
    local dest="$2"
    local phrase
    phrase="$(get_policy_phrase)"
    # sed 구분자를 |로 사용해 경로/phrase 충돌 회피
    sed -e "s|{{CONTENT_LANGUAGE_POLICY}}|${phrase}|g" \
        -e "s|{{AGENT_LANGUAGE_POLICY}}|${AGENT_DISPLAY_LANG:-Korean}|g" \
        -e "s|{{AGENT_LANGUAGE}}|${AGENT_LANGUAGE:-korean}|g" "$src" > "$dest"
}

# 함수: 지정 디렉토리 내의 .md.tmpl 파일을 모두 찾아 .md로 렌더링 (원본 .tmpl 삭제)
# 사용법: render_policy_tmpls_in_dir <dir>
render_policy_tmpls_in_dir() {
    local dir="$1"
    local tmpl md
    while IFS= read -r tmpl; do
        md="${tmpl%.tmpl}"
        render_policy_tmpl "$tmpl" "$md"
        rm -f "$tmpl"
    done < <(find "$dir" -type f -name '*.md.tmpl' 2>/dev/null)
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
