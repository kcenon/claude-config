#!/bin/bash

# Claude Configuration Auto-Installer
# ====================================
# 백업된 CLAUDE.md 설정을 새 시스템에 자동으로 설치하는 스크립트

set -e  # 에러 발생 시 스크립트 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 스크립트 디렉토리 경로
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BACKUP_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║       Claude Configuration Auto-Installer                    ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 함수: 정보 메시지
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# 함수: 성공 메시지
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# 함수: 경고 메시지
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 함수: 에러 메시지
error() {
    echo -e "${RED}❌ $1${NC}"
}

# 함수: 디렉토리 생성
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || error "디렉토리 생성 실패: $dir"
        success "디렉토리 생성: $dir"
    fi
}

# 함수: 의존성 확인
check_dependencies() {
    local missing_deps=0
    for cmd in cp mkdir chmod grep sed; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "필수 명령어 '$cmd'가 설치되어 있지 않습니다."
            missing_deps=1
        fi
    done
    if [ $missing_deps -ne 0 ]; then
        exit 1
    fi
}

# 함수: Claude Code CLI 설치 확인 및 자동 설치
# version-check.sh 등 hook 스크립트와 batch-issue-work.sh / batch-pr-work.sh가
# `claude --version` / `claude` 명령을 직접 호출한다. 미설치 상태에서 설정만
# 배포되면 silent failure가 발생하므로 설치 시점에 Anthropic 공식 native
# installer를 통한 동의 기반 자동 설치를 제공한다.
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
    echo "  설치된 hook(version-check) 및 batch 스크립트가 'claude' 명령을 호출하므로,"
    echo "  미설치 상태에서는 일부 기능이 정상 동작하지 않습니다."
    echo ""

    read -p "Claude Code CLI를 지금 설치하시겠습니까? (y/n) [기본값: y]: " INSTALL_CLAUDE
    INSTALL_CLAUDE=${INSTALL_CLAUDE:-y}

    if [ "$INSTALL_CLAUDE" != "y" ]; then
        warning "Claude Code CLI 설치 건너뜀. 추후 수동 설치:"
        echo "    curl -fsSL https://claude.ai/install.sh | bash"
        return 0
    fi

    # Native installer는 Anthropic 공식 권장 방식이며 백그라운드 자동 업데이트를 지원한다.
    # 설치 경로: ~/.local/bin/claude → ~/.local/share/claude/versions/<ver>
    local installer_url="https://claude.ai/install.sh"
    local install_status=1
    info "Native installer 실행 중: $installer_url"
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "$installer_url" | bash; then
            install_status=0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -qO- "$installer_url" | bash; then
            install_status=0
        fi
    else
        warning "curl/wget이 모두 없어 자동 설치를 진행할 수 없습니다."
        echo "  curl 설치 후 재시도하거나 수동으로 다음을 실행하세요:"
        echo "    curl -fsSL https://claude.ai/install.sh | bash"
        return 0
    fi

    if [ $install_status -eq 0 ]; then
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
        echo "  수동 설치:"
        echo "    curl -fsSL https://claude.ai/install.sh | bash"
        echo "  또는 Anthropic 공식 가이드: https://code.claude.com/docs/en/setup"
    fi
}

# 함수: CLAUDE.local.md 생성
create_local_claude() {
    local project_dir="$1"
    local local_file="$project_dir/CLAUDE.local.md"
    local template_file="$BACKUP_DIR/project/CLAUDE.local.md.template"

    # Create CLAUDE.local.md from template if not exists
    if [ ! -f "$local_file" ]; then
        if [ -f "$template_file" ]; then
            cp "$template_file" "$local_file"
            success "Created $local_file from template"
        fi
    else
        info "CLAUDE.local.md already exists, skipping..."
    fi

    # Ensure gitignore entry
    if [ -f "$project_dir/.gitignore" ]; then
        if ! grep -q "CLAUDE.local.md" "$project_dir/.gitignore"; then
            echo "" >> "$project_dir/.gitignore"
            echo "# Claude Code local settings (personal, do not commit)" >> "$project_dir/.gitignore"
            echo "CLAUDE.local.md" >> "$project_dir/.gitignore"
            success "Added CLAUDE.local.md to .gitignore"
        fi
    fi
}

# Note: get_policy_phrase is provided by scripts/lib/install-prompts.sh,
# which is sourced before any callers (the prompt section sources it
# explicitly; render_policy_tmpl below depends on it). Kept centralized
# in the lib so the bash, PowerShell, and drift-test definitions stay
# in lockstep.

# 함수: .tmpl 파일을 읽어 {{CONTENT_LANGUAGE_POLICY}}를 phrase로 치환한 뒤 대상에 기록
# 사용법: render_policy_tmpl <src.tmpl> <dest.md>
render_policy_tmpl() {
    local src="$1"
    local dest="$2"
    local phrase
    phrase="$(get_policy_phrase)"
    # sed 구분자를 |로 사용해 경로/phrase 충돌 회피
    sed "s|{{CONTENT_LANGUAGE_POLICY}}|${phrase}|g" "$src" > "$dest"
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

# 함수: Enterprise 경로 감지
get_enterprise_dir() {
    case "$(uname -s)" in
        Darwin)
            echo "/Library/Application Support/ClaudeCode"
            ;;
        Linux)
            echo "/etc/claude-code"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "C:/Program Files/ClaudeCode"
            ;;
        *)
            echo "/etc/claude-code"
            ;;
    esac
}

# 함수: Enterprise 설정 설치
install_enterprise() {
    local enterprise_dir
    enterprise_dir="$(get_enterprise_dir)"

    echo ""
    echo "======================================================"
    info "Enterprise 설정 설치 중..."
    echo "======================================================"
    echo ""

    # Check if template has been customized (match footer marker line starting with *)
    if grep -q "^\*This is a template\." "$BACKUP_DIR/enterprise/CLAUDE.md" 2>/dev/null; then
        echo ""
        warning "============================================================"
        warning "enterprise/CLAUDE.md has NOT been customized yet!"
        warning "============================================================"
        echo ""
        echo -e "${YELLOW}The managed policy path has the HIGHEST priority in Claude Code."
        echo -e "Deploying an uncustomized template will enforce requirements"
        echo -e "that have no supporting implementation:${NC}"
        echo ""
        echo "  - GPG signing for all commits (no guidance configured)"
        echo "  - Sign-off required (--signoff not mentioned elsewhere)"
        echo "  - 80% test coverage minimum (conflicts with testing.md)"
        echo "  - Security team approval (no process defined)"
        echo "  - Squash merge preferred (not in PR guidelines)"
        echo ""
        echo -e "${YELLOW}Recommendation: Customize enterprise/CLAUDE.md first, then re-run.${NC}"
        echo ""
        read -p "Deploy uncustomized template anyway? (y/n) [default: n]: " DEPLOY_TEMPLATE
        DEPLOY_TEMPLATE=${DEPLOY_TEMPLATE:-n}
        if [ "$DEPLOY_TEMPLATE" != "y" ]; then
            info "Enterprise installation skipped. Customize enterprise/CLAUDE.md first."
            return 0
        fi
        warning "Proceeding with uncustomized template deployment."
    fi

    info "Enterprise 경로: $enterprise_dir"
    warning "관리자 권한이 필요합니다."
    echo ""

    # sudo 필요 여부 확인
    if [ "$(uname -s)" = "Darwin" ] || [ "$(uname -s)" = "Linux" ]; then
        if [ ! -w "$(dirname "$enterprise_dir")" ]; then
            info "sudo를 사용하여 설치합니다."

            # 디렉토리 생성
            sudo mkdir -p "$enterprise_dir"
            sudo mkdir -p "$enterprise_dir/rules"

            # 파일 복사
            sudo cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$enterprise_dir/" || error "CLAUDE.md 복사 실패"
            success "CLAUDE.md 설치됨"

            # rules 디렉토리 복사
            if [ -d "$BACKUP_DIR/enterprise/rules" ] && [ -n "$(ls -A "$BACKUP_DIR/enterprise/rules" 2>/dev/null)" ]; then
                sudo cp -r "$BACKUP_DIR/enterprise/rules"/* "$enterprise_dir/rules/" || error "rules 복사 실패"
                success "rules 디렉토리 설치됨"
            fi

            # 권한 설정 (읽기 전용)
            sudo chmod 755 "$enterprise_dir"
            sudo chmod 644 "$enterprise_dir/CLAUDE.md"
            sudo chmod 755 "$enterprise_dir/rules"
            if [ -n "$(ls -A "$enterprise_dir/rules" 2>/dev/null)" ]; then
                sudo chmod 644 "$enterprise_dir/rules"/* || error "rules 권한 설정 실패"
            fi
        else
            # sudo 불필요
            mkdir -p "$enterprise_dir"
            mkdir -p "$enterprise_dir/rules"
            cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$enterprise_dir/" || error "CLAUDE.md 복사 실패"
            success "CLAUDE.md 설치됨"

            if [ -d "$BACKUP_DIR/enterprise/rules" ] && [ -n "$(ls -A "$BACKUP_DIR/enterprise/rules" 2>/dev/null)" ]; then
                cp -r "$BACKUP_DIR/enterprise/rules"/* "$enterprise_dir/rules/" || error "rules 복사 실패"
                success "rules 디렉토리 설치됨"
            fi
        fi
    else
        # Windows
        mkdir -p "$enterprise_dir"
        mkdir -p "$enterprise_dir/rules"
        cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$enterprise_dir/" || error "CLAUDE.md 복사 실패"
        success "CLAUDE.md 설치됨"

        if [ -d "$BACKUP_DIR/enterprise/rules" ] && [ -n "$(ls -A "$BACKUP_DIR/enterprise/rules" 2>/dev/null)" ]; then
            cp -r "$BACKUP_DIR/enterprise/rules"/* "$enterprise_dir/rules/" || error "rules 복사 실패"
            success "rules 디렉토리 설치됨"
        fi
    fi

    success "Enterprise 설정 설치 완료!"
    echo ""
    warning "중요: enterprise/CLAUDE.md를 조직 정책에 맞게 수정하세요!"
}

# ----- Memory Sync Scheduler (issue #527) -----
#
# Installs the platform-native scheduler that invokes memory-sync.sh hourly.
# macOS: launchd LaunchAgent at ~/Library/LaunchAgents/com.kcenon.claude-memory-sync.plist
# Linux: systemd user units at ~/.config/systemd/user/memory-sync.{service,timer}
#
# Skipped silently when CLAUDE_MEMORY_REPO_URL is unset. Installs are idempotent:
# re-running unloads/disables the prior unit cleanly, then re-loads/enables.
#
# Test/dry-run overrides (no destructive launchctl/systemctl side effects):
#   LAUNCHD_TARGET_DIR=/tmp/foo     redirect plist destination away from
#                                   ~/Library/LaunchAgents (also skips launchctl)
#   SYSTEMD_USER_DIR=/tmp/bar       redirect unit destination away from
#                                   ~/.config/systemd/user (also skips systemctl)
# These overrides also disable the launchctl bootstrap / systemctl enable steps
# so the install function can be exercised on CI runners and dev sandboxes
# without modifying real launchd / systemd state.

install_launchd_agent() {
    local src_plist="$BACKUP_DIR/scripts/launchd/com.kcenon.claude-memory-sync.plist"
    if [ ! -f "$src_plist" ]; then
        warning "launchd plist source not found: $src_plist"
        return 1
    fi

    local target_dir="${LAUNCHD_TARGET_DIR:-$HOME/Library/LaunchAgents}"
    local target_plist="$target_dir/com.kcenon.claude-memory-sync.plist"

    ensure_dir "$target_dir"
    cp "$src_plist" "$target_plist"
    chmod 644 "$target_plist"

    # Skip launchctl when redirected to a test directory.
    if [ -n "${LAUNCHD_TARGET_DIR:-}" ]; then
        info "[install] LAUNCHD_TARGET_DIR set; skipping launchctl bootstrap"
        success "launchd plist staged at $target_plist (test mode)"
        return 0
    fi

    # Idempotent activation: bootout (ignore failure if not loaded) then bootstrap.
    local domain="gui/$(id -u)"
    launchctl bootout "$domain" "$target_plist" 2>/dev/null || true
    if launchctl bootstrap "$domain" "$target_plist" 2>/dev/null; then
        success "launchd agent loaded ($domain com.kcenon.claude-memory-sync)"
    else
        warning "launchctl bootstrap failed; falling back to load/unload"
        launchctl unload "$target_plist" 2>/dev/null || true
        launchctl load "$target_plist" || warning "launchctl load failed"
    fi
}

install_systemd_timer() {
    local src_dir="$BACKUP_DIR/scripts/systemd"
    if [ ! -f "$src_dir/memory-sync.service" ] || [ ! -f "$src_dir/memory-sync.timer" ]; then
        warning "systemd unit sources not found in $src_dir"
        return 1
    fi

    local target_dir="${SYSTEMD_USER_DIR:-$HOME/.config/systemd/user}"
    ensure_dir "$target_dir"
    cp "$src_dir/memory-sync.service" "$target_dir/"
    cp "$src_dir/memory-sync.timer" "$target_dir/"
    chmod 644 "$target_dir/memory-sync.service" "$target_dir/memory-sync.timer"

    # Skip systemctl when redirected to a test directory.
    if [ -n "${SYSTEMD_USER_DIR:-}" ]; then
        info "[install] SYSTEMD_USER_DIR set; skipping systemctl enable"
        success "systemd units staged at $target_dir (test mode)"
        return 0
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || warning "systemctl daemon-reload failed"
        if systemctl --user enable --now memory-sync.timer 2>/dev/null; then
            success "systemd user timer enabled (memory-sync.timer)"
        else
            warning "systemctl --user enable failed; check 'loginctl enable-linger' and DBUS_SESSION_BUS_ADDRESS"
        fi
    else
        warning "systemctl not found; units copied but timer not enabled"
    fi
}

install_memory_sync() {
    if [ -z "${CLAUDE_MEMORY_REPO_URL:-}" ]; then
        info "[install] CLAUDE_MEMORY_REPO_URL not set; skipping memory sync setup"
        return 0
    fi

    if [ ! -d "$HOME/.claude/memory-shared/.git" ]; then
        info "[install] cloning memory repo from $CLAUDE_MEMORY_REPO_URL"
        if ! git clone "$CLAUDE_MEMORY_REPO_URL" "$HOME/.claude/memory-shared"; then
            warning "[install] memory repo clone failed; aborting scheduler install"
            return 1
        fi
        if [ -x "$HOME/.claude/memory-shared/scripts/install-hooks.sh" ]; then
            (cd "$HOME/.claude/memory-shared" && ./scripts/install-hooks.sh) || \
                warning "[install] memory repo install-hooks.sh failed"
        fi
    else
        info "[install] memory repo already cloned at $HOME/.claude/memory-shared"
    fi

    case "$(uname -s)" in
        Darwin)
            install_launchd_agent
            ;;
        Linux)
            install_systemd_timer
            ;;
        *)
            warning "[install] platform $(uname -s) not supported for memory sync; scheduler skipped"
            ;;
    esac
}

uninstall_memory_sync() {
    case "$(uname -s)" in
        Darwin)
            local target_dir="${LAUNCHD_TARGET_DIR:-$HOME/Library/LaunchAgents}"
            local target_plist="$target_dir/com.kcenon.claude-memory-sync.plist"
            if [ -f "$target_plist" ]; then
                if [ -z "${LAUNCHD_TARGET_DIR:-}" ]; then
                    launchctl bootout "gui/$(id -u)" "$target_plist" 2>/dev/null || \
                        launchctl unload "$target_plist" 2>/dev/null || true
                fi
                rm -f "$target_plist"
                success "launchd agent removed ($target_plist)"
            else
                info "launchd agent not present at $target_plist"
            fi
            ;;
        Linux)
            local target_dir="${SYSTEMD_USER_DIR:-$HOME/.config/systemd/user}"
            if [ -z "${SYSTEMD_USER_DIR:-}" ] && command -v systemctl >/dev/null 2>&1; then
                systemctl --user disable --now memory-sync.timer 2>/dev/null || true
            fi
            rm -f "$target_dir/memory-sync.service" "$target_dir/memory-sync.timer"
            if [ -z "${SYSTEMD_USER_DIR:-}" ] && command -v systemctl >/dev/null 2>&1; then
                systemctl --user daemon-reload 2>/dev/null || true
            fi
            success "systemd units removed from $target_dir"
            ;;
        *)
            info "platform $(uname -s) has no memory sync scheduler to remove"
            ;;
    esac
    success "[uninstall] memory sync scheduler removed"
}

# Early exit path for --uninstall-memory-sync (issue #527).
# Honored before the interactive install prompts so users can clean up
# the scheduler without re-running the full installer.
if [ "${1:-}" = "--uninstall-memory-sync" ]; then
    uninstall_memory_sync
    exit 0
fi

# 의존성 확인
check_dependencies
ensure_claude_cli

# 설치 타입 선택
echo ""
info "설치 타입을 선택하세요:"
echo "  1) 글로벌 설정만 설치 (~/.claude/)"
echo "  2) 프로젝트 설정만 설치 (현재 디렉토리)"
echo "  3) 둘 다 설치 (권장)"
echo "  4) Enterprise 설정만 설치 (관리자 권한 필요)"
echo "  5) 전체 설치 (Enterprise + Global + Project)"
echo ""
read -p "선택 (1-5) [기본값: 3]: " INSTALL_TYPE
INSTALL_TYPE=${INSTALL_TYPE:-3}

# Language selection prompts. Single source of truth in scripts/lib/install-prompts.sh
# (mirrored by scripts/lib/InstallPrompts.psm1 for PowerShell). The simplified UI
# offers English/Korean only; advanced policies (korean_plus_english, any) remain
# accepted by the validator but must be set via direct settings.json edit.
# Only the Global / Enterprise install paths touch settings.json; "english" leaves
# the dispatcher at its default and skips writing settings.json.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/install-prompts.sh"
prompt_content_language
prompt_agent_language

# Legacy settings.json migration warning (informational only).
# If the existing settings.json holds a CLAUDE_CONTENT_LANGUAGE value the
# simplified UI no longer surfaces (korean_plus_english, any), warn the
# operator before the new selection overwrites it.
warn_legacy_settings_value "$HOME/.claude/settings.json" || true

# Enterprise CLAUDE.md 충돌 감지 (issue #411)
# Enterprise 정책 경로는 Claude Code에서 최상위 우선순위를 가집니다 (install.sh:122-124 참조).
# 배포된 enterprise CLAUDE.md가 영어 강제인데 사용자가 더 허용적인 값을 골랐다면 경고합니다.
if [ "$CONTENT_LANGUAGE" != "english" ]; then
    ENTERPRISE_CLAUDE="$(get_enterprise_dir)/CLAUDE.md"
    if [ -f "$ENTERPRISE_CLAUDE" ] && grep -qi "written in english" "$ENTERPRISE_CLAUDE" 2>/dev/null; then
        echo ""
        warning "Enterprise 정책 충돌 감지"
        warning "  경로: $ENTERPRISE_CLAUDE"
        warning "  Enterprise CLAUDE.md가 영어 강제를 명시하지만, 선택한 정책은 '$CONTENT_LANGUAGE' 입니다."
        warning "  Enterprise 경로는 최상위 우선순위로 로드되므로 이 선택은 enterprise 정책 위반이 될 수 있습니다."
        echo ""
        read -p "그래도 '$CONTENT_LANGUAGE' 로 계속하시겠습니까? (y/n) [기본값: n]: " OVERRIDE_ENTERPRISE
        OVERRIDE_ENTERPRISE=${OVERRIDE_ENTERPRISE:-n}
        if [ "$OVERRIDE_ENTERPRISE" != "y" ]; then
            info "english로 재설정합니다."
            CONTENT_LANGUAGE="english"
        fi
    fi
fi

# Enterprise 설정 설치
if [ "$INSTALL_TYPE" = "4" ] || [ "$INSTALL_TYPE" = "5" ]; then
    install_enterprise
fi

# 글로벌 설정 설치
if [ "$INSTALL_TYPE" = "1" ] || [ "$INSTALL_TYPE" = "3" ] || [ "$INSTALL_TYPE" = "5" ]; then
    echo ""
    echo "======================================================"
    info "글로벌 설정 설치 중..."
    echo "======================================================"
    echo ""

    # ~/.claude 디렉토리 생성
    ensure_dir "$HOME/.claude"
    chmod 700 "$HOME/.claude"

    # 설치 매니페스트 헬퍼 로드
    # shellcheck disable=SC1091
    source "$BACKUP_DIR/scripts/install-manifest.sh"

    # 파일 설치 (매니페스트 가드 사용)
    for gf in CLAUDE.md commit-settings.md git-identity.md token-management.md; do
        if [ -f "$BACKUP_DIR/global/$gf" ]; then
            if guarded_copy "$BACKUP_DIR/global/$gf" "$HOME/.claude/$gf" "$gf"; then
                if [ "$gf" = "git-identity.md" ] || [ "$gf" = "token-management.md" ]; then
                    chmod 600 "$HOME/.claude/$gf"
                else
                    chmod 644 "$HOME/.claude/$gf"
                fi
                success "$gf 설치됨"
            else
                info "$gf 로컬 변경 유지"
            fi
        fi
    done

    # conversation-language.md 템플릿 렌더링
    # AGENT_DISPLAY_LANG is populated by prompt_agent_language() in
    # scripts/lib/install-prompts.sh; fall back if the prompt was skipped
    # (e.g. project-only install path).
    if [ -f "$BACKUP_DIR/global/conversation-language.md.tmpl" ]; then
        if [ -z "${AGENT_DISPLAY_LANG:-}" ]; then
            if [ "${AGENT_LANGUAGE:-korean}" = "english" ]; then
                AGENT_DISPLAY_LANG="English"
            else
                AGENT_DISPLAY_LANG="Korean"
            fi
        fi

        if guarded_template_copy "$BACKUP_DIR/global/conversation-language.md.tmpl" "$HOME/.claude/conversation-language.md" "conversation-language.md" "$AGENT_DISPLAY_LANG"; then
            chmod 644 "$HOME/.claude/conversation-language.md"
            success "conversation-language.md 설치됨 (언어: $AGENT_DISPLAY_LANG)"
        else
            info "conversation-language.md 로컬 변경 유지"
        fi
    fi

    # settings.json install (Hook configuration)
    # Intentionally bypasses guarded_copy: policy attributes (.language,
    # .env.CLAUDE_CONTENT_LANGUAGE) must be enforced on every install.
    # update_claude_settings_json (below) injects them and is responsible
    # for idempotent reset when the policy returns to default ("english").
    if [ -f "$BACKUP_DIR/global/settings.json" ]; then
        cp "$BACKUP_DIR/global/settings.json" "$HOME/.claude/"
        success "Hook 설정 (settings.json) 설치 완료!"

        # CLAUDE_CONTENT_LANGUAGE env 주입 및 Agent Language 속성 업데이트
        if update_claude_settings_json "$HOME/.claude/settings.json" "$AGENT_LANGUAGE" "$CONTENT_LANGUAGE"; then
            success "settings.json: language=$AGENT_LANGUAGE, CLAUDE_CONTENT_LANGUAGE=$CONTENT_LANGUAGE 업데이트 완료."
        else
            warning "jq가 설치되어 있지 않아 settings.json을 자동 업데이트할 수 없습니다."
            if [ "$CONTENT_LANGUAGE" != "english" ]; then
                echo "  수동으로 ~/.claude/settings.json 의 env 섹션에 다음을 추가하세요:"
                echo "    \"CLAUDE_CONTENT_LANGUAGE\": \"$CONTENT_LANGUAGE\""
            fi
            echo "  그리고 루트 레벨에 다음을 추가/수정하세요:"
            echo "    \"language\": \"$AGENT_LANGUAGE\""
        fi
    fi

    # hooks 디렉토리 설치 (외부 스크립트)
    if [ -d "$BACKUP_DIR/global/hooks" ]; then
        ensure_dir "$HOME/.claude/hooks"
        cp "$BACKUP_DIR/global/hooks"/*.sh "$HOME/.claude/hooks/" 2>/dev/null || true
        chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null || true
        success "Hook 스크립트 (hooks/) 설치 완료!"

        # Full-suite probe (issue #423): advertise which canonical guards the
        # plugin surface should stand down for. Plugin/hooks.json inspects this
        # file at runtime so its inline guards only activate in standalone
        # deployments. Listed hooks reflect the ones that overlap with plugin
        # inline guards. Atomic write (tmp + mv) so a partial write cannot
        # produce a half-valid probe.
        PROBE_DIR="$HOME/.claude"
        PROBE_FILE="$PROBE_DIR/.full-suite-active"
        SENS_GUARD=false
        DANG_GUARD=false
        [ -f "$HOME/.claude/hooks/sensitive-file-guard.sh" ] && SENS_GUARD=true
        [ -f "$HOME/.claude/hooks/dangerous-command-guard.sh" ] && DANG_GUARD=true
        if command -v python3 >/dev/null 2>&1; then
            TMP_PROBE="$(mktemp "${TMPDIR:-/tmp}/claude-probe.XXXXXX")"
            if SENS="$SENS_GUARD" DANG="$DANG_GUARD" python3 - "$TMP_PROBE" <<'PY' 2>/dev/null
import json, os, sys
path = sys.argv[1]
def flag(name):
    return os.environ.get(name, "false").lower() == "true"
doc = {
    "schema": 1,
    "hooks": {
        "sensitive-file-guard": flag("SENS"),
        "dangerous-command-guard": flag("DANG"),
    },
}
with open(path, "w") as f:
    json.dump(doc, f)
    f.write("\n")
PY
            then
                if mv "$TMP_PROBE" "$PROBE_FILE"; then
                    chmod 644 "$PROBE_FILE" 2>/dev/null || true
                    success "Full-suite probe 작성됨 (.full-suite-active)"
                fi
            else
                rm -f "$TMP_PROBE"
                warning "Full-suite probe 작성 실패 (python3 JSON 직렬화 오류)"
            fi
        else
            warning "python3 부재로 Full-suite probe 건너뜀 (플러그인 가드는 계속 활성화됨)"
        fi
    fi

    # 공유 검증 라이브러리 설치 (commit-message-guard.sh 및 pr-language-guard.sh에서 사용)
    if [ -d "$BACKUP_DIR/hooks/lib" ]; then
        ensure_dir "$HOME/.claude/hooks/lib"
        for lib in validate-commit-message.sh validate-language.sh; do
            if [ -f "$BACKUP_DIR/hooks/lib/$lib" ]; then
                cp "$BACKUP_DIR/hooks/lib/$lib" "$HOME/.claude/hooks/lib/"
                chmod +x "$HOME/.claude/hooks/lib/$lib"
            fi
        done
        success "공유 검증 라이브러리 설치 완료!"
    fi

    # scripts 디렉토리 설치 (statusline 등)
    if [ -d "$BACKUP_DIR/global/scripts" ]; then
        ensure_dir "$HOME/.claude/scripts"
        cp "$BACKUP_DIR/global/scripts"/*.sh "$HOME/.claude/scripts/" 2>/dev/null || true
        chmod +x "$HOME/.claude/scripts/"*.sh 2>/dev/null || true
        success "Statusline 스크립트 (scripts/) 설치 완료!"
    fi

    # commit-settings.md 설치 (CLAUDE.md에서 @./commit-settings.md로 참조)
    # issue #411: .tmpl이 있으면 정책 phrase를 치환해서 생성. 없으면 원본 복사.
    if [ -f "$BACKUP_DIR/global/commit-settings.md.tmpl" ]; then
        render_policy_tmpl "$BACKUP_DIR/global/commit-settings.md.tmpl" "$HOME/.claude/commit-settings.md"
        success "commit-settings.md 설치 완료 (policy phrase: $(get_policy_phrase))"
    elif [ -f "$BACKUP_DIR/global/commit-settings.md" ]; then
        cp "$BACKUP_DIR/global/commit-settings.md" "$HOME/.claude/"
        success "commit-settings.md 설치 완료!"
    fi

    # .claudeignore 설치
    if [ -f "$BACKUP_DIR/global/.claudeignore" ]; then
        cp "$BACKUP_DIR/global/.claudeignore" "$HOME/.claude/"
        success ".claudeignore 설치 완료!"
    fi

    # tmux.conf 설치
    if [ -f "$BACKUP_DIR/global/tmux.conf" ]; then
        cp "$BACKUP_DIR/global/tmux.conf" "$HOME/.claude/"
        success "tmux.conf 설치 완료!"
    fi

    # policies 디렉토리 설치 (Phase 1 dual-read; p4-timeline-* hooks read from here first)
    if [ -d "$BACKUP_DIR/global/policies" ]; then
        ensure_dir "$HOME/.claude/policies"
        cp "$BACKUP_DIR/global/policies"/*.json "$HOME/.claude/policies/" 2>/dev/null || true
        success "정책 파일 (policies/) 설치 완료!"
    fi

    # skills 디렉토리 설치 (global skills: harness, pr-work, issue-work, etc.)
    # `_internal/` 하위 격리 + `disable-model-invocation: true`가 적용된 스킬군은
    # Claude Code 슬래시 카탈로그에 노출되지 않으며, 글로벌 CLAUDE.md의
    # "Skill Aliases" 표에 따라 leading keyword 호출로만 실행된다.
    # `cp -r src/. dst/` 점 트릭으로 _policy.md 같은 루트 레벨 파일까지 복사한다.
    if [ -d "$BACKUP_DIR/global/skills" ]; then
        mkdir -p "$HOME/.claude/skills"
        cp -r "$BACKUP_DIR/global/skills"/. "$HOME/.claude/skills/"
        skill_count=$(find "$HOME/.claude/skills" -name "SKILL.md" | wc -l | tr -d ' ')
        success "Global Skills (${skill_count}개) 설치 완료!"
    fi

    # commands 디렉토리 설치
    if [ -d "$BACKUP_DIR/global/commands" ]; then
        cp -r "$BACKUP_DIR/global/commands" "$HOME/.claude/"
        success "Commands 디렉토리 설치 완료!"
    fi

    # ccstatusline 설정 복사 (~/.config/ccstatusline/ — ccstatusline의 기본 설정 경로)
    if [ -d "$BACKUP_DIR/global/ccstatusline" ]; then
        ensure_dir "$HOME/.config/ccstatusline"
        cp "$BACKUP_DIR/global/ccstatusline/settings.json" "$HOME/.config/ccstatusline/"
        success "ccstatusline 설정 설치 완료!"
    fi

    # npm 패키지 설치 (statusline 의존성)
    echo ""
    if command -v npm &> /dev/null; then
        read -p "Statusline npm 패키지를 설치하시겠습니까? (ccstatusline, claude-limitline) (y/n) [기본값: y]: " INSTALL_NPM
        INSTALL_NPM=${INSTALL_NPM:-y}
        if [ "$INSTALL_NPM" = "y" ]; then
            info "npm 패키지 설치 중..."
            if npm install -g ccstatusline claude-limitline 2>/dev/null; then
                success "npm 패키지 설치 완료! (ccstatusline, claude-limitline)"
            else
                warning "npm 패키지 설치 실패. 수동으로 설치하세요:"
                echo "    npm install -g ccstatusline claude-limitline"
            fi
        else
            info "npm 패키지 설치 건너뜀"
            echo "  수동 설치: npm install -g ccstatusline claude-limitline"
        fi
    else
        warning "npm이 설치되어 있지 않습니다."
        echo "  Node.js/npm 설치 후 아래 명령을 실행하세요:"
        echo "    npm install -g ccstatusline claude-limitline"
    fi

    success "글로벌 설정 설치 완료!"

    # Memory sync scheduler (issue #527).
    # Opt-in via CLAUDE_MEMORY_REPO_URL env var; no-op when unset.
    # Installed only on global-touching profiles (1, 3, 5) since the scheduler
    # invokes ~/.claude/scripts/memory-sync.sh which lives under the global tree.
    echo ""
    info "메모리 동기화 스케줄러 설치 중..."
    install_memory_sync

    # Git identity 개인화 안내
    echo ""
    warning "중요: git-identity.md를 개인 정보로 수정하세요!"
    echo "  편집: vi ~/.claude/git-identity.md"
fi

# 프로젝트 설정 설치
if [ "$INSTALL_TYPE" = "2" ] || [ "$INSTALL_TYPE" = "3" ] || [ "$INSTALL_TYPE" = "5" ]; then
    echo ""
    echo "======================================================"
    info "프로젝트 설정 설치 중..."
    echo "======================================================"
    echo ""

    # 설치 디렉토리 확인
    DEFAULT_PROJECT_DIR="$(pwd)"
    read -p "프로젝트 디렉토리 경로 [기본값: $DEFAULT_PROJECT_DIR]: " PROJECT_DIR
    PROJECT_DIR=${PROJECT_DIR:-$DEFAULT_PROJECT_DIR}

    if [ ! -d "$PROJECT_DIR" ]; then
        error "디렉토리가 존재하지 않습니다: $PROJECT_DIR"
        exit 1
    fi

    info "설치 경로: $PROJECT_DIR"

    # 파일 복사
    cp "$BACKUP_DIR/project/CLAUDE.md" "$PROJECT_DIR/"

    # .claude 디렉토리 설치
    ensure_dir "$PROJECT_DIR/.claude"

    # settings.json 설치 (Hook 설정)
    if [ -f "$BACKUP_DIR/project/.claude/settings.json" ]; then
        cp "$BACKUP_DIR/project/.claude/settings.json" "$PROJECT_DIR/.claude/"
        success "프로젝트 Hook 설정 (.claude/settings.json) 설치 완료!"
    fi

    # rules 디렉토리 설치
    if [ -d "$BACKUP_DIR/project/.claude/rules" ]; then
        cp -r "$BACKUP_DIR/project/.claude/rules" "$PROJECT_DIR/.claude/"
        # issue #411: rules/ 안의 .md.tmpl을 정책 phrase로 치환
        render_policy_tmpls_in_dir "$PROJECT_DIR/.claude/rules"
        success "Rules 디렉토리 설치 완료! (policy phrase: $(get_policy_phrase))"
    fi

    # Skills 디렉토리 설치
    if [ -d "$BACKUP_DIR/project/.claude/skills" ]; then
        cp -r "$BACKUP_DIR/project/.claude/skills" "$PROJECT_DIR/.claude/"
        success "Skills 디렉토리 설치 완료!"
    fi

    # commands 디렉토리 설치
    if [ -d "$BACKUP_DIR/project/.claude/commands" ]; then
        cp -r "$BACKUP_DIR/project/.claude/commands" "$PROJECT_DIR/.claude/"
        success "Commands 디렉토리 설치 완료!"
    fi

    # agents 디렉토리 설치
    if [ -d "$BACKUP_DIR/project/.claude/agents" ]; then
        cp -r "$BACKUP_DIR/project/.claude/agents" "$PROJECT_DIR/.claude/"
        success "Agents 디렉토리 설치 완료!"
    fi

    # .claudeignore 설치 (token optimization)
    if [ -f "$BACKUP_DIR/project/.claudeignore" ]; then
        cp "$BACKUP_DIR/project/.claudeignore" "$PROJECT_DIR/"
        success ".claudeignore 설치 완료!"
    fi

    # CLAUDE.local.md 생성 (개인 설정용)
    echo ""
    read -p "개인용 CLAUDE.local.md를 생성하시겠습니까? (y/n) [기본값: y]: " CREATE_LOCAL
    CREATE_LOCAL=${CREATE_LOCAL:-y}
    if [ "$CREATE_LOCAL" = "y" ]; then
        create_local_claude "$PROJECT_DIR"
    fi

    success "프로젝트 설정 설치 완료!"

    # 프로젝트별 커스터마이징 안내
    echo ""
    info "프로젝트에 맞게 설정을 커스터마이즈하세요:"
    echo "  - CLAUDE.md: 프로젝트 개요 수정"
    echo "  - .claude/rules/: 프로젝트별 코딩 표준 조정"
    echo "  - CLAUDE.local.md: 개인 환경 설정 (커밋 제외)"
fi

# 설치 완료 요약
echo ""
echo "======================================================"
success "설치 완료!"
echo "======================================================"
echo ""

info "설치된 파일:"
if [ "$INSTALL_TYPE" = "4" ] || [ "$INSTALL_TYPE" = "5" ]; then
    echo "  📂 Enterprise 설정:"
    echo "    - $(get_enterprise_dir)/CLAUDE.md"
    echo "    - $(get_enterprise_dir)/rules/"
fi

if [ "$INSTALL_TYPE" = "1" ] || [ "$INSTALL_TYPE" = "3" ] || [ "$INSTALL_TYPE" = "5" ]; then
    echo "  📂 글로벌 설정:"
    echo "    - ~/.claude/CLAUDE.md"
    echo "    - ~/.claude/commit-settings.md"
    for gf in conversation-language.md git-identity.md token-management.md; do
        [ -f "$HOME/.claude/$gf" ] && echo "    - ~/.claude/$gf"
    done
    echo "    - ~/.claude/.claudeignore"
    echo "    - ~/.claude/settings.json (Hook 설정)"
    echo "    - ~/.claude/hooks/ (외부 Hook 스크립트)"
    echo "    - ~/.claude/skills/ (Global Skills)"
    echo "    - ~/.claude/commands/ (Global Commands)"
    echo "    - ~/.claude/scripts/ (Statusline 스크립트)"
    echo "    - ~/.config/ccstatusline/ (ccstatusline 설정)"
fi

if [ "$INSTALL_TYPE" = "2" ] || [ "$INSTALL_TYPE" = "3" ] || [ "$INSTALL_TYPE" = "5" ]; then
    echo "  📂 프로젝트 설정:"
    echo "    - $PROJECT_DIR/CLAUDE.md"
    echo "    - $PROJECT_DIR/.claudeignore (Token Optimization)"
    echo "    - $PROJECT_DIR/.claude/rules/ (Guidelines)"
    echo "    - $PROJECT_DIR/.claude/settings.json (Hook 설정)"
    if [ -d "$BACKUP_DIR/project/.claude/skills" ]; then
        echo "    - $PROJECT_DIR/.claude/skills/ (Skills)"
    fi
    if [ -d "$BACKUP_DIR/project/.claude/commands" ]; then
        echo "    - $PROJECT_DIR/.claude/commands/ (Commands)"
    fi
    if [ -d "$BACKUP_DIR/project/.claude/agents" ]; then
        echo "    - $PROJECT_DIR/.claude/agents/ (Agents)"
    fi
fi

echo ""
echo "======================================================"
info "다음 단계"
echo "======================================================"
echo ""
echo "1. ⚙️  Git identity 개인화 (필수!):"
echo "     vi ~/.claude/git-identity.md"
echo ""
echo "2. 🔄 Claude Code 재시작:"
echo "     새 터미널을 열거나 현재 세션 종료 후 재시작"
echo ""
echo "3. ✅ 설정 확인:"
echo "     cat ~/.claude/CLAUDE.md"
echo ""
echo "4. 📦 Statusline npm 패키지 (미설치 시):"
echo "     npm install -g ccstatusline claude-limitline"
echo ""
echo "5. 📚 사용 가이드:"
echo "     cat CLAUDE_CODE_REAL_GUIDE.md"
echo ""

success "설치가 완료되었습니다! 🎉"
