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

# pre-commit hook 설치
info "pre-commit hook 설치 중..."

if [ -f "$GIT_HOOKS_DIR/pre-commit" ]; then
    warning "기존 pre-commit hook이 존재합니다."
    read -p "덮어쓰시겠습니까? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "설치를 건너뜁니다."
        exit 0
    fi
fi

cp "$SCRIPT_DIR/pre-commit" "$GIT_HOOKS_DIR/pre-commit"
chmod +x "$GIT_HOOKS_DIR/pre-commit"

success "pre-commit hook 설치 완료!"

echo ""
info "설치된 hooks:"
ls -la "$GIT_HOOKS_DIR" | grep -v ".sample"

echo ""
success "Git hooks 설치가 완료되었습니다."
info "SKILL.md 파일을 커밋할 때 자동으로 검증이 실행됩니다."
