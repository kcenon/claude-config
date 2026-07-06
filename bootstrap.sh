#!/bin/bash

# Claude Configuration Bootstrap Script
# ======================================
# 원라인 설치 스크립트 - GitHub에서 직접 실행 가능
#
# 사용법:
#   curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
#
# 또는 (Private repo의 경우):
#   curl -sSL -H "Authorization: token YOUR_GITHUB_TOKEN" \
#     https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# GitHub 저장소 설정
GITHUB_USER="${GITHUB_USER:-kcenon}"
GITHUB_REPO="${GITHUB_REPO:-claude-config}"

# Pin install source to a release tag for SLSA-aligned supply-chain hardening.
# Floating refs (e.g. `main`) ship whatever HEAD is at install time, leaving no
# integrity baseline if `main` is briefly compromised. Override with GITHUB_REF.
if [ -n "${GITHUB_BRANCH:-}" ]; then
    echo "warning: GITHUB_BRANCH is deprecated, use GITHUB_REF" >&2
    GITHUB_REF="${GITHUB_REF:-$GITHUB_BRANCH}"
fi
GITHUB_REF="${GITHUB_REF:-v1.11.0}"

# Anthropic Claude Code installer pin (M1.2b — supply-chain hardening, see #565).
# The Anthropic-hosted install script is pinned by sha256 to prevent MITM
# substitution. Rotation policy: docs/SUPPLY_CHAIN.md. The weekly drift check
# workflow `.github/workflows/check-anthropic-installer.yml` fails when the
# upstream sha256 deviates from this value.
ANTHROPIC_INSTALLER_URL="${ANTHROPIC_INSTALLER_URL:-https://claude.ai/install.sh}"
ANTHROPIC_INSTALLER_SHA256="${ANTHROPIC_INSTALLER_SHA256:-b315b46925a9bfb9422f2503dd5aa649f680832f4c076b22d87c39d578c3d830}"  # pinned 2026-05-03

# 설치 디렉토리
INSTALL_DIR="${INSTALL_DIR:-$HOME/claude_config_backup}"

# ── Argument parsing + non-interactive prompt helper (issue #778) ─────────────
# Mirrors the scripts/install.sh FORCE_MODE / --type contract so the advertised
# `curl ... | bash` one-liner keeps working: env overrides and --yes enable
# fully unattended installs, and a /dev/tty fallback restores real prompts when
# stdin is the piped script body rather than a keyboard.
FORCE_MODE="${FORCE_MODE:-0}"
_PENDING_TYPE=""
_arg_prev=""
for _arg in "$@"; do
    if [ "$_arg_prev" = "--type" ]; then
        _PENDING_TYPE="$_arg"; _arg_prev=""; continue
    fi
    case "$_arg" in
        --yes|-y) FORCE_MODE=1 ;;
        --type)   ;;  # value consumed on the next iteration via _arg_prev
        -h|--help)
            sed -n '3,12p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "bootstrap.sh: unknown argument '$_arg'" >&2
            echo "Run with --help for usage." >&2
            exit 2 ;;
    esac
    _arg_prev="$_arg"
done
[ -n "$_PENDING_TYPE" ] && INSTALL_TYPE="${INSTALL_TYPE:-$_PENDING_TYPE}"
unset _arg _arg_prev _PENDING_TYPE

# bootstrap_read <varname> <prompt> <default>
# Resolve a prompt value, in priority order:
#   1. a pre-set non-empty env var of the same name (install.sh vocabulary:
#      INSTALL_TYPE / PROJECT_DIR / INSTALL_NPM / OVERWRITE / ...),
#   2. under FORCE_MODE (--yes/-y): the default, with no prompt,
#   3. an interactive prompt, read from /dev/tty when stdin is not a terminal
#      (the `curl | bash` case where stdin is the script body),
#   4. the default when no terminal is available at all (CI / non-tty).
# The `|| true` keeps an EOF read from aborting under `set -euo pipefail`.
bootstrap_read() {
    local __var="$1" __prompt="$2" __default="$3" __reply=""
    if [ -n "${!__var:-}" ]; then return 0; fi
    if [ "${FORCE_MODE:-0}" = "1" ]; then
        printf -v "$__var" '%s' "$__default"; return 0
    fi
    if [ -t 0 ]; then
        read -r -p "$__prompt" __reply || true
    elif [ -r /dev/tty ]; then
        read -r -p "$__prompt" __reply < /dev/tty || true
    fi
    printf -v "$__var" '%s' "${__reply:-$__default}"
}

# Test-only prompt-resolution mode for CI smoke tests. It runs after argument
# parsing and bootstrap_read are loaded, but before dependency checks, cloning,
# or filesystem installation, so tests can exercise the piped non-tty entry
# point hermetically.
if [ "${CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE:-}" = "prompt-resolution" ]; then
    bootstrap_read INSTALL_TYPE "선택 (1-4) [기본값: 1]: " "1"
    printf 'FORCE_MODE=%s\n' "${FORCE_MODE:-0}"
    printf 'INSTALL_TYPE=%s\n' "${INSTALL_TYPE:-}"
    if [ -t 0 ]; then
        printf 'STDIN_TTY=1\n'
    else
        printf 'STDIN_TTY=0\n'
    fi
    exit 0
fi
# ──────────────────────────────────────────────────────────────────────────────
CLAUDE_DIR="$HOME/.claude"

echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║       Claude Configuration Bootstrap Installer               ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 함수 정의
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# Path-guarded rm helper (M1.3, see #566).
# This file is consumed via `curl | bash`, so the canonical helper at
# scripts/lib/safe-rm.sh is unavailable when clone_repository() removes
# a stale $INSTALL_DIR. The function is intentionally inlined here and
# kept byte-equivalent in semantics with scripts/lib/safe-rm.sh.
# Resolves the canonical path via `realpath -e`, then asserts it lies
# under an allow-listed prefix before deleting. See safe-rm.sh for the
# full threat model and allow-list rationale.
safe_rm_rf() {
    local raw="${1:-}"
    if [ -z "$raw" ]; then
        echo "safe_rm_rf: target required" >&2
        return 1
    fi
    # Idempotent: missing target is not an error.
    if [ ! -e "$raw" ] && [ ! -L "$raw" ]; then
        return 0
    fi
    local target
    target=$(realpath -e "$raw") || {
        echo "safe_rm_rf: cannot resolve $raw" >&2
        return 1
    }
    case "$target" in
        "$HOME"/.claude/*) ;;
        "$HOME"/.claude-backup/*) ;;
        "$HOME"/claude_config_backup/*) ;;
        /tmp/claude-*) ;;
        /tmp/claude-config-*) ;;
        *)
            echo "safe_rm_rf: refused — $target is outside allow-listed prefix" >&2
            return 1
            ;;
    esac
    rm -rf -- "$target"
}

# 의존성 확인
check_dependencies() {
    info "의존성 확인 중..."

    # Required tools enforced by claude-config hooks (see PREREQUISITES.md).
    # `gh` and `perl` are checked in addition to git/curl because several
    # PreToolUse guards (merge-gate-guard, attribution-guard, markdown-anchor-
    # validator) and the `lib/timeout-wrapper.sh` fallback rely on them.
    local missing=()
    for cmd in jq gh git perl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing+=("curl-or-wget")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        error "필수 도구가 설치되어 있지 않습니다: ${missing[*]}. 설치 안내는 PREREQUISITES.md를 참고하세요."
    fi

    success "의존성 확인 완료"
}

# Claude Code CLI 설치 확인 및 자동 설치
# version-check.sh, batch-issue-work.sh 등이 `claude --version` / `claude` 명령을
# 호출하므로 미설치 시 silent failure가 발생한다. 본 함수는 부트스트랩 시점에
# 사용자 동의 하에 Anthropic 공식 native installer로 Claude Code CLI를 설치한다.
# 참고: https://code.claude.com/docs/en/setup
ensure_claude_cli() {
    info "Claude Code CLI 확인 중..."

    if command -v claude >/dev/null 2>&1; then
        local cc_version
        cc_version="$(claude --version 2>/dev/null | head -n1)"
        success "Claude Code CLI 이미 설치됨: ${cc_version:-version unknown}"
        return 0
    fi

    warning "Claude Code CLI가 설치되어 있지 않습니다."
    echo "  Claude Code CLI는 hooks(version-check), batch scripts(issue-work, pr-work) 등이"
    echo "  의존하는 핵심 도구입니다. 미설치 상태에서는 일부 기능이 동작하지 않습니다."
    echo ""

    bootstrap_read INSTALL_CLAUDE "Claude Code CLI를 지금 설치하시겠습니까? (y/n) [기본값: y]: " "y"

    if [ "$INSTALL_CLAUDE" != "y" ]; then
        warning "Claude Code CLI 설치 건너뜀. 추후 수동 설치 가이드:"
        echo "    https://code.claude.com/docs/en/setup"
        echo "  또는 본 스크립트를 다시 실행해 sha256 검증된 자동 설치를 진행하세요."
        return 0
    fi

    # Native installer는 Anthropic 공식 권장 방식이며 백그라운드 자동 업데이트를 지원한다.
    # 설치 경로: ~/.local/bin/claude → ~/.local/share/claude/versions/<ver>
    #
    # Supply-chain hardening (M1.2b, see #565; lib extraction #620):
    # Delegates to hooks/lib/installer-fetch.sh which encapsulates the
    # download → verify-sha256 → run contract. Source it from the clone so
    # bootstrap.sh, scripts/install.sh and bootstrap.ps1 share one
    # implementation; the lib is fetched as part of the tagged repo, so the
    # GITHUB_REF pin is the integrity root for every subsequent verification.
    local install_status=1
    # Guard the sourced lib (mirrors scripts/install.sh and bootstrap.ps1):
    # a missing lib must not abort the whole run under `set -euo pipefail`.
    if [ ! -f "$INSTALL_DIR/hooks/lib/installer-fetch.sh" ]; then
        warning "installer-fetch.sh missing — skipping CLI install (clone may be incomplete)"
        return 0
    fi
    # shellcheck disable=SC1091
    source "$INSTALL_DIR/hooks/lib/installer-fetch.sh"
    if installer_fetch_verify_run \
        "$ANTHROPIC_INSTALLER_URL" \
        "$ANTHROPIC_INSTALLER_SHA256" \
        "claude-installer"; then
        install_status=0
    fi

    if [ $install_status -eq 0 ]; then
        # 새로 만들어진 ~/.local/bin이 현재 셸 PATH에 없을 수 있으므로 일시 prepend.
        if ! command -v claude >/dev/null 2>&1 && [ -x "$HOME/.local/bin/claude" ]; then
            export PATH="$HOME/.local/bin:$PATH"
        fi
        if command -v claude >/dev/null 2>&1; then
            local cc_version
            cc_version="$(claude --version 2>/dev/null | head -n1)"
            success "Claude Code CLI 설치 완료: ${cc_version:-version unknown}"
            echo "  설치 위치: $(command -v claude)"
        else
            warning "Native installer는 종료되었으나 'claude'를 PATH에서 찾을 수 없습니다."
            echo "  새 셸을 열거나 ~/.local/bin을 PATH에 추가하세요:"
            echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    else
        warning "Claude Code CLI 자동 설치 실패."
        echo "  Anthropic 공식 설치 가이드를 참고하세요: https://code.claude.com/docs/en/setup"
        echo "  또는 본 스크립트를 다시 실행해 sha256 검증된 자동 설치를 재시도하세요."
    fi
}

# 저장소 클론
clone_repository() {
    info "저장소 클론 중..."

    if [ -d "$INSTALL_DIR" ]; then
        warning "기존 설치 디렉토리가 존재합니다: $INSTALL_DIR"
        bootstrap_read OVERWRITE "덮어쓰시겠습니까? (y/n) [기본값: n]: " "n"

        if [ "$OVERWRITE" = "y" ]; then
            safe_rm_rf "$INSTALL_DIR"
        else
            info "기존 디렉토리를 사용합니다. git pull 실행..."
            cd "$INSTALL_DIR"
            git pull origin "$GITHUB_REF"
            return
        fi
    fi

    # GitHub에서 클론 (pinned to GITHUB_REF, --depth 1 for bandwidth efficiency)
    git clone --branch "$GITHUB_REF" --depth 1 "https://github.com/$GITHUB_USER/$GITHUB_REPO.git" "$INSTALL_DIR"
    success "저장소 클론 완료: $INSTALL_DIR (ref: $GITHUB_REF)"
}

# copy_bootstrap_files <source_dir> <dest_dir> <glob> <executable:0|1> [manifest_key_prefix]
copy_bootstrap_files() {
    local src_dir="$1" dest_dir="$2" pattern="$3" executable="$4" key_prefix="${5:-}"
    local src dest

    mkdir -p "$dest_dir" || return 1

    if [ -n "$key_prefix" ] && type manifest_copy_files >/dev/null 2>&1; then
        manifest_copy_files "$src_dir" "$dest_dir" "$key_prefix" "$pattern" "$executable"
        return 0
    fi

    for src in "$src_dir"/$pattern; do
        [ -f "$src" ] || continue
        dest="$dest_dir/$(basename "$src")"
        cp "$src" "$dest" || return 1
        if [ "$executable" = "1" ]; then
            chmod +x "$dest" || return 1
        fi
    done

    return 0
}

deploy_bootstrap_hooks() {
    local hooks_src="$INSTALL_DIR/global/hooks"
    local hooks_dst="$CLAUDE_DIR/hooks"
    local hooks_lib_src="$hooks_src/lib"
    local shared_lib_src="$INSTALL_DIR/hooks/lib"
    local lib

    if [ ! -d "$hooks_src" ]; then
        echo "hook source directory missing: $hooks_src" >&2
        return 1
    fi

    copy_bootstrap_files "$hooks_src" "$hooks_dst" "*.sh" 1 "hooks" || return 1

    # global/hooks/lib/*.sh 배포 (issue #586). 위 *.sh glob은 비재귀적이라
    # tokenize-shell.sh 등 공유 라이브러리는 별도 복사 없이는 누락된다.
    # dangerous-command-guard 등 4개 Bash 가드가 런타임에 이를 source한다.
    if [ -d "$hooks_lib_src" ]; then
        copy_bootstrap_files "$hooks_lib_src" "$hooks_dst/lib" "*.sh" 1 "hooks/lib" || return 1
    fi

    # 공유 검증 라이브러리 설치 (commit-message-guard.sh, pr-language-guard.sh,
    # traceability-guard.sh가 사용). scripts/install.sh와 같은 런타임 계약.
    if [ -d "$shared_lib_src" ]; then
        for lib in validate-commit-message.sh validate-language.sh validate-traceability.sh; do
            if [ -f "$shared_lib_src/$lib" ]; then
                copy_bootstrap_files "$shared_lib_src" "$hooks_dst/lib" "$lib" 1 "hooks/lib" || return 1
            fi
        done
    fi

    for lib in \
        tokenize-shell.sh \
        path-utils.sh \
        timeout-wrapper.sh \
        rotate.sh \
        validate-commit-message.sh \
        validate-language.sh \
        validate-traceability.sh; do
        if [ ! -f "$hooks_dst/lib/$lib" ]; then
            echo "required hook runtime library missing after deploy: hooks/lib/$lib" >&2
            return 1
        fi
    done

    return 0
}

deploy_bootstrap_scripts() {
    local scripts_src="$INSTALL_DIR/global/scripts"
    local scripts_dst="$CLAUDE_DIR/scripts"

    [ -d "$scripts_src" ] || return 0
    copy_bootstrap_files "$scripts_src" "$scripts_dst" "*.sh" 1 "scripts" || return 1

    return 0
}

install_bootstrap_settings_and_hooks() {
    local settings_src="$INSTALL_DIR/global/settings.json"
    local settings_dst="$CLAUDE_DIR/settings.json"
    local settings_tmp="$CLAUDE_DIR/.settings.json.tmp.$$"
    local agent_language="${AGENT_LANGUAGE:-korean}"
    local content_language="${CONTENT_LANGUAGE:-english}"
    local settings_updated=0

    [ -f "$settings_src" ] || return 0

    # Stage settings first, then publish only after hook deployment succeeds.
    # This keeps ~/.claude/settings.json from pointing at missing runtime hooks.
    rm -f "$settings_tmp"
    cp "$settings_src" "$settings_tmp" || error "settings.json 스테이징 실패"

    if update_claude_settings_json "$settings_tmp" "$agent_language" "$content_language"; then
        settings_updated=1
    fi

    if ! deploy_bootstrap_hooks; then
        rm -f "$settings_tmp"
        error "Hook 스크립트 배포 실패. settings.json을 변경하지 않았습니다."
    fi

    if ! deploy_bootstrap_scripts; then
        rm -f "$settings_tmp"
        error "Utility 스크립트 배포 실패. settings.json을 변경하지 않았습니다."
    fi

    mv -f "$settings_tmp" "$settings_dst" || {
        rm -f "$settings_tmp"
        error "settings.json 게시 실패"
    }

    if [ "$settings_updated" = "1" ]; then
        success "settings.json (에이전트: $agent_language, 컨텐츠: $content_language) 설치 완료"
    else
        success "settings.json 설치 완료 (기본값)"
    fi
    success "Hook 스크립트 (hooks/ + lib/) 설치 완료!"
}

# 글로벌 설정 설치
install_global() {
    info "글로벌 설정 설치 중..."

    # ~/.claude 디렉토리 생성
    mkdir -p "$CLAUDE_DIR"

    # 설치 매니페스트 헬퍼 로드 (SHA-256 해시 기반 로컬 변경 보존)
    # shellcheck disable=SC1091
    source "$INSTALL_DIR/scripts/install-manifest.sh"
    manifest_reset_managed_keys
    # shellcheck disable=SC1091
    source "$INSTALL_DIR/scripts/lib/install-prompts.sh"

    # 파일 복사 (매니페스트 가드: 로컬 편집은 기본적으로 유지)
    for gf in CLAUDE.md commit-settings.md git-identity.md token-management.md; do
        src="$INSTALL_DIR/global/$gf"
        dest="$CLAUDE_DIR/$gf"
        [ -f "$src" ] || continue
        if manifest_copy_file "$src" "$dest" "$gf"; then
            success "$gf 설치됨"
        else
            info "$gf 로컬 변경 유지"
        fi
    done

    # Auto-seed git identity from `git config --global` (issue #777). Shared
    # with scripts/install.sh via seed_git_identity() in install-prompts.sh, so
    # the later personalize_git_identity step becomes confirm-only whenever the
    # user already has a global git identity configured.
    if seed_git_identity "$CLAUDE_DIR/git-identity.md"; then
        success "git-identity.md: git config로 자동 채우기 완료 (${SEED_GIT_IDENTITY_NAME} <${SEED_GIT_IDENTITY_EMAIL}>)"
    fi

    # Reinstall: keep the previously chosen language policy (issue #780).
    seed_language_from_settings "$HOME/.claude/settings.json"

    # Language policy selection (Unified Language Profile)
    prompt_language_profile

    # conversation-language.md 템플릿 처리
    if [ -f "$INSTALL_DIR/global/conversation-language.md.tmpl" ]; then
        if guarded_template_copy "$INSTALL_DIR/global/conversation-language.md.tmpl" "$CLAUDE_DIR/conversation-language.md" "conversation-language.md" "$AGENT_DISPLAY_LANG"; then
            manifest_track_key "conversation-language.md"
            success "conversation-language.md 설치됨 (언어: $AGENT_DISPLAY_LANG)"
        else
            manifest_track_key "conversation-language.md"
            info "conversation-language.md 로컬 변경 유지"
        fi
    else
        # Static-file fallback. The default repo ships only the .tmpl, so this
        # branch is unreachable in normal use. It exists to support fork users
        # who replace the .tmpl with a hand-edited static .md — preserving
        # their file via guarded_copy instead of silently dropping it.
        if [ -f "$INSTALL_DIR/global/conversation-language.md" ]; then
            if guarded_copy "$INSTALL_DIR/global/conversation-language.md" "$CLAUDE_DIR/conversation-language.md" "conversation-language.md"; then
                manifest_track_key "conversation-language.md"
                success "conversation-language.md 설치됨"
            else
                manifest_track_key "conversation-language.md"
                info "conversation-language.md 로컬 변경 유지"
            fi
        fi
    fi

    # Legacy settings.json migration warning (informational only).
    warn_legacy_settings_value "$HOME/.claude/settings.json" || true

    # settings.json + hooks 디렉토리 설치 (settings.json이 참조하는 런타임 가드)
    # settings.json은 ~/.claude/hooks/*.sh 가드 다수를 참조하므로, 설정 복사와
    # 훅 배포를 한 트랜잭션으로 처리해 "설정은 있는데 훅이 없는" 조용한 보안
    # 공백을 막는다. Hook 배포 실패 시 settings.json은 게시하지 않는다.
    install_bootstrap_settings_and_hooks

    # 글로벌 skills 및 commands 설치
    # `_internal/` 하위 격리 + `disable-model-invocation: true`가 적용된 스킬군은
    # Claude Code 슬래시 카탈로그에 노출되지 않으며, 글로벌 CLAUDE.md의
    # "Skill Aliases" 표에 따라 leading keyword 호출로만 실행된다.
    if [ -d "$INSTALL_DIR/global/skills" ]; then
        mkdir -p "$CLAUDE_DIR/skills"
        manifest_copy_tree "$INSTALL_DIR/global/skills" "$CLAUDE_DIR/skills" "skills"
        skill_count=$(find "$CLAUDE_DIR/skills" -name "SKILL.md" | wc -l | tr -d ' ')
        success "글로벌 skills 설치 완료 (${skill_count}개)"
    fi
    if [ -d "$INSTALL_DIR/global/commands" ]; then
        mkdir -p "$CLAUDE_DIR/commands"
        manifest_copy_tree "$INSTALL_DIR/global/commands" "$CLAUDE_DIR/commands" "commands"
        success "글로벌 commands 설치 완료"
    fi

    manifest_seed_retired_managed "$CLAUDE_DIR" \
        "commands/branch-cleanup.md" "3e7fc38c324cfc9cea639e95394d7819e7768364d12023ec0b36b91f9230b09d" \
        "commands/doc-review.md" "be659114c43ef29423c74d7b33e0f594b80c134b38fb7c5b61e6935cae88c26f" \
        "commands/implement-all-levels.md" "b675f8e689e8aca71eb67e8666acc98018ad70b746d16655476b5939380737be" \
        "commands/issue-create.md" "c654ab412f320b9d97553f92a510cf5de13a5d0a7ed5e14212ca62534887ae71" \
        "commands/issue-work.md" "048a26140b03862c5b10630853115ee656056f45cedfd0a0b6ec814bf7225684" \
        "commands/pr-work.md" "2ecf1a78271c553e2310b57b2a1deb026a07ae01b84c1f856638293ab41f1199" \
        "commands/release.md" "93fd6d2f7800deada2868b97b65ef486f42482b5e2f1224c35f732ebfeb1c013"
    manifest_prune_tracked "$CLAUDE_DIR"

    # tmux 설정 설치
    if [ -f "$INSTALL_DIR/global/tmux.conf" ]; then
        cp "$INSTALL_DIR/global/tmux.conf" "$HOME/.tmux.conf"
        mkdir -p "$HOME/.local/tmux_logs"
        success "tmux 설정 설치 완료"
    fi

    # ccstatusline 설정 설치 (~/.config/ccstatusline/ — ccstatusline 기본 설정 경로)
    if [ -d "$INSTALL_DIR/global/ccstatusline" ]; then
        mkdir -p "$HOME/.config/ccstatusline"
        cp "$INSTALL_DIR/global/ccstatusline/settings.json" "$HOME/.config/ccstatusline/"
        success "ccstatusline 설정 설치 완료"
    fi

    # npm 패키지 설치 (statusline 의존성)
    if command -v npm &> /dev/null; then
        bootstrap_read INSTALL_NPM "Statusline npm 패키지를 설치하시겠습니까? (y/n) [기본값: y]: " "y"
        if [ "$INSTALL_NPM" = "y" ]; then
            if npm install -g ccstatusline claude-limitline 2>/dev/null; then
                success "npm 패키지 설치 완료 (ccstatusline, claude-limitline)"
            else
                warning "npm 패키지 설치 실패. 수동 설치: npm install -g ccstatusline claude-limitline"
            fi
        fi
    else
        warning "npm 미설치. Statusline 의존성: npm install -g ccstatusline claude-limitline"
    fi

    success "글로벌 설정 설치 완료"
}

# Git identity 개인화 안내
personalize_git_identity() {
    echo ""
    if grep -qE "YOUR NAME|YOUR EMAIL" "$CLAUDE_DIR/git-identity.md" 2>/dev/null; then
        warning "Git Identity에 기본 placeholder가 남아 있습니다. 개인 정보로 수정하세요."
    else
        info "Git Identity가 준비되었습니다. 필요하면 값을 확인하거나 수정하세요."
    fi
    echo ""
    echo "  현재 설정:"
    grep -E "^(name|email):" "$CLAUDE_DIR/git-identity.md" 2>/dev/null || true
    echo ""
    echo "  수정 방법:"
    echo "    vi ~/.claude/git-identity.md"
    echo ""

    bootstrap_read EDIT_NOW "지금 수정하시겠습니까? (y/n) [기본값: n]: " "n"

    if [ "$EDIT_NOW" = "y" ]; then
        ${EDITOR:-vi} "$CLAUDE_DIR/git-identity.md"
        success "Git identity 수정 완료"
    fi
}

# 설치 타입 선택
select_install_type() {
    echo ""
    info "설치 타입을 선택하세요:"
    echo "  1) 글로벌 설정만 설치 (~/.claude/)"
    echo "  2) 프로젝트 설정만 설치 (현재 디렉토리)"
    echo "  3) 둘 다 설치 (권장)"
    echo "  4) 저장소만 클론 (수동 설치)"
    echo ""
    bootstrap_read INSTALL_TYPE "선택 (1-4) [기본값: 1]: " "1"
}

# 프로젝트 설정 설치
install_project() {
    echo ""
    bootstrap_read PROJECT_DIR "프로젝트 디렉토리 경로 [기본값: $(pwd)]: " "$(pwd)"

    if [ ! -d "$PROJECT_DIR" ]; then
        error "디렉토리가 존재하지 않습니다: $PROJECT_DIR"
    fi

    info "프로젝트 설정 설치 중: $PROJECT_DIR"

    # 정책 템플릿 렌더링 준비 (issue #760)
    # install-prompts.sh는 render_policy_tmpls_in_dir와 언어 프로파일 프롬프트를
    # 제공한다. 프로젝트-단독 설치(타입 2)에서는 install_global이 호출되지 않으므로
    # 이 시점에 lib 소싱과 언어 프로파일 해소가 모두 필요하다. 둘 다 멱등:
    #   - lib는 INSTALL_PROMPTS_SH_LOADED 가드로 재소싱이 no-op
    #   - 언어 변수가 이미 설정된 경우(타입 3에서 install_global이 프롬프트함)
    #     재프롬프트하지 않도록 미설정일 때만 prompt_language_profile 호출
    # shellcheck disable=SC1091
    source "$INSTALL_DIR/scripts/lib/install-prompts.sh"
    # Reinstall: keep the previously chosen language policy (issue #780).
    seed_language_from_settings "$HOME/.claude/settings.json"
    if [ -z "${AGENT_LANGUAGE:-}" ] || [ -z "${CONTENT_LANGUAGE:-}" ]; then
        prompt_language_profile
    fi

    if ! type manifest_copy_file >/dev/null 2>&1; then
        # shellcheck disable=SC1091
        source "$INSTALL_DIR/scripts/install-manifest.sh"
    fi

    local previous_manifest_path="${MANIFEST_PATH:-}"

    # 파일 복사
    mkdir -p "$PROJECT_DIR/.claude"
    MANIFEST_PATH="$PROJECT_DIR/.claude/.install-manifest.json"
    manifest_reset_managed_keys

    if manifest_copy_file "$INSTALL_DIR/project/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md" "CLAUDE.md"; then
        success "프로젝트 CLAUDE.md 설치 완료"
    else
        info "프로젝트 CLAUDE.md 로컬 변경 유지"
    fi

    # .claude 디렉토리 설치
    if [ -d "$INSTALL_DIR/project/.claude/rules" ]; then
        local rules_tmp
        rules_tmp=$(mktemp -d)
        cp -R "$INSTALL_DIR/project/.claude/rules"/. "$rules_tmp/"
        # issue #760: 복사된 rules/ 안의 .md.tmpl을 정책 phrase로 치환
        # (install.sh와 동일한 single-source 렌더 함수)
        render_policy_tmpls_in_dir "$rules_tmp"
        manifest_copy_tree "$rules_tmp" "$PROJECT_DIR/.claude/rules" ".claude/rules"
        rm -rf "$rules_tmp"
    fi
    [ -d "$INSTALL_DIR/project/.claude/reference" ] && manifest_copy_tree "$INSTALL_DIR/project/.claude/reference" "$PROJECT_DIR/.claude/reference" ".claude/reference"
    [ -d "$INSTALL_DIR/project/.claude/skills" ] && manifest_copy_tree "$INSTALL_DIR/project/.claude/skills" "$PROJECT_DIR/.claude/skills" ".claude/skills"
    [ -d "$INSTALL_DIR/project/.claude/commands" ] && manifest_copy_tree "$INSTALL_DIR/project/.claude/commands" "$PROJECT_DIR/.claude/commands" ".claude/commands"
    [ -d "$INSTALL_DIR/project/.claude/agents" ] && manifest_copy_tree "$INSTALL_DIR/project/.claude/agents" "$PROJECT_DIR/.claude/agents" ".claude/agents"
    [ -f "$INSTALL_DIR/project/.claude/settings.json" ] && manifest_copy_file "$INSTALL_DIR/project/.claude/settings.json" "$PROJECT_DIR/.claude/settings.json" ".claude/settings.json" || true
    [ -f "$INSTALL_DIR/project/.claudeignore" ] && manifest_copy_file "$INSTALL_DIR/project/.claudeignore" "$PROJECT_DIR/.claudeignore" ".claudeignore" || true

    manifest_seed_retired_managed "$PROJECT_DIR" \
        ".claude/commands/_policy.md" "7144bf54352362eb3d523d05a1712732aec8e82fc95ea9db0cbc79269e2bf9b1" \
        ".claude/commands/code-quality.md" "8c1e6ca0470582936fb96491d4aff7e23706da45b96ba38c51d43ba255f8f544" \
        ".claude/commands/git-status.md" "4602f6ea8ffb18b05d5698c85d060b3d6f01913a4258e778bd6b898611ca9d33" \
        ".claude/commands/pr-review.md" "3dbd7d788b1e19b1d04654e03eaf8531c933e6b7462120ffdc03d5d7f9658711"
    manifest_prune_tracked "$PROJECT_DIR"
    MANIFEST_PATH="$previous_manifest_path"

    success "프로젝트 설정 설치 완료"
}

# 메인 실행
main() {
    check_dependencies
    # clone_repository must run before ensure_claude_cli — the latter sources
    # hooks/lib/installer-fetch.sh from the just-cloned tag (#620). Trust
    # root: GITHUB_REF tag → cloned hooks/lib/* → pinned sha256 verification.
    clone_repository
    ensure_claude_cli
    select_install_type

    case $INSTALL_TYPE in
        1)
            install_global
            personalize_git_identity
            ;;
        2)
            install_project
            ;;
        3)
            install_global
            install_project
            personalize_git_identity
            ;;
        4)
            info "저장소가 클론되었습니다: $INSTALL_DIR"
            info "수동으로 ./scripts/install.sh를 실행하세요."
            ;;
        *)
            error "잘못된 선택입니다."
            ;;
    esac

    echo ""
    echo "======================================================"
    success "설치 완료!"
    echo "======================================================"
    echo ""

    info "설치된 위치:"
    echo "  📂 백업 저장소: $INSTALL_DIR"
    [ "$INSTALL_TYPE" = "1" ] || [ "$INSTALL_TYPE" = "3" ] && echo "  📂 글로벌 설정: $CLAUDE_DIR"
    [ "$INSTALL_TYPE" = "2" ] || [ "$INSTALL_TYPE" = "3" ] && echo "  📂 프로젝트 설정: $PROJECT_DIR"

    echo ""
    info "다음 단계:"
    echo "  1. Claude Code 재시작"
    echo "  2. 설정 확인: cat ~/.claude/CLAUDE.md"
    echo "  3. Statusline 패키지: npm install -g ccstatusline claude-limitline"
    echo "  4. 동기화: cd $INSTALL_DIR && ./scripts/sync.sh"
    echo ""

    success "Happy Coding with Claude! 🎉"
}

if [ "${CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE:-}" = "atomic-deploy" ]; then
    mkdir -p "$CLAUDE_DIR"
    # shellcheck disable=SC1091
    source "$INSTALL_DIR/scripts/install-manifest.sh"
    install_bootstrap_settings_and_hooks
    exit 0
fi

# 스크립트 실행
main "$@"
