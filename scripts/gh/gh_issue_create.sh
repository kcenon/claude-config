#!/bin/bash
#
# gh_issue_create.sh
#
# Create a GitHub Issue with title, body, labels, and assignees
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#   jq (https://jqlang.github.io/jq/)
#
# Usage:
#   ./gh_issue_create.sh -t "Bug title"                  # Minimal (auto-detect repo)
#   ./gh_issue_create.sh -r owner/repo -t "Title" -b "Body"
#   ./gh_issue_create.sh -t "Title" -l "bug,urgent" -a "user1"
#   ./gh_issue_create.sh -t "Title" --json               # JSON output
#   ./gh_issue_create.sh -t "Title" --quiet              # Minimal output
#   ./gh_issue_create.sh -h                               # Show help
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
    echo "║              GitHub Issue Creator                                   ║"
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
    echo "  -t, --title TITLE        Issue title (required)"
    echo "  -b, --body BODY          Issue body text"
    echo "  -l, --labels LABELS      Comma-separated labels (e.g. \"bug,enhancement\")"
    echo "  -a, --assignees USERS    Comma-separated assignees (e.g. \"user1,user2\")"
    echo "  -m, --milestone NAME     Milestone name"
    echo "  -e, --editor             Open editor for body input"
    echo "  --json                   Output result as JSON (for programmatic use)"
    echo "  --quiet                  Suppress decorative output"
    echo "  -h, --help               Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  $0 -t \"Fix login bug\" -b \"Login fails on timeout\" -l \"bug\""
    echo "  $0 -r kcenon/thread_system -t \"Add feature\" -a \"kcenon\""
    echo "  $0 -t \"Design review\" -e              # Opens editor for body"
    echo "  $0 -t \"Bug\" --json                     # {\"url\":\"...\",\"number\":42}"
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

# =============================================================================
# Main function
# =============================================================================
main() {
    local repo=""
    local title=""
    local body=""
    local labels=""
    local assignees=""
    local milestone=""
    local use_editor=false

    # Argument parsing
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--repo)      repo="$2";      shift 2 ;;
            -t|--title)     title="$2";     shift 2 ;;
            -b|--body)      body="$2";      shift 2 ;;
            -l|--labels)    labels="$2";    shift 2 ;;
            -a|--assignees) assignees="$2"; shift 2 ;;
            -m|--milestone) milestone="$2"; shift 2 ;;
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

    print_header
    print_info "Repository: $repo"
    print_info "Title:      $title"

    # Build gh command
    local -a cmd=(gh issue create --repo "$repo" --title "$title")

    if [[ "$use_editor" == true ]]; then
        # Editor mode: let gh open the editor
        cmd+=(--editor)
    elif [[ -n "$body" ]]; then
        cmd+=(--body "$body")
        print_info "Body:       $(echo "$body" | head -c 80)..."
    fi

    if [[ -n "$labels" ]]; then
        cmd+=(--label "$labels")
        print_info "Labels:     $labels"
    fi

    if [[ -n "$assignees" ]]; then
        cmd+=(--assignee "$assignees")
        print_info "Assignees:  $assignees"
    fi

    if [[ -n "$milestone" ]]; then
        cmd+=(--milestone "$milestone")
        print_info "Milestone:  $milestone"
    fi

    [[ "$OUTPUT_JSON" != true && "$OUTPUT_QUIET" != true ]] && echo ""

    # Execute
    local result
    result=$("${cmd[@]}" 2>&1) || {
        print_error "Failed to create issue: $result"
        exit 1
    }

    # Output
    if [[ "$OUTPUT_JSON" == true ]]; then
        local issue_number
        issue_number=$(echo "$result" | grep -oE '[0-9]+$')
        printf '{"url":"%s","number":%s}\n' "$result" "$issue_number"
    elif [[ "$OUTPUT_QUIET" == true ]]; then
        echo "$result"
    else
        echo -e "${GREEN}"
        echo "╔══════════════════════════════════════════════════════════════════════╗"
        echo "║                     Issue Created Successfully                     ║"
        echo "╚══════════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"

        echo -e "  ${BOLD}URL:${NC} $result"
        echo ""
    fi
}

main "$@"
