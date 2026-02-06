#!/bin/bash
#
# cleanup_branches.sh
#
# 지정된 경로(또는 현재 디렉토리)의 모든 Git 저장소에서
# main 브랜치를 제외한 모든 로컬 브랜치를 삭제하고
# main 브랜치를 최신으로 pull하는 스크립트
#
# 사용법:
#   ./cleanup_branches.sh              # 현재 디렉토리의 모든 Git 저장소 대상
#   ./cleanup_branches.sh <경로>       # 지정된 경로의 모든 Git 저장소 대상
#   ./cleanup_branches.sh --json       # JSON 결과 출력
#   ./cleanup_branches.sh --quiet      # 최소 출력
#   ./cleanup_branches.sh -h           # 도움말 표시
#

set -e

# =============================================================================
# Output mode flags
# =============================================================================
OUTPUT_JSON=false
OUTPUT_QUIET=false

# =============================================================================
# TTY detection and conditional colors
# =============================================================================
if [[ -t 1 ]]; then IS_TTY=true; else IS_TTY=false; fi

if [[ "$IS_TTY" == true ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

# 현재 작업 디렉토리
WORKING_DIR="$(pwd)"

# 결과 저장용 배열
declare -a SUCCESS_PROJECTS
declare -a FAILED_PROJECTS
declare -a SKIPPED_PROJECTS

# =============================================================================
# Helper functions
# =============================================================================
print_error()   { echo -e "${RED}✗ $1${NC}" >&2; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}" >&2; }
print_info()    { [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return; echo -e "${CYAN}ℹ $1${NC}"; }
print_detail()  { [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return; echo -e "$1"; }

# 도움말 출력
show_help() {
    if [[ "$OUTPUT_JSON" != true && "$OUTPUT_QUIET" != true ]]; then
        echo -e "${GREEN}"
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║       Git 브랜치 정리 및 main 브랜치 업데이트 스크립트        ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
    fi
    echo ""
    echo -e "${CYAN}사용법:${NC}"
    echo "  $0                  현재 디렉토리의 모든 Git 저장소에 대해 작업"
    echo "  $0 <경로>           지정된 경로의 모든 Git 저장소에 대해 작업"
    echo "  $0 --json           JSON 형식으로 결과 출력"
    echo "  $0 --quiet          장식적 출력 억제"
    echo "  $0 -h, --help       이 도움말 표시"
    echo ""
    echo -e "${CYAN}예시:${NC}"
    echo "  $0                  # 현재 디렉토리의 모든 Git 저장소"
    echo "  $0 .                # 현재 디렉토리 (위와 동일)"
    echo "  $0 ../projects      # ../projects 경로의 모든 Git 저장소"
    echo "  $0 ~/Sources        # ~/Sources 경로의 모든 Git 저장소"
    echo "  $0 --json           # {\"success\":[...],\"failed\":[...],\"skipped\":[...]}"
    echo ""
    echo -e "${CYAN}동작:${NC}"
    echo "  1. 지정된 경로에서 Git 저장소 자동 탐색"
    echo "  2. 각 저장소로 이동"
    echo "  3. 커밋되지 않은 변경사항 자동 stash"
    echo "  4. main 브랜치로 체크아웃"
    echo "  5. main을 제외한 모든 로컬 브랜치 삭제"
    echo "  6. git pull origin main 으로 최신화"
    echo ""
}

# 프로젝트 브랜치 정리 함수
cleanup_project() {
    local project_path="$1"
    local project_name
    project_name=$(basename "$project_path")

    print_detail "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_detail "${BLUE}📁 프로젝트: ${project_name}${NC}"
    print_detail "${BLUE}   경로: ${project_path}${NC}"
    print_detail "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # 디렉토리 존재 확인
    if [[ ! -d "$project_path" ]]; then
        print_warning "디렉토리가 존재하지 않습니다: ${project_path}"
        SKIPPED_PROJECTS+=("$project_name (디렉토리 없음)")
        return 1
    fi

    # Git 저장소인지 확인
    if [[ ! -d "${project_path}/.git" ]]; then
        print_warning "Git 저장소가 아닙니다: ${project_path}"
        SKIPPED_PROJECTS+=("$project_name (Git 저장소 아님)")
        return 1
    fi

    cd "$project_path"

    # 현재 브랜치 확인
    local current_branch
    current_branch=$(git branch --show-current)
    print_detail "   현재 브랜치: ${current_branch}"

    # 변경사항 확인
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        print_warning "커밋되지 않은 변경사항이 있습니다. stash 처리합니다. ($project_name)"
        git stash push -m "Auto-stash by cleanup_branches.sh at $(date '+%Y-%m-%d %H:%M:%S')"
    fi

    # main 또는 master 브랜치 확인
    local target_branch="main"
    if git show-ref --verify --quiet refs/heads/main || git show-ref --verify --quiet refs/remotes/origin/main; then
        target_branch="main"
    elif git show-ref --verify --quiet refs/heads/master || git show-ref --verify --quiet refs/remotes/origin/master; then
        target_branch="master"
    else
        print_error "main 또는 master 브랜치가 존재하지 않습니다. ($project_name)"
        FAILED_PROJECTS+=("$project_name (main/master 없음)")
        return 1
    fi

    # 대상 브랜치로 체크아웃
    print_detail "   ${GREEN}→ ${target_branch} 브랜치로 체크아웃${NC}"
    if ! git checkout "$target_branch" 2>/dev/null; then
        print_error "${target_branch} 브랜치 체크아웃 실패 ($project_name)"
        FAILED_PROJECTS+=("$project_name (${target_branch} 체크아웃 실패)")
        return 1
    fi

    # 대상 브랜치를 제외한 모든 로컬 브랜치 목록 가져오기
    local branches
    branches=$(git branch | grep -v '^\*' | grep -v "^[[:space:]]*${target_branch}$" | sed 's/^[ \t]*//' || true)

    if [[ -n "$branches" ]]; then
        print_detail "   ${YELLOW}→ 삭제할 브랜치:${NC}"
        echo "$branches" | while read -r branch; do
            print_detail "      - ${branch}"
        done

        # 브랜치 삭제
        echo "$branches" | while read -r branch; do
            if [[ -n "$branch" ]]; then
                print_detail "   ${RED}✗ 삭제: ${branch}${NC}"
                git branch -D "$branch" 2>/dev/null || true
            fi
        done
    else
        print_detail "   ${GREEN}✓ 삭제할 브랜치가 없습니다.${NC}"
    fi

    # 대상 브랜치 pull
    print_detail "   ${GREEN}→ ${target_branch} 브랜치 pull${NC}"
    if git pull origin "$target_branch" 2>&1; then
        print_detail "   ${GREEN}✓ pull 완료${NC}"
        SUCCESS_PROJECTS+=("$project_name")
    else
        print_warning "pull 실패 (원격 저장소 연결 문제일 수 있음) ($project_name)"
        FAILED_PROJECTS+=("$project_name (pull 실패)")
        return 1
    fi

    return 0
}

# 지정된 경로에서 Git 저장소 찾기
find_git_repos() {
    local search_path="$1"
    local repos=()

    # 첫 번째 레벨 디렉토리만 검색 (깊은 탐색 방지)
    for dir in "$search_path"/*/; do
        if [[ -d "${dir}.git" ]]; then
            # 절대 경로로 변환
            repos+=("$(cd "$dir" && pwd)")
        fi
    done

    printf '%s\n' "${repos[@]}"
}

# =============================================================================
# JSON output function
# =============================================================================
output_summary_json() {
    local success_json="[]" failed_json="[]" skipped_json="[]"

    if [[ ${#SUCCESS_PROJECTS[@]} -gt 0 ]]; then
        success_json=$(printf '%s\n' "${SUCCESS_PROJECTS[@]}" | jq -R . | jq -s .)
    fi
    if [[ ${#FAILED_PROJECTS[@]} -gt 0 ]]; then
        failed_json=$(printf '%s\n' "${FAILED_PROJECTS[@]}" | jq -R . | jq -s .)
    fi
    if [[ ${#SKIPPED_PROJECTS[@]} -gt 0 ]]; then
        skipped_json=$(printf '%s\n' "${SKIPPED_PROJECTS[@]}" | jq -R . | jq -s .)
    fi

    jq -n \
        --argjson success "$success_json" \
        --argjson failed "$failed_json" \
        --argjson skipped "$skipped_json" \
        '{
            success: $success,
            failed: $failed,
            skipped: $skipped,
            counts: {
                success: ($success | length),
                failed: ($failed | length),
                skipped: ($skipped | length)
            }
        }'
}

# 메인 실행
main() {
    local target_path=""

    # 인자 처리 - 먼저 플래그를 파싱
    local positional_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --quiet)
                OUTPUT_QUIET=true
                shift
                ;;
            *)
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    # JSON mode requires jq
    if [[ "$OUTPUT_JSON" == true ]]; then
        if ! command -v jq &>/dev/null; then
            print_error "jq is required for --json output. Install it from https://jqlang.github.io/jq/"
            exit 1
        fi
    fi

    # 위치 인자로 경로 결정
    case "${positional_args[0]:-}" in
        "")
            target_path="$WORKING_DIR"
            ;;
        *)
            if [[ "${positional_args[0]}" = /* ]]; then
                target_path="${positional_args[0]}"
            else
                target_path="$(cd "$WORKING_DIR/${positional_args[0]}" 2>/dev/null && pwd)"
                if [[ -z "$target_path" ]]; then
                    print_error "경로를 찾을 수 없습니다: ${positional_args[0]}"
                    exit 1
                fi
            fi
            ;;
    esac

    if [[ "$OUTPUT_JSON" != true && "$OUTPUT_QUIET" != true ]]; then
        echo -e "${GREEN}"
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║       Git 브랜치 정리 및 main 브랜치 업데이트 스크립트        ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
    fi

    print_detail "대상 경로: ${CYAN}${target_path}${NC}"

    # 지정된 경로에서 Git 저장소 찾기
    print_detail "Git 저장소 검색 중..."

    local repos
    repos=$(find_git_repos "$target_path")

    if [[ -z "$repos" ]]; then
        print_warning "지정된 경로에서 Git 저장소를 찾을 수 없습니다."
        if [[ "$OUTPUT_JSON" == true ]]; then
            output_summary_json
        fi
        exit 1
    fi

    local repo_count
    repo_count=$(echo "$repos" | wc -l | tr -d ' ')
    print_detail "발견된 Git 저장소: ${GREEN}${repo_count}개${NC}"
    print_detail ""

    # 각 저장소 처리
    while IFS= read -r repo_path; do
        if [[ -n "$repo_path" ]]; then
            cleanup_project "$repo_path" || true
        fi
    done <<< "$repos"

    # Output
    if [[ "$OUTPUT_JSON" == true ]]; then
        output_summary_json
    elif [[ "$OUTPUT_QUIET" == true ]]; then
        echo "success: ${#SUCCESS_PROJECTS[@]}, failed: ${#FAILED_PROJECTS[@]}, skipped: ${#SKIPPED_PROJECTS[@]}"
    else
        # 결과 요약
        echo -e "\n${GREEN}"
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║                         결과 요약                             ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "${GREEN}✅ 성공: ${#SUCCESS_PROJECTS[@]}개${NC}"
        for p in "${SUCCESS_PROJECTS[@]}"; do
            echo -e "   - $p"
        done

        if [[ ${#FAILED_PROJECTS[@]} -gt 0 ]]; then
            echo -e "\n${RED}❌ 실패: ${#FAILED_PROJECTS[@]}개${NC}"
            for p in "${FAILED_PROJECTS[@]}"; do
                echo -e "   - $p"
            done
        fi

        if [[ ${#SKIPPED_PROJECTS[@]} -gt 0 ]]; then
            echo -e "\n${YELLOW}⚠️  건너뜀: ${#SKIPPED_PROJECTS[@]}개${NC}"
            for p in "${SKIPPED_PROJECTS[@]}"; do
                echo -e "   - $p"
            done
        fi

        echo -e "\n${BLUE}작업 완료!${NC}\n"
    fi
}

# 스크립트 실행
main "$@"
