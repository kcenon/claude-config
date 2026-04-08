#!/bin/bash

# Git Hooks Installation Script
# =============================
# Git hooks를 설치하는 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 함수 정의
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# 스크립트 디렉토리
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║              Git Hooks Installation Script                    ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Git 저장소 확인
if [ ! -d "$REPO_ROOT/.git" ]; then
    error "Git 저장소가 아닙니다."
    exit 1
fi

# hooks 디렉토리 확인
if [ ! -d "$GIT_HOOKS_DIR" ]; then
    mkdir -p "$GIT_HOOKS_DIR"
    success "Git hooks 디렉토리 생성: $GIT_HOOKS_DIR"
fi

# hook 설치 함수 (덮어쓰기/병합/건너뛰기 지원)
install_hook() {
    local hook_name="$1"
    local source_file="$SCRIPT_DIR/$hook_name"
    local target_file="$GIT_HOOKS_DIR/$hook_name"

    info "$hook_name hook 설치 중..."

    if [ -f "$target_file" ]; then
        warning "기존 $hook_name hook이 존재합니다."
        echo "  1) 덮어쓰기 (교체)"
        echo "  2) 병합 (기존 hook 뒤에 추가)"
        echo "  3) 건너뛰기"
        read -p "  선택 (1-3) [기본값: 3]: " choice
        choice=${choice:-3}

        case "$choice" in
            1)
                cp "$source_file" "$target_file"
                chmod +x "$target_file"
                success "$hook_name hook 덮어쓰기 완료!"
                ;;
            2)
                {
                    echo ""
                    echo "# --- claude-config hooks (appended $(date +%Y-%m-%d)) ---"
                    tail -n +2 "$source_file"
                } >> "$target_file"
                chmod +x "$target_file"
                success "$hook_name hook 병합 완료!"
                ;;
            3)
                info "$hook_name 설치를 건너뜁니다."
                ;;
            *)
                info "$hook_name 설치를 건너뜁니다."
                ;;
        esac
    else
        cp "$source_file" "$target_file"
        chmod +x "$target_file"
        success "$hook_name hook 설치 완료!"
    fi
}

# pre-commit hook 설치
install_hook "pre-commit"

# commit-msg hook 설치
echo ""
install_hook "commit-msg"

# 공유 검증 라이브러리 설치
info "검증 라이브러리 설치 중..."
mkdir -p "$GIT_HOOKS_DIR/lib"
cp "$SCRIPT_DIR/lib/validate-commit-message.sh" "$GIT_HOOKS_DIR/lib/"
chmod +x "$GIT_HOOKS_DIR/lib/validate-commit-message.sh"
success "검증 라이브러리 설치 완료!"

echo ""
info "설치된 hooks:"
ls -la "$GIT_HOOKS_DIR" | grep -v ".sample"

echo ""
success "Git hooks 설치가 완료되었습니다."
info "커밋 시 SKILL.md 검증과 커밋 메시지 검증이 자동으로 실행됩니다."
