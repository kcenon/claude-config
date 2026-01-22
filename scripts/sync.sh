#!/bin/bash

# Claude Configuration Sync Tool
# ===============================
# 현재 시스템과 백업 사이의 CLAUDE.md 설정을 동기화하는 스크립트

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 스크립트 디렉토리
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BACKUP_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║         Claude Configuration Sync Tool                       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 함수 정의
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
highlight() { echo -e "${CYAN}🔸 $1${NC}"; }

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

# 파일 비교 함수
compare_files() {
    local source="$1"
    local target="$2"
    local name="$3"

    if [ ! -f "$source" ] && [ ! -f "$target" ]; then
        echo "    ⚫ $name: 양쪽 모두 없음"
        return 0
    elif [ ! -f "$source" ]; then
        echo "    🔵 $name: 백업에만 있음 (시스템에 복사 가능)"
        return 1
    elif [ ! -f "$target" ]; then
        echo "    🟡 $name: 시스템에만 있음 (백업으로 복사 가능)"
        return 2
    else
        if diff -q "$source" "$target" > /dev/null 2>&1; then
            echo "    🟢 $name: 동일함"
            return 0
        else
            echo "    🔴 $name: 다름"
            return 3
        fi
    fi
}

# 동기화 방향 선택
echo ""
info "동기화 방향을 선택하세요:"
echo "  1) 백업 → 시스템 (백업의 설정을 시스템에 적용)"
echo "  2) 시스템 → 백업 (시스템의 설정을 백업에 저장)"
echo "  3) 차이점만 확인 (변경하지 않음)"
echo ""
read -p "선택 (1-3) [기본값: 3]: " SYNC_DIRECTION
SYNC_DIRECTION=${SYNC_DIRECTION:-3}

# Enterprise 설정 비교
echo ""
read -p "Enterprise 설정도 비교하시겠습니까? (y/n) [기본값: n]: " CHECK_ENTERPRISE
CHECK_ENTERPRISE=${CHECK_ENTERPRISE:-n}

ENTERPRISE_DIFF=0
ENTERPRISE_DIR="$(get_enterprise_dir)"

if [ "$CHECK_ENTERPRISE" = "y" ]; then
    echo ""
    echo "======================================================"
    info "Enterprise 설정 비교"
    echo "======================================================"
    echo ""
    info "Enterprise 경로: $ENTERPRISE_DIR"

    compare_files "$BACKUP_DIR/enterprise/CLAUDE.md" "$ENTERPRISE_DIR/CLAUDE.md" "Enterprise CLAUDE.md"
    [ $? -ne 0 ] && ENTERPRISE_DIFF=1

    # rules 디렉토리 비교
    if [ -d "$BACKUP_DIR/enterprise/rules" ] || [ -d "$ENTERPRISE_DIR/rules" ]; then
        highlight "Enterprise rules 디렉토리 비교:"
        if [ ! -d "$BACKUP_DIR/enterprise/rules" ]; then
            echo "    🟡 rules: 시스템에만 있음 (백업으로 복사 가능)"
            ENTERPRISE_DIFF=1
        elif [ ! -d "$ENTERPRISE_DIR/rules" ]; then
            echo "    🔵 rules: 백업에만 있음 (시스템에 복사 가능)"
            ENTERPRISE_DIFF=1
        else
            diff -rq "$BACKUP_DIR/enterprise/rules" "$ENTERPRISE_DIR/rules" 2>/dev/null | head -10 || true
            [ ${PIPESTATUS[0]} -ne 0 ] && ENTERPRISE_DIFF=1
        fi
    fi
fi

# 글로벌 설정 비교
echo ""
echo "======================================================"
info "글로벌 설정 비교"
echo "======================================================"
echo ""

GLOBAL_DIFF=0

compare_files "$BACKUP_DIR/global/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "CLAUDE.md"
[ $? -ne 0 ] && GLOBAL_DIFF=1

compare_files "$BACKUP_DIR/global/conversation-language.md" "$HOME/.claude/conversation-language.md" "conversation-language.md"
[ $? -ne 0 ] && GLOBAL_DIFF=1

compare_files "$BACKUP_DIR/global/git-identity.md" "$HOME/.claude/git-identity.md" "git-identity.md"
[ $? -ne 0 ] && GLOBAL_DIFF=1

compare_files "$BACKUP_DIR/global/token-management.md" "$HOME/.claude/token-management.md" "token-management.md"
[ $? -ne 0 ] && GLOBAL_DIFF=1

# 프로젝트 설정 확인
echo ""
read -p "프로젝트 설정도 비교하시겠습니까? (y/n) [기본값: n]: " CHECK_PROJECT
CHECK_PROJECT=${CHECK_PROJECT:-n}

PROJECT_DIFF=0
if [ "$CHECK_PROJECT" = "y" ]; then
    read -p "프로젝트 디렉토리 경로: " PROJECT_DIR

    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
        echo ""
        echo "======================================================"
        info "프로젝트 설정 비교: $PROJECT_DIR"
        echo "======================================================"
        echo ""

        compare_files "$BACKUP_DIR/project/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md" "프로젝트 CLAUDE.md"
        [ $? -ne 0 ] && PROJECT_DIFF=1

        # rules 디렉토리 비교
        if [ -d "$BACKUP_DIR/project/.claude/rules" ] && [ -d "$PROJECT_DIR/.claude/rules" ]; then
            highlight "rules 디렉토리 비교:"
            diff -rq "$BACKUP_DIR/project/.claude/rules" "$PROJECT_DIR/.claude/rules" 2>/dev/null | head -10 || true
            [ ${PIPESTATUS[0]} -ne 0 ] && PROJECT_DIFF=1
        fi

        # skills 디렉토리 비교
        if [ -d "$BACKUP_DIR/project/.claude/skills" ] || [ -d "$PROJECT_DIR/.claude/skills" ]; then
            highlight "skills 디렉토리 비교:"
            if [ ! -d "$BACKUP_DIR/project/.claude/skills" ]; then
                echo "    🟡 skills: 시스템에만 있음 (백업으로 복사 가능)"
                PROJECT_DIFF=1
            elif [ ! -d "$PROJECT_DIR/.claude/skills" ]; then
                echo "    🔵 skills: 백업에만 있음 (시스템에 복사 가능)"
                PROJECT_DIFF=1
            else
                diff -rq "$BACKUP_DIR/project/.claude/skills" "$PROJECT_DIR/.claude/skills" 2>/dev/null | head -10 || true
                [ ${PIPESTATUS[0]} -ne 0 ] && PROJECT_DIFF=1
            fi
        fi
    fi
fi

# 동기화 실행
if [ "$SYNC_DIRECTION" = "3" ]; then
    echo ""
    success "비교 완료 (변경 없음)"
    exit 0
fi

if [ $GLOBAL_DIFF -eq 0 ] && [ $PROJECT_DIFF -eq 0 ] && [ $ENTERPRISE_DIFF -eq 0 ]; then
    echo ""
    success "모든 파일이 동일합니다. 동기화 불필요!"
    exit 0
fi

echo ""
echo "======================================================"
warning "동기화 확인"
echo "======================================================"

if [ "$SYNC_DIRECTION" = "1" ]; then
    echo ""
    warning "백업의 설정이 시스템에 적용됩니다!"
    echo "  • 기존 시스템 파일은 .backup_* 으로 백업됩니다"
    echo ""
    read -p "계속하시겠습니까? (y/n): " CONFIRM
else
    echo ""
    warning "시스템의 설정이 백업에 저장됩니다!"
    echo "  • 기존 백업 파일은 덮어씌워집니다"
    echo ""
    read -p "계속하시겠습니까? (y/n): " CONFIRM
fi

if [ "$CONFIRM" != "y" ]; then
    info "동기화 취소됨"
    exit 0
fi

# 실제 동기화 수행
echo ""
echo "======================================================"
info "동기화 진행 중..."
echo "======================================================"

if [ "$SYNC_DIRECTION" = "1" ]; then
    # 백업 → 시스템

    # Enterprise 동기화
    if [ "$CHECK_ENTERPRISE" = "y" ]; then
        if [ -f "$BACKUP_DIR/enterprise/CLAUDE.md" ]; then
            if [ "$(uname -s)" = "Darwin" ] || [ "$(uname -s)" = "Linux" ]; then
                if [ ! -w "$(dirname "$ENTERPRISE_DIR")" ]; then
                    sudo mkdir -p "$ENTERPRISE_DIR/rules"
                    sudo cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$ENTERPRISE_DIR/"
                    [ -d "$BACKUP_DIR/enterprise/rules" ] && sudo cp -r "$BACKUP_DIR/enterprise/rules"/* "$ENTERPRISE_DIR/rules/" 2>/dev/null || true
                else
                    mkdir -p "$ENTERPRISE_DIR/rules"
                    cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$ENTERPRISE_DIR/"
                    [ -d "$BACKUP_DIR/enterprise/rules" ] && cp -r "$BACKUP_DIR/enterprise/rules"/* "$ENTERPRISE_DIR/rules/" 2>/dev/null || true
                fi
            else
                mkdir -p "$ENTERPRISE_DIR/rules"
                cp "$BACKUP_DIR/enterprise/CLAUDE.md" "$ENTERPRISE_DIR/"
                [ -d "$BACKUP_DIR/enterprise/rules" ] && cp -r "$BACKUP_DIR/enterprise/rules"/* "$ENTERPRISE_DIR/rules/" 2>/dev/null || true
            fi
            success "Enterprise CLAUDE.md → 시스템"
        fi
    fi

    [ -f "$BACKUP_DIR/global/CLAUDE.md" ] && {
        [ -f "$HOME/.claude/CLAUDE.md" ] && cp "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$BACKUP_DIR/global/CLAUDE.md" "$HOME/.claude/"
        success "CLAUDE.md → 시스템"
    }

    [ -f "$BACKUP_DIR/global/conversation-language.md" ] && {
        cp "$BACKUP_DIR/global/conversation-language.md" "$HOME/.claude/"
        success "conversation-language.md → 시스템"
    }

    [ -f "$BACKUP_DIR/global/git-identity.md" ] && {
        cp "$BACKUP_DIR/global/git-identity.md" "$HOME/.claude/"
        success "git-identity.md → 시스템"
    }

    [ -f "$BACKUP_DIR/global/token-management.md" ] && {
        cp "$BACKUP_DIR/global/token-management.md" "$HOME/.claude/"
        success "token-management.md → 시스템"
    }

    if [ "$CHECK_PROJECT" = "y" ] && [ -n "$PROJECT_DIR" ]; then
        [ -f "$BACKUP_DIR/project/CLAUDE.md" ] && {
            cp "$BACKUP_DIR/project/CLAUDE.md" "$PROJECT_DIR/"
            success "프로젝트 CLAUDE.md → 시스템"
        }

        [ -d "$BACKUP_DIR/project/.claude/rules" ] && {
            mkdir -p "$PROJECT_DIR/.claude/rules"
            cp -r "$BACKUP_DIR/project/.claude/rules"/* "$PROJECT_DIR/.claude/rules/"
            success "rules → 시스템"
        }

        [ -d "$BACKUP_DIR/project/.claude/skills" ] && {
            mkdir -p "$PROJECT_DIR/.claude/skills"
            cp -r "$BACKUP_DIR/project/.claude/skills"/* "$PROJECT_DIR/.claude/skills/"
            success "skills → 시스템"
        }
    fi

else
    # 시스템 → 백업

    # Enterprise 동기화
    if [ "$CHECK_ENTERPRISE" = "y" ]; then
        if [ -f "$ENTERPRISE_DIR/CLAUDE.md" ]; then
            mkdir -p "$BACKUP_DIR/enterprise/rules"
            cp "$ENTERPRISE_DIR/CLAUDE.md" "$BACKUP_DIR/enterprise/"
            [ -d "$ENTERPRISE_DIR/rules" ] && cp -r "$ENTERPRISE_DIR/rules"/* "$BACKUP_DIR/enterprise/rules/" 2>/dev/null || true
            success "Enterprise CLAUDE.md → 백업"
        fi
    fi

    [ -f "$HOME/.claude/CLAUDE.md" ] && {
        cp "$HOME/.claude/CLAUDE.md" "$BACKUP_DIR/global/"
        success "CLAUDE.md → 백업"
    }

    [ -f "$HOME/.claude/conversation-language.md" ] && {
        cp "$HOME/.claude/conversation-language.md" "$BACKUP_DIR/global/"
        success "conversation-language.md → 백업"
    }

    [ -f "$HOME/.claude/git-identity.md" ] && {
        cp "$HOME/.claude/git-identity.md" "$BACKUP_DIR/global/"
        success "git-identity.md → 백업"
    }

    [ -f "$HOME/.claude/token-management.md" ] && {
        cp "$HOME/.claude/token-management.md" "$BACKUP_DIR/global/"
        success "token-management.md → 백업"
    }

    if [ "$CHECK_PROJECT" = "y" ] && [ -n "$PROJECT_DIR" ]; then
        [ -f "$PROJECT_DIR/CLAUDE.md" ] && {
            cp "$PROJECT_DIR/CLAUDE.md" "$BACKUP_DIR/project/"
            success "프로젝트 CLAUDE.md → 백업"
        }

        [ -d "$PROJECT_DIR/.claude/rules" ] && {
            mkdir -p "$BACKUP_DIR/project/.claude/rules"
            cp -r "$PROJECT_DIR/.claude/rules"/* "$BACKUP_DIR/project/.claude/rules/"
            success "rules → 백업"
        }

        [ -d "$PROJECT_DIR/.claude/skills" ] && {
            mkdir -p "$BACKUP_DIR/project/.claude/skills"
            cp -r "$PROJECT_DIR/.claude/skills"/* "$BACKUP_DIR/project/.claude/skills/"
            success "skills → 백업"
        }
    fi
fi

echo ""
echo "======================================================"
success "동기화 완료!"
echo "======================================================"
echo ""

if [ "$SYNC_DIRECTION" = "1" ]; then
    info "다음 단계:"
    echo "  1. Git identity 확인: vi ~/.claude/git-identity.md"
    echo "  2. Claude Code 재시작"
else
    info "다음 단계:"
    echo "  1. 백업을 다른 시스템에 복사"
    echo "  2. 새 시스템에서 ./scripts/install.sh 실행"
fi

echo ""
success "동기화가 완료되었습니다! 🎉"
