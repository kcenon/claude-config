#!/bin/bash

# Git Hooks Installation Script
# =============================
# Git hooks를 설치하는 스크립트
#
# Usage:
#   hooks/install-hooks.sh              # interactive — prompts on conflict
#   hooks/install-hooks.sh --force      # non-interactive — overwrite all
#   hooks/install-hooks.sh -y           # alias for --force
#
# Merge contract (when option 2 "병합" is chosen):
#   The new claude-config validators are PREPENDED — they run before the
#   existing hook content. If a validator exits non-zero, git rejects the
#   commit/push and the existing hook never runs. Pre-#619 builds appended
#   after, which let an existing 'exit 0' silently bypass the new validators.
#   If you previously merged with the old behavior, choose option 1
#   (overwrite) on the next install to clean up the duplicated block.
#
# The non-interactive mode is intended for CI, automation sessions, and
# scripted provisioning where no TTY is available to answer the prompt.
#
# Environment overrides (test/automation use):
#   INSTALL_HOOKS_TARGET_DIR  override the install destination (default
#                             $REPO_ROOT/.git/hooks). Used by
#                             tests/hooks/test-merge-installation.sh.

set -euo pipefail

FORCE_MODE=0
for arg in "$@"; do
    case "$arg" in
        --force|-y|--yes)
            FORCE_MODE=1
            ;;
        -h|--help)
            sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "install-hooks.sh: unknown argument '$arg'" >&2
            echo "Run with --help for usage." >&2
            exit 2
            ;;
    esac
done

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
GIT_HOOKS_DIR="${INSTALL_HOOKS_TARGET_DIR:-$REPO_ROOT/.git/hooks}"

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
        local choice
        if [ "$FORCE_MODE" = "1" ]; then
            choice=1
            info "  --force: 덮어쓰기 선택 (비대화)"
        else
            echo "  1) 덮어쓰기 (교체)"
            echo "  2) 병합 (claude-config validators run BEFORE existing hook)"
            echo "  3) 건너뛰기"
            read -p "  선택 (1-3) [기본값: 3]: " choice
            choice=${choice:-3}
        fi

        case "$choice" in
            1)
                cp "$source_file" "$target_file"
                chmod +x "$target_file"
                success "$hook_name hook 덮어쓰기 완료!"
                ;;
            2)
                # PREPEND new validators before existing hook content (#619).
                # Old behavior appended after, which let `exit 0` in the
                # existing hook silently bypass the new validators.
                local existing_body
                existing_body=$(tail -n +2 "$target_file")
                {
                    head -n 1 "$source_file"
                    echo ""
                    echo "# --- claude-config $hook_name (prepended $(date +%Y-%m-%d)) ---"
                    tail -n +2 "$source_file"
                    echo ""
                    echo "# --- existing $hook_name content (preserved) ---"
                    echo "$existing_body"
                } > "$target_file"
                chmod +x "$target_file"
                success "$hook_name hook 병합 완료 (claude-config validators run first)"
                info "  merge order: 1) claude-config validators  2) existing hook content"
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

# pre-push hook 설치
echo ""
install_hook "pre-push"

# 공유 검증 라이브러리 설치
info "검증 라이브러리 설치 중..."
mkdir -p "$GIT_HOOKS_DIR/lib"
cp "$SCRIPT_DIR/lib/validate-commit-message.sh" "$GIT_HOOKS_DIR/lib/"
chmod +x "$GIT_HOOKS_DIR/lib/validate-commit-message.sh"
# Traceability cascade validator (issue #590). Sourced by the pre-push hook
# above; opt-in (no-op when docs/.index/graph.yaml is absent).
if [ -f "$SCRIPT_DIR/lib/validate-traceability.sh" ]; then
    cp "$SCRIPT_DIR/lib/validate-traceability.sh" "$GIT_HOOKS_DIR/lib/"
    chmod +x "$GIT_HOOKS_DIR/lib/validate-traceability.sh"
fi
success "검증 라이브러리 설치 완료!"

echo ""
info "설치된 hooks:"
ls -la "$GIT_HOOKS_DIR" | grep -v ".sample"

echo ""
success "Git hooks 설치가 완료되었습니다."
info "커밋 시 SKILL.md 검증과 커밋 메시지 검증이 자동으로 실행됩니다."
info "push 시 보호 브랜치(main, develop) 직접 push가 차단됩니다."
