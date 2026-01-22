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

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# GitHub 저장소 설정
GITHUB_USER="${GITHUB_USER:-kcenon}"
GITHUB_REPO="${GITHUB_REPO:-claude-config}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

# 설치 디렉토리
INSTALL_DIR="${INSTALL_DIR:-$HOME/claude_config_backup}"
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

# 의존성 확인
check_dependencies() {
    info "의존성 확인 중..."

    if ! command -v git &> /dev/null; then
        error "git이 설치되어 있지 않습니다. 먼저 git을 설치하세요."
    fi

    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        error "curl 또는 wget이 필요합니다."
    fi

    success "의존성 확인 완료"
}

# 저장소 클론
clone_repository() {
    info "저장소 클론 중..."

    if [ -d "$INSTALL_DIR" ]; then
        warning "기존 설치 디렉토리가 존재합니다: $INSTALL_DIR"
        read -p "덮어쓰시겠습니까? (y/n) [기본값: n]: " OVERWRITE
        OVERWRITE=${OVERWRITE:-n}

        if [ "$OVERWRITE" = "y" ]; then
            rm -rf "$INSTALL_DIR"
        else
            info "기존 디렉토리를 사용합니다. git pull 실행..."
            cd "$INSTALL_DIR"
            git pull origin "$GITHUB_BRANCH"
            return
        fi
    fi

    # GitHub에서 클론
    git clone "https://github.com/$GITHUB_USER/$GITHUB_REPO.git" "$INSTALL_DIR"
    success "저장소 클론 완료: $INSTALL_DIR"
}

# 글로벌 설정 설치
install_global() {
    info "글로벌 설정 설치 중..."

    # ~/.claude 디렉토리 생성
    mkdir -p "$CLAUDE_DIR"

    # 기존 파일 백업
    if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
        local backup_name="$CLAUDE_DIR/CLAUDE.md.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$CLAUDE_DIR/CLAUDE.md" "$backup_name"
        info "기존 CLAUDE.md 백업: $backup_name"
    fi

    # 파일 복사
    cp "$INSTALL_DIR/global/CLAUDE.md" "$CLAUDE_DIR/"
    cp "$INSTALL_DIR/global/conversation-language.md" "$CLAUDE_DIR/"
    cp "$INSTALL_DIR/global/git-identity.md" "$CLAUDE_DIR/"
    cp "$INSTALL_DIR/global/token-management.md" "$CLAUDE_DIR/"

    success "글로벌 설정 설치 완료"
}

# Git identity 개인화 안내
personalize_git_identity() {
    echo ""
    warning "중요: Git Identity를 개인 정보로 수정해야 합니다!"
    echo ""
    echo "  현재 설정:"
    grep -E "^(name|email):" "$CLAUDE_DIR/git-identity.md" 2>/dev/null || true
    echo ""
    echo "  수정 방법:"
    echo "    vi ~/.claude/git-identity.md"
    echo ""

    read -p "지금 수정하시겠습니까? (y/n) [기본값: n]: " EDIT_NOW
    EDIT_NOW=${EDIT_NOW:-n}

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
    read -p "선택 (1-4) [기본값: 1]: " INSTALL_TYPE
    INSTALL_TYPE=${INSTALL_TYPE:-1}
}

# 프로젝트 설정 설치
install_project() {
    echo ""
    read -p "프로젝트 디렉토리 경로 [기본값: $(pwd)]: " PROJECT_DIR
    PROJECT_DIR=${PROJECT_DIR:-$(pwd)}

    if [ ! -d "$PROJECT_DIR" ]; then
        error "디렉토리가 존재하지 않습니다: $PROJECT_DIR"
    fi

    info "프로젝트 설정 설치 중: $PROJECT_DIR"

    # 파일 복사
    cp "$INSTALL_DIR/project/CLAUDE.md" "$PROJECT_DIR/"

    # .claude 디렉토리 설치
    mkdir -p "$PROJECT_DIR/.claude"
    [ -d "$INSTALL_DIR/project/.claude/rules" ] && cp -r "$INSTALL_DIR/project/.claude/rules" "$PROJECT_DIR/.claude/"
    [ -d "$INSTALL_DIR/project/.claude/skills" ] && cp -r "$INSTALL_DIR/project/.claude/skills" "$PROJECT_DIR/.claude/"
    [ -d "$INSTALL_DIR/project/.claude/commands" ] && cp -r "$INSTALL_DIR/project/.claude/commands" "$PROJECT_DIR/.claude/"
    [ -d "$INSTALL_DIR/project/.claude/agents" ] && cp -r "$INSTALL_DIR/project/.claude/agents" "$PROJECT_DIR/.claude/"
    [ -f "$INSTALL_DIR/project/.claude/settings.json" ] && cp "$INSTALL_DIR/project/.claude/settings.json" "$PROJECT_DIR/.claude/"

    success "프로젝트 설정 설치 완료"
}

# 메인 실행
main() {
    check_dependencies
    clone_repository
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
    echo "  3. 동기화: cd $INSTALL_DIR && ./scripts/sync.sh"
    echo ""

    success "Happy Coding with Claude! 🎉"
}

# 스크립트 실행
main "$@"
