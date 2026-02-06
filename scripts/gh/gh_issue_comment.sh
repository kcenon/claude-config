#!/bin/bash
#
# gh_issue_comment.sh
#
# Add a comment to a GitHub Issue
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#
# Usage:
#   ./gh_issue_comment.sh -n 42 -b "Comment text"       # Auto-detect repo
#   ./gh_issue_comment.sh -r owner/repo -n 42 -b "Text"
#   ./gh_issue_comment.sh -n 42 -e                       # Open editor
#   ./gh_issue_comment.sh -n 42 -b "Text" --json         # JSON output
#   ./gh_issue_comment.sh -n 42 -b "Text" --quiet        # Minimal output
#   ./gh_issue_comment.sh -h                              # Show help
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
    echo "║              GitHub Issue Comment                                   ║"
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
    echo "  -n, --number NUMBER      Issue number (required)"
    echo "  -b, --body BODY          Comment body text (required unless -e is used)"
    echo "  -e, --editor             Open editor for comment input"
    echo "  --json                   Output result as JSON (for programmatic use)"
    echo "  --quiet                  Suppress decorative output"
    echo "  -h, --help               Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  $0 -n 42 -b \"Fixed in commit abc123\""
    echo "  $0 -r kcenon/thread_system -n 10 -b \"LGTM\""
    echo "  $0 -n 42 -e                               # Opens editor"
    echo "  $0 -n 42 -b \"LGTM\" --json                 # {\"url\":\"...\"}"
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
}

detect_repo() {
    local repo
    repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
        print_error "Cannot detect repository. Use -r to specify one."
        exit 1
    }
    echo "$repo"
}

# =============================================================================
# Main function
# =============================================================================
main() {
    local repo=""
    local number=""
    local body=""
    local use_editor=false

    # Argument parsing
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--repo)    repo="$2";   shift 2 ;;
            -n|--number)  number="$2"; shift 2 ;;
            -b|--body)    body="$2";   shift 2 ;;
            -e|--editor)  use_editor=true; shift ;;
            --json)       OUTPUT_JSON=true; shift ;;
            --quiet)      OUTPUT_QUIET=true; shift ;;
            -h|--help)    show_help; exit 0 ;;
            *)
                print_error "Unknown option: $1"
                echo "Run '$0 --help' for usage information." >&2
                exit 1
                ;;
        esac
    done

    # Validate
    check_prerequisites

    if [[ -z "$number" ]]; then
        print_error "Issue number is required. Use -n to provide one."
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    if [[ -z "$body" && "$use_editor" == false ]]; then
        print_error "Comment body is required. Use -b or -e to provide one."
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    if [[ -z "$repo" ]]; then
        repo=$(detect_repo)
    fi

    print_header
    print_info "Repository: $repo"
    print_info "Issue:      #$number"

    # Build gh command
    local -a cmd=(gh issue comment "$number" --repo "$repo")

    if [[ "$use_editor" == true ]]; then
        cmd+=(--editor)
    else
        cmd+=(--body "$body")
        local preview
        preview=$(echo "$body" | head -c 80)
        print_info "Comment:    ${preview}..."
    fi

    [[ "$OUTPUT_JSON" != true && "$OUTPUT_QUIET" != true ]] && echo ""

    # Execute
    local result
    result=$("${cmd[@]}" 2>&1) || {
        print_error "Failed to add comment: $result"
        exit 1
    }

    # Output
    if [[ "$OUTPUT_JSON" == true ]]; then
        printf '{"url":"%s"}\n' "$result"
    elif [[ "$OUTPUT_QUIET" == true ]]; then
        echo "$result"
    else
        echo -e "${GREEN}"
        echo "╔══════════════════════════════════════════════════════════════════════╗"
        echo "║                   Comment Added Successfully                       ║"
        echo "╚══════════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "  ${BOLD}URL:${NC} $result"
        echo ""
    fi
}

main "$@"
