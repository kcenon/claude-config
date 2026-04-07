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

# 함수: 백업 생성
create_backup() {
    local target="$1"
    if [ -e "$target" ]; then
        local backup_name="${target}.backup_$(date +%Y%m%d_%H%M%S)"
        cp -r "$target" "$backup_name"
        info "기존 파일 백업: $backup_name"
    fi
}

# 함수: 디렉토리 생성
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        success "디렉토리 생성: $dir"
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

# 함수: 버전 비교 (v1 >= v2 이면 true)
version_gte() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# 함수: Claude Code 버전 확인
check_claude_version() {
    local MIN_CLAUDE_VERSION="2.2.0"

    echo ""
    info "Claude Code 버전 확인 중..."

    if ! command -v claude &> /dev/null; then
        warning "Claude Code CLI가 설치되어 있지 않습니다."
        info "설치 후에도 설정 파일은 정상 동작합니다. 계속 진행합니다."
        return 0
    fi

    local claude_version
    claude_version=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [ -z "$claude_version" ]; then
        warning "Claude Code 버전을 확인할 수 없습니다."
        info "계속 진행합니다."
        return 0
    fi

    if version_gte "$claude_version" "$MIN_CLAUDE_VERSION"; then
        success "Claude Code v${claude_version} (최소 요구: v${MIN_CLAUDE_VERSION})"
    else
        echo ""
        warning "Claude Code v${claude_version}이(가) 감지되었습니다."
        warning "이 설정은 v${MIN_CLAUDE_VERSION} 이상에서 테스트되었습니다."
        echo ""
        read -p "계속 진행하시겠습니까? (y/N) [기본값: N]: " CONTINUE_INSTALL
        CONTINUE_INSTALL=${CONTINUE_INSTALL:-N}
        if [ "$CONTINUE_INSTALL" != "y" ] && [ "$CONTINUE_INSTALL" != "Y" ]; then
            error "설치가 취소되었습니다. Claude Code를 업데이트한 후 다시 시도하세요."
            exit 1
        fi
        warning "낮은 버전으로 계속 진행합니다."
    fi
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
            sudo cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$enterprise_dir/"
            success "CLAUDE.md 설치됨"

            # rules 디렉토리 복사
            if [ -d "$BACKUP_DIR/enterprise/rules" ]; then
                sudo cp -r "$BACKUP_DIR/enterprise/rules"/* "$enterprise_dir/rules/" 2>/dev/null || true
                success "rules 디렉토리 설치됨"
            fi

            # 권한 설정 (읽기 전용)
            sudo chmod 755 "$enterprise_dir"
            sudo chmod 644 "$enterprise_dir/CLAUDE.md"
            sudo chmod 755 "$enterprise_dir/rules"
            sudo chmod 644 "$enterprise_dir/rules"/* 2>/dev/null || true
        else
            # sudo 불필요
            mkdir -p "$enterprise_dir"
            mkdir -p "$enterprise_dir/rules"
            cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$enterprise_dir/"
            success "CLAUDE.md 설치됨"

            if [ -d "$BACKUP_DIR/enterprise/rules" ]; then
                cp -r "$BACKUP_DIR/enterprise/rules"/* "$enterprise_dir/rules/" 2>/dev/null || true
                success "rules 디렉토리 설치됨"
            fi
        fi
    else
        # Windows
        mkdir -p "$enterprise_dir"
        mkdir -p "$enterprise_dir/rules"
        cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$enterprise_dir/"
        success "CLAUDE.md 설치됨"

        if [ -d "$BACKUP_DIR/enterprise/rules" ]; then
            cp -r "$BACKUP_DIR/enterprise/rules"/* "$enterprise_dir/rules/" 2>/dev/null || true
            success "rules 디렉토리 설치됨"
        fi
    fi

    success "Enterprise 설정 설치 완료!"
    echo ""
    warning "중요: enterprise/CLAUDE.md를 조직 정책에 맞게 수정하세요!"
}

# Claude Code 버전 확인
check_claude_version

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

    # 기존 파일 백업 여부 확인
    BACKUP_EXISTING="y"
    if [ -f "$HOME/.claude/CLAUDE.md" ]; then
        warning "기존 CLAUDE.md가 존재합니다."
        read -p "백업 후 덮어쓰시겠습니까? (y/n) [기본값: y]: " BACKUP_EXISTING
        BACKUP_EXISTING=${BACKUP_EXISTING:-y}
    fi

    # 파일 설치
    if [ "$BACKUP_EXISTING" = "y" ]; then
        create_backup "$HOME/.claude/CLAUDE.md"
        create_backup "$HOME/.claude/conversation-language.md"
        create_backup "$HOME/.claude/git-identity.md"
        create_backup "$HOME/.claude/token-management.md"

        cp "$BACKUP_DIR/global/CLAUDE.md" "$HOME/.claude/"
        cp "$BACKUP_DIR/global/conversation-language.md" "$HOME/.claude/"
        cp "$BACKUP_DIR/global/git-identity.md" "$HOME/.claude/"
        cp "$BACKUP_DIR/global/token-management.md" "$HOME/.claude/"

        # settings.json 설치 (Hook 설정)
        if [ -f "$BACKUP_DIR/global/settings.json" ]; then
            create_backup "$HOME/.claude/settings.json"
            cp "$BACKUP_DIR/global/settings.json" "$HOME/.claude/"
            success "Hook 설정 (settings.json) 설치 완료!"
        fi

        # hooks 디렉토리 설치 (외부 스크립트)
        if [ -d "$BACKUP_DIR/global/hooks" ]; then
            ensure_dir "$HOME/.claude/hooks"
            cp "$BACKUP_DIR/global/hooks"/*.sh "$HOME/.claude/hooks/" 2>/dev/null || true
            chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null || true
            success "Hook 스크립트 (hooks/) 설치 완료!"
        fi

        # 공유 검증 라이브러리 설치 (commit-message-guard.sh에서 사용)
        if [ -f "$BACKUP_DIR/hooks/lib/validate-commit-message.sh" ]; then
            ensure_dir "$HOME/.claude/hooks/lib"
            cp "$BACKUP_DIR/hooks/lib/validate-commit-message.sh" "$HOME/.claude/hooks/lib/"
            chmod +x "$HOME/.claude/hooks/lib/validate-commit-message.sh"
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
        if [ -f "$BACKUP_DIR/global/commit-settings.md" ]; then
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

        # skills 디렉토리 설치 (global skills: harness, pr-work, issue-work, etc.)
        if [ -d "$BACKUP_DIR/global/skills" ]; then
            if [ -d "$HOME/.claude/skills" ]; then
                create_backup "$HOME/.claude/skills"
            fi
            mkdir -p "$HOME/.claude/skills"
            for skill_dir in "$BACKUP_DIR/global/skills"/*/; do
                if [ -d "$skill_dir" ]; then
                    cp -r "$skill_dir" "$HOME/.claude/skills/"
                fi
            done
            local skill_count
            skill_count=$(find "$HOME/.claude/skills" -name "SKILL.md" | wc -l | tr -d ' ')
            success "Global Skills (${skill_count}개) 설치 완료!"
        fi

        # commands 디렉토리 설치
        if [ -d "$BACKUP_DIR/global/commands" ]; then
            if [ -d "$HOME/.claude/commands" ]; then
                create_backup "$HOME/.claude/commands"
            fi
            cp -r "$BACKUP_DIR/global/commands" "$HOME/.claude/"
            success "Commands 디렉토��� 설치 완료!"
        fi

        # ccstatusline 설정 복사 (~/.config/ccstatusline/ — ccstatusline의 기본 설정 경로)
        if [ -d "$BACKUP_DIR/global/ccstatusline" ]; then
            ensure_dir "$HOME/.config/ccstatusline"
            cp "$BACKUP_DIR/global/ccstatusline/settings.json" "$HOME/.config/ccstatusline/"
            success "ccstatusline 설정 (~/.config/ccstatusline/settings.json) 설��� 완료!"
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

        # Git identity 개인화 안내
        echo ""
        warning "중요: git-identity.md를 개인 정보로 수정하세요!"
        echo "  편집: vi ~/.claude/git-identity.md"
    else
        info "글로벌 설정 설치 건너뜀"
    fi
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

    # 기존 파일 백업
    if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
        create_backup "$PROJECT_DIR/CLAUDE.md"
    fi
    if [ -d "$PROJECT_DIR/.claude/rules" ]; then
        create_backup "$PROJECT_DIR/.claude/rules"
    fi

    # 파일 복사
    cp "$BACKUP_DIR/project/CLAUDE.md" "$PROJECT_DIR/"

    # .claude 디렉토리 설치
    ensure_dir "$PROJECT_DIR/.claude"

    # settings.json 설치 (Hook 설정)
    if [ -f "$BACKUP_DIR/project/.claude/settings.json" ]; then
        create_backup "$PROJECT_DIR/.claude/settings.json"
        cp "$BACKUP_DIR/project/.claude/settings.json" "$PROJECT_DIR/.claude/"
        success "프로젝트 Hook 설정 (.claude/settings.json) 설치 완료!"
    fi

    # rules 디렉토리 설치
    if [ -d "$BACKUP_DIR/project/.claude/rules" ]; then
        cp -r "$BACKUP_DIR/project/.claude/rules" "$PROJECT_DIR/.claude/"
        success "Rules 디렉토리 설치 완료!"
    fi

    # Skills 디렉토리 설치
    if [ -d "$BACKUP_DIR/project/.claude/skills" ]; then
        if [ -d "$PROJECT_DIR/.claude/skills" ]; then
            create_backup "$PROJECT_DIR/.claude/skills"
        fi
        cp -r "$BACKUP_DIR/project/.claude/skills" "$PROJECT_DIR/.claude/"
        success "Skills 디렉토리 설치 완료!"
    fi

    # commands 디렉토리 설치
    if [ -d "$BACKUP_DIR/project/.claude/commands" ]; then
        if [ -d "$PROJECT_DIR/.claude/commands" ]; then
            create_backup "$PROJECT_DIR/.claude/commands"
        fi
        cp -r "$BACKUP_DIR/project/.claude/commands" "$PROJECT_DIR/.claude/"
        success "Commands 디렉토리 설치 완료!"
    fi

    # agents 디렉토리 설치
    if [ -d "$BACKUP_DIR/project/.claude/agents" ]; then
        if [ -d "$PROJECT_DIR/.claude/agents" ]; then
            create_backup "$PROJECT_DIR/.claude/agents"
        fi
        cp -r "$BACKUP_DIR/project/.claude/agents" "$PROJECT_DIR/.claude/"
        success "Agents 디렉토리 설치 완료!"
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
    echo "    - ~/.claude/conversation-language.md"
    echo "    - ~/.claude/git-identity.md"
    echo "    - ~/.claude/token-management.md"
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
