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
    if [ -d "$PROJECT_DIR/claude-guidelines" ]; then
        create_backup "$PROJECT_DIR/claude-guidelines"
    fi

    # 파일 복사
    cp "$BACKUP_DIR/project/CLAUDE.md" "$PROJECT_DIR/"
    cp -r "$BACKUP_DIR/project/claude-guidelines" "$PROJECT_DIR/"

    # .claude 디렉토리 및 settings.json 설치 (Hook 설정)
    if [ -d "$BACKUP_DIR/project/.claude" ]; then
        ensure_dir "$PROJECT_DIR/.claude"
        if [ -f "$BACKUP_DIR/project/.claude/settings.json" ]; then
            create_backup "$PROJECT_DIR/.claude/settings.json"
            cp "$BACKUP_DIR/project/.claude/settings.json" "$PROJECT_DIR/.claude/"
            success "프로젝트 Hook 설정 (.claude/settings.json) 설치 완료!"
        fi

        # Skills 디렉토리 설치
        if [ -d "$BACKUP_DIR/project/.claude/skills" ]; then
            if [ -d "$PROJECT_DIR/.claude/skills" ]; then
                create_backup "$PROJECT_DIR/.claude/skills"
            fi
            cp -r "$BACKUP_DIR/project/.claude/skills" "$PROJECT_DIR/.claude/"
            success "Skills 디렉토리 설치 완료!"
        fi
    fi

    success "프로젝트 설정 설치 완료!"

    # 프로젝트별 커스터마이징 안내
    echo ""
    info "프로젝트에 맞게 설정을 커스터마이즈하세요:"
    echo "  - CLAUDE.md: 프로젝트 개요 수정"
    echo "  - claude-guidelines/: 프로젝트별 코딩 표준 조정"
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
    echo "    - ~/.claude/conversation-language.md"
    echo "    - ~/.claude/git-identity.md"
    echo "    - ~/.claude/token-management.md"
    echo "    - ~/.claude/settings.json (Hook 설정)"
    echo "    - ~/.claude/hooks/ (외부 Hook 스크립트)"
fi

if [ "$INSTALL_TYPE" = "2" ] || [ "$INSTALL_TYPE" = "3" ] || [ "$INSTALL_TYPE" = "5" ]; then
    echo "  📂 프로젝트 설정:"
    echo "    - $PROJECT_DIR/CLAUDE.md"
    echo "    - $PROJECT_DIR/claude-guidelines/"
    echo "    - $PROJECT_DIR/.claude/settings.json (Hook 설정)"
    if [ -d "$BACKUP_DIR/project/.claude/skills" ]; then
        echo "    - $PROJECT_DIR/.claude/skills/ (Skills)"
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
echo "4. 📚 사용 가이드:"
echo "     cat CLAUDE_CODE_REAL_GUIDE.md"
echo ""

success "설치가 완료되었습니다! 🎉"
