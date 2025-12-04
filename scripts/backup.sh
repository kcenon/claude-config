#!/bin/bash

# Claude Configuration Backup Tool
# =================================
# 현재 시스템의 CLAUDE.md 설정을 백업하는 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 스크립트 디렉토리
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BACKUP_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║         Claude Configuration Backup Tool                     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 함수 정의
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# 백업 타입 선택
echo ""
info "백업 타입을 선택하세요:"
echo "  1) 글로벌 설정만 백업 (~/.claude/)"
echo "  2) 프로젝트 설정만 백업"
echo "  3) 둘 다 백업 (권장)"
echo ""
read -p "선택 (1-3) [기본값: 3]: " BACKUP_TYPE
BACKUP_TYPE=${BACKUP_TYPE:-3}

# 백업 디렉토리 생성
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_BACKUP="$BACKUP_DIR/backup_$TIMESTAMP"
mkdir -p "$TEMP_BACKUP/global"
mkdir -p "$TEMP_BACKUP/project/claude-guidelines"

# 글로벌 설정 백업
if [ "$BACKUP_TYPE" = "1" ] || [ "$BACKUP_TYPE" = "3" ]; then
    echo ""
    echo "======================================================"
    info "글로벌 설정 백업 중..."
    echo "======================================================"

    if [ -f "$HOME/.claude/CLAUDE.md" ]; then
        cp "$HOME/.claude/CLAUDE.md" "$TEMP_BACKUP/global/"
        success "CLAUDE.md 백업됨"
    else
        warning "CLAUDE.md 없음"
    fi

    if [ -f "$HOME/.claude/conversation-language.md" ]; then
        cp "$HOME/.claude/conversation-language.md" "$TEMP_BACKUP/global/"
        success "conversation-language.md 백업됨"
    fi

    if [ -f "$HOME/.claude/git-identity.md" ]; then
        cp "$HOME/.claude/git-identity.md" "$TEMP_BACKUP/global/"
        success "git-identity.md 백업됨"
    fi

    if [ -f "$HOME/.claude/token-management.md" ]; then
        cp "$HOME/.claude/token-management.md" "$TEMP_BACKUP/global/"
        success "token-management.md 백업됨"
    fi
fi

# 프로젝트 설정 백업
if [ "$BACKUP_TYPE" = "2" ] || [ "$BACKUP_TYPE" = "3" ]; then
    echo ""
    echo "======================================================"
    info "프로젝트 설정 백업 중..."
    echo "======================================================"

    # 프로젝트 디렉토리 입력
    read -p "프로젝트 디렉토리 경로: " PROJECT_DIR

    if [ -z "$PROJECT_DIR" ]; then
        warning "프로젝트 디렉토리 미지정, 건너뜀"
    elif [ ! -d "$PROJECT_DIR" ]; then
        error "디렉토리가 존재하지 않음: $PROJECT_DIR"
    else
        if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
            cp "$PROJECT_DIR/CLAUDE.md" "$TEMP_BACKUP/project/"
            success "프로젝트 CLAUDE.md 백업됨"
        fi

        if [ -d "$PROJECT_DIR/claude-guidelines" ]; then
            cp -r "$PROJECT_DIR/claude-guidelines"/* "$TEMP_BACKUP/project/claude-guidelines/"
            success "claude-guidelines 백업됨"
        fi
    fi
fi

# 백업 완료 후 처리
echo ""
echo "======================================================"
info "백업 완료 처리 중..."
echo "======================================================"

# 기존 백업 대체 여부 확인
echo ""
read -p "기존 백업을 이 백업으로 대체하시겠습니까? (y/n) [기본값: y]: " REPLACE
REPLACE=${REPLACE:-y}

if [ "$REPLACE" = "y" ]; then
    # global 디렉토리 업데이트
    if [ -d "$TEMP_BACKUP/global" ] && [ "$(ls -A $TEMP_BACKUP/global)" ]; then
        rm -rf "$BACKUP_DIR/global"/*
        cp -r "$TEMP_BACKUP/global"/* "$BACKUP_DIR/global/" 2>/dev/null || true
        success "글로벌 백업 업데이트됨"
    fi

    # project 디렉토리 업데이트
    if [ -d "$TEMP_BACKUP/project" ] && [ "$(ls -A $TEMP_BACKUP/project)" ]; then
        rm -rf "$BACKUP_DIR/project"/*
        cp -r "$TEMP_BACKUP/project"/* "$BACKUP_DIR/project/" 2>/dev/null || true
        success "프로젝트 백업 업데이트됨"
    fi

    # 임시 백업 제거
    rm -rf "$TEMP_BACKUP"
    info "임시 백업 제거됨"
else
    success "타임스탬프 백업 유지: $TEMP_BACKUP"
fi

# 백업 요약
echo ""
echo "======================================================"
success "백업 완료!"
echo "======================================================"
echo ""

info "백업된 파일 위치: $BACKUP_DIR"
echo ""
echo "  📂 글로벌 설정:"
ls -1 "$BACKUP_DIR/global/" 2>/dev/null | sed 's/^/    - /' || echo "    (없음)"

echo ""
echo "  📂 프로젝트 설정:"
if [ -f "$BACKUP_DIR/project/CLAUDE.md" ]; then
    echo "    - CLAUDE.md"
fi
if [ -d "$BACKUP_DIR/project/claude-guidelines" ] && [ "$(ls -A $BACKUP_DIR/project/claude-guidelines)" ]; then
    echo "    - claude-guidelines/"
fi

echo ""
info "다음 단계:"
echo "  1. 백업 내용 확인: ls -la $BACKUP_DIR"
echo "  2. 다른 시스템에 복사"
echo "  3. 새 시스템에서 ./scripts/install.sh 실행"
echo ""

success "백업이 완료되었습니다! 🎉"
