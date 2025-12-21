#!/bin/bash

# Claude Configuration Verification Tool
# =======================================
# 백업의 무결성과 완전성을 확인하는 스크립트

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
║       Claude Configuration Verification Tool                 ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 함수 정의
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# 카운터
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# 검증 함수
check_file() {
    local file="$1"
    local desc="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [ -f "$file" ]; then
        local size=$(wc -c < "$file" | tr -d ' ')
        success "$desc (${size} bytes)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        error "$desc (없음)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

check_dir() {
    local dir="$1"
    local desc="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [ -d "$dir" ]; then
        local count=$(find "$dir" -type f | wc -l | tr -d ' ')
        success "$desc (${count} 파일)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        error "$desc (없음)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

check_executable() {
    local file="$1"
    local desc="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [ -x "$file" ]; then
        success "$desc (실행 가능)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        warning "$desc (실행 권한 없음)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# 백업 디렉토리 구조 검증
echo ""
echo "======================================================"
info "백업 구조 검증"
echo "======================================================"
echo ""

echo "📂 디렉토리 구조:"
check_dir "$BACKUP_DIR/global" "글로벌 설정 디렉토리"
check_dir "$BACKUP_DIR/project" "프로젝트 설정 디렉토리"
check_dir "$BACKUP_DIR/scripts" "스크립트 디렉토리"

# 글로벌 설정 파일 검증
echo ""
echo "======================================================"
info "글로벌 설정 파일 검증"
echo "======================================================"
echo ""

check_file "$BACKUP_DIR/global/CLAUDE.md" "CLAUDE.md"
check_file "$BACKUP_DIR/global/conversation-language.md" "conversation-language.md"
check_file "$BACKUP_DIR/global/git-identity.md" "git-identity.md"
check_file "$BACKUP_DIR/global/token-management.md" "token-management.md"
check_file "$BACKUP_DIR/global/settings.json" "settings.json (Hook 설정)"

# JSON 유효성 검사
if [ -f "$BACKUP_DIR/global/settings.json" ]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if python3 -m json.tool "$BACKUP_DIR/global/settings.json" > /dev/null 2>&1; then
        success "settings.json JSON 유효성 검사 통과"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        error "settings.json JSON 유효성 검사 실패"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
fi

# 프로젝트 설정 파일 검증
echo ""
echo "======================================================"
info "프로젝트 설정 파일 검증"
echo "======================================================"
echo ""

check_file "$BACKUP_DIR/project/CLAUDE.md" "프로젝트 CLAUDE.md"
check_dir "$BACKUP_DIR/project/claude-guidelines" "claude-guidelines 디렉토리"
check_dir "$BACKUP_DIR/project/.claude" ".claude 디렉토리"
check_file "$BACKUP_DIR/project/.claude/settings.json" "프로젝트 settings.json (Hook 설정)"

# 프로젝트 settings.json JSON 유효성 검사
if [ -f "$BACKUP_DIR/project/.claude/settings.json" ]; then
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if python3 -m json.tool "$BACKUP_DIR/project/.claude/settings.json" > /dev/null 2>&1; then
        success "프로젝트 settings.json JSON 유효성 검사 통과"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        error "프로젝트 settings.json JSON 유효성 검사 실패"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
fi

# Skills 디렉토리 검증
echo ""
echo "======================================================"
info "Skills 디렉토리 검증"
echo "======================================================"
echo ""

check_dir "$BACKUP_DIR/project/.claude/skills" "skills 디렉토리"

# 각 Skill의 SKILL.md 파일 존재 확인
if [ -d "$BACKUP_DIR/project/.claude/skills" ]; then
    for skill_dir in "$BACKUP_DIR/project/.claude/skills"/*/; do
        if [ -d "$skill_dir" ]; then
            skill_name=$(basename "$skill_dir")
            TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
            if [ -f "${skill_dir}SKILL.md" ]; then
                success "${skill_name}/SKILL.md 존재"
                PASSED_CHECKS=$((PASSED_CHECKS + 1))
            else
                warning "${skill_name}/SKILL.md 없음"
                FAILED_CHECKS=$((FAILED_CHECKS + 1))
            fi
        fi
    done
fi

if [ -d "$BACKUP_DIR/project/claude-guidelines" ]; then
    check_dir "$BACKUP_DIR/project/claude-guidelines/coding-standards" "coding-standards"
    check_dir "$BACKUP_DIR/project/claude-guidelines/operations" "operations"
    check_dir "$BACKUP_DIR/project/claude-guidelines/project-management" "project-management"
fi

# 스크립트 검증
echo ""
echo "======================================================"
info "스크립트 검증"
echo "======================================================"
echo ""

check_file "$BACKUP_DIR/scripts/install.sh" "install.sh"
check_executable "$BACKUP_DIR/scripts/install.sh" "install.sh 실행 권한"

check_file "$BACKUP_DIR/scripts/backup.sh" "backup.sh"
check_executable "$BACKUP_DIR/scripts/backup.sh" "backup.sh 실행 권한"

check_file "$BACKUP_DIR/scripts/sync.sh" "sync.sh"
check_executable "$BACKUP_DIR/scripts/sync.sh" "sync.sh 실행 권한"

# 문서 검증
echo ""
echo "======================================================"
info "문서 검증"
echo "======================================================"
echo ""

check_file "$BACKUP_DIR/README.md" "README.md"
check_file "$BACKUP_DIR/QUICKSTART.md" "QUICKSTART.md"
check_file "$BACKUP_DIR/HOOKS.md" "HOOKS.md (Hook 가이드)"

# 통계
echo ""
echo "======================================================"
info "통계 정보"
echo "======================================================"
echo ""

# 전체 파일 수
TOTAL_FILES=$(find "$BACKUP_DIR" -type f | wc -l | tr -d ' ')
info "총 파일 수: $TOTAL_FILES"

# 전체 크기
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
info "전체 크기: $TOTAL_SIZE"

# 파일 타입별 통계
MD_COUNT=$(find "$BACKUP_DIR" -name "*.md" | wc -l | tr -d ' ')
SH_COUNT=$(find "$BACKUP_DIR" -name "*.sh" | wc -l | tr -d ' ')
info "Markdown 파일: $MD_COUNT"
info "Shell 스크립트: $SH_COUNT"

# 검증 결과 요약
echo ""
echo "======================================================"
info "검증 결과 요약"
echo "======================================================"
echo ""

echo "  총 검사 항목:   $TOTAL_CHECKS"
echo "  통과:          $PASSED_CHECKS"
echo "  실패:          $FAILED_CHECKS"

SUCCESS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

echo ""
if [ $FAILED_CHECKS -eq 0 ]; then
    success "모든 검증 통과! (100%)"
    echo ""
    info "백업이 완전하고 사용 가능합니다."
    echo ""
    echo "다음 단계:"
    echo "  1. 다른 시스템에 복사"
    echo "  2. ./scripts/install.sh 실행"
    exit 0
else
    warning "일부 검증 실패 (성공률: ${SUCCESS_RATE}%)"
    echo ""
    info "누락된 파일이 있습니다. 백업을 다시 생성하세요:"
    echo "  ./scripts/backup.sh"
    exit 1
fi
