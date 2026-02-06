#!/bin/bash
#
# gh_pr_create.sh
#
# Create a GitHub Pull Request with title, body, labels, and reviewers
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#   jq (https://jqlang.github.io/jq/)
#
# Usage:
#   ./gh_pr_create.sh -t "PR title"                     # Minimal (auto-detect repo)
#   ./gh_pr_create.sh -r owner/repo -t "Title" -b "Body"
#   ./gh_pr_create.sh -t "Title" -B main -H feature/x -l "enhancement"
#   ./gh_pr_create.sh -t "Title" --json                  # JSON output
#   ./gh_pr_create.sh -t "Title" --quiet                 # Minimal output
#   ./gh_pr_create.sh -h                                  # Show help
#

set -euo pipefail

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
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' DIM='' NC=''
fi

# =============================================================================
# Helper functions
# =============================================================================
print_success() { [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return; echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}" >&2; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}" >&2; }
print_info()    { [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return; echo -e "${CYAN}ℹ $1${NC}"; }

print_header() {
    [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║              GitHub Pull Request Creator                            ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_help() {
    print_header
    echo -e "${CYAN}Usage:${NC}"
    echo "  $0 [OPTIONS]"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo "  -r, --repo REPO          Target repo (owner/repo). Auto-detects if omitted."
    echo "  -t, --title TITLE        PR title (required)"
    echo "  -b, --body BODY          PR body text"
    echo "  -B, --base BRANCH        Base branch (default: main)"
    echo "  -H, --head BRANCH        Head branch (default: current branch)"
    echo "  -l, --labels LABELS      Comma-separated labels (e.g. \"enhancement,review\")"
    echo "  -v, --reviewers USERS    Comma-separated reviewers (e.g. \"user1,user2\")"
    echo "  -d, --draft              Create as draft PR"
    echo "  -e, --editor             Open editor for body input"
    echo "  --json                   Output result as JSON (for programmatic use)"
    echo "  --quiet                  Suppress decorative output"
    echo "  -h, --help               Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  $0 -t \"Add login feature\" -b \"Implements OAuth2 login\" -l \"enhancement\""
    echo "  $0 -r kcenon/thread_system -t \"Fix race condition\" -B main -d"
    echo "  $0 -t \"Refactor\" -v \"reviewer1\" -e       # Opens editor for body"
    echo "  $0 -t \"Fix\" --json                        # {\"url\":\"...\",\"number\":42}"
    echo ""
}

# =============================================================================
# Validation functions
# =============================================================================
check_prerequisites() {
    if ! command -v gh &>/dev/null; then
        print_error "gh CLI is not installed. Install it from https://cli.github.com/"
        exit 1
    fi

    if ! gh auth status &>/dev/null; then
        print_error "gh CLI is not authenticated. Run: gh auth login"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        print_error "jq is not installed. Install it from https://jqlang.github.io/jq/"
        exit 1
    fi
}

detect_repo() {
    local repo
    repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
        print_error "Cannot detect repository. Use -r to specify one."
        exit 1
    }
    echo "$repo"
}

detect_current_branch() {
    local branch
    branch=$(git branch --show-current 2>/dev/null) || {
        print_error "Cannot detect current branch. Use -H to specify one."
        exit 1
    }
    echo "$branch"
}

# =============================================================================
# Main function
# =============================================================================
main() {
    local repo=""
    local title=""
    local body=""
    local base=""
    local head=""
    local labels=""
    local reviewers=""
    local draft=false
    local use_editor=false

    # Argument parsing
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--repo)      repo="$2";      shift 2 ;;
            -t|--title)     title="$2";     shift 2 ;;
            -b|--body)      body="$2";      shift 2 ;;
            -B|--base)      base="$2";      shift 2 ;;
            -H|--head)      head="$2";      shift 2 ;;
            -l|--labels)    labels="$2";    shift 2 ;;
            -v|--reviewers) reviewers="$2"; shift 2 ;;
            -d|--draft)     draft=true;      shift   ;;
            -e|--editor)    use_editor=true; shift   ;;
            --json)         OUTPUT_JSON=true; shift  ;;
            --quiet)        OUTPUT_QUIET=true; shift ;;
            -h|--help)      show_help; exit 0        ;;
            *)
                print_error "Unknown option: $1"
                echo "Run '$0 --help' for usage information." >&2
                exit 1
                ;;
        esac
    done

    # Validate
    check_prerequisites

    if [[ -z "$title" ]]; then
        print_error "Title is required. Use -t to provide one."
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    if [[ -z "$repo" ]]; then
        repo=$(detect_repo)
    fi

    if [[ -z "$head" ]]; then
        head=$(detect_current_branch)
    fi

    print_header
    print_info "Repository: $repo"
    print_info "Title:      $title"
    print_info "Head:       $head"
    [[ -n "$base" ]] && print_info "Base:       $base"
    [[ "$draft" == true ]] && print_info "Draft:      yes"

    # Build gh command
    local -a cmd=(gh pr create --repo "$repo" --title "$title" --head "$head")

    if [[ -n "$base" ]]; then
        cmd+=(--base "$base")
    fi

    if [[ "$use_editor" == true ]]; then
        cmd+=(--editor)
    elif [[ -n "$body" ]]; then
        cmd+=(--body "$body")
        print_info "Body:       $(echo "$body" | head -c 80)..."
    else
        cmd+=(--body "")
    fi

    if [[ -n "$labels" ]]; then
        cmd+=(--label "$labels")
        print_info "Labels:     $labels"
    fi

    if [[ -n "$reviewers" ]]; then
        cmd+=(--reviewer "$reviewers")
        print_info "Reviewers:  $reviewers"
    fi

    if [[ "$draft" == true ]]; then
        cmd+=(--draft)
    fi

    [[ "$OUTPUT_JSON" != true && "$OUTPUT_QUIET" != true ]] && echo ""

    # Execute
    local result
    result=$("${cmd[@]}" 2>&1) || {
        print_error "Failed to create PR: $result"
        exit 1
    }

    # Output
    if [[ "$OUTPUT_JSON" == true ]]; then
        local pr_number
        pr_number=$(echo "$result" | grep -oE '[0-9]+$')
        printf '{"url":"%s","number":%s}\n' "$result" "$pr_number"
    elif [[ "$OUTPUT_QUIET" == true ]]; then
        echo "$result"
    else
        echo -e "${GREEN}"
        echo "╔══════════════════════════════════════════════════════════════════════╗"
        echo "║                      PR Created Successfully                       ║"
        echo "╚══════════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "  ${BOLD}URL:${NC} $result"
        echo ""
    fi
}

main "$@"
