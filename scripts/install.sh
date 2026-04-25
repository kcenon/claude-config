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

# 함수: 정책 phrase 반환 (install-time substitution용, issue #411)
# CLAUDE_CONTENT_LANGUAGE 값에 매핑되는 짧은 phrase를 반환합니다.
get_policy_phrase() {
    case "${CONTENT_LANGUAGE:-english}" in
        english)             echo "English" ;;
        korean_plus_english) echo "English or Korean" ;;
        exclusive_bilingual) echo "English or Korean (document-exclusive)" ;;
        any)                 echo "any language" ;;
        *)                   echo "English" ;;
    esac
}

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

# 의존성 확인
check_dependencies

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

# Content language policy selection (CLAUDE_CONTENT_LANGUAGE)
# Only the Global / Enterprise install paths touch settings.json.
# Default "english" matches the dispatcher default and leaves settings.json untouched.
echo ""
info "Select content-language policy (commit / PR / issue validation scope):"
echo "  1) English (Default, identical to current behavior)"
echo "  2) Korean + English (Allows Hangul, inline mixing permitted)"
echo "  3) Exclusive bilingual (English or Korean per document, no inline mixing)"
echo "  4) Any (No language validation — AI attribution block maintained)"
echo ""
read -p "Selection (1-4) [default: 1]: " LANG_TYPE
LANG_TYPE=${LANG_TYPE:-1}

case "$LANG_TYPE" in
    1) CONTENT_LANGUAGE="english" ;;
    2) CONTENT_LANGUAGE="korean_plus_english" ;;
    3) CONTENT_LANGUAGE="exclusive_bilingual" ;;
    4) CONTENT_LANGUAGE="any" ;;
    *)
        warning "Unknown selection: $LANG_TYPE. Falling back to english."
        CONTENT_LANGUAGE="english"
        ;;
esac

# Agent Conversation Language selection
echo ""
info "Select Agent Conversation Language:"
echo "  1) English"
echo "  2) Korean"
echo ""
read -p "Selection (1-2) [default: 2]: " AGENT_LANG_TYPE
AGENT_LANG_TYPE=${AGENT_LANG_TYPE:-2}

case "$AGENT_LANG_TYPE" in
    1) AGENT_LANGUAGE="english" ;;
    2) AGENT_LANGUAGE="korean" ;;
    *)
        warning "Unknown selection: $AGENT_LANG_TYPE. Falling back to korean."
        AGENT_LANGUAGE="korean"
        ;;
esac

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
    if [ -f "$BACKUP_DIR/global/conversation-language.md.tmpl" ]; then
        if [ "$AGENT_LANGUAGE" = "english" ]; then
            DISPLAY_LANG="English"
        else
            DISPLAY_LANG="Korean"
        fi
        
        if guarded_template_copy "$BACKUP_DIR/global/conversation-language.md.tmpl" "$HOME/.claude/conversation-language.md" "conversation-language.md" "$DISPLAY_LANG"; then
            chmod 644 "$HOME/.claude/conversation-language.md"
            success "conversation-language.md 설치됨 (언어: $DISPLAY_LANG)"
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

    # skills 디렉토리 설치 (global skills: harness, pr-work, issue-work, etc.)
    if [ -d "$BACKUP_DIR/global/skills" ]; then
        mkdir -p "$HOME/.claude/skills"
        for skill_dir in "$BACKUP_DIR/global/skills"/*/; do
            if [ -d "$skill_dir" ]; then
                cp -r "$skill_dir" "$HOME/.claude/skills/"
            fi
        done
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
