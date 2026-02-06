#!/bin/bash
#
# gh_issue_read.sh
#
# Read a GitHub Issue's description and comments
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#   jq (https://jqlang.github.io/jq/)
#
# Usage:
#   ./gh_issue_read.sh -n 42                            # Auto-detect repo
#   ./gh_issue_read.sh -r owner/repo -n 42              # Specific repo
#   ./gh_issue_read.sh -n 42 --no-comments              # Description only
#   ./gh_issue_read.sh -n 42 --json                     # JSON output
#   ./gh_issue_read.sh -n 42 --json | jq .              # Pretty JSON
#   ./gh_issue_read.sh -n 42 --quiet                    # Minimal output
#   ./gh_issue_read.sh -h                                # Show help
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

print_section() {
    [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_header() {
    [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║              GitHub Issue Reader                                    ║"
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
    echo "  --no-comments            Show only the issue description (skip comments)"
    echo "  --json                   Output result as JSON (for programmatic use)"
    echo "  --quiet                  Suppress decorative output"
    echo "  -h, --help               Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  $0 -n 42                                 # Auto-detect repo"
    echo "  $0 -r kcenon/thread_system -n 10         # Specific repo"
    echo "  $0 -n 42 --no-comments                   # Description only"
    echo "  $0 -n 42 --json                          # Structured JSON"
    echo "  $0 -n 42 --json | jq '.title'            # Extract title"
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
# JSON output function
# =============================================================================
output_issue_json() {
    local repo="$1"
    local number="$2"
    local show_comments="$3"

    local issue_json
    issue_json=$(gh issue view "$number" \
        --repo "$repo" \
        --json number,title,state,body,author,labels,assignees,createdAt,updatedAt \
        2>/dev/null) || {
        print_error "Failed to fetch issue #$number from $repo"
        exit 1
    }

    if [[ "$show_comments" == true ]]; then
        local comments_json
        comments_json=$(gh api "repos/${repo}/issues/${number}/comments" --jq '.' 2>/dev/null) || comments_json="[]"

        echo "$issue_json" | jq \
            --argjson comments "$comments_json" \
            '{
                number: .number,
                title: .title,
                state: .state,
                author: .author.login,
                labels: [.labels[].name],
                assignees: [.assignees[].login],
                body: (.body // ""),
                created: .createdAt,
                updated: .updatedAt,
                comments: [$comments[] | {
                    author: .user.login,
                    created: .created_at,
                    body: .body
                }]
            }'
    else
        echo "$issue_json" | jq '{
            number: .number,
            title: .title,
            state: .state,
            author: .author.login,
            labels: [.labels[].name],
            assignees: [.assignees[].login],
            body: (.body // ""),
            created: .createdAt,
            updated: .updatedAt
        }'
    fi
}

# =============================================================================
# Display functions
# =============================================================================
display_issue_detail() {
    local repo="$1"
    local number="$2"

    local issue_json
    issue_json=$(gh issue view "$number" \
        --repo "$repo" \
        --json number,title,state,body,author,labels,assignees,milestone,createdAt,updatedAt \
        2>/dev/null) || {
        print_error "Failed to fetch issue #$number from $repo"
        exit 1
    }

    local title state author created updated body label_str assignee_str milestone_name
    title=$(echo "$issue_json" | jq -r '.title')
    state=$(echo "$issue_json" | jq -r '.state')
    author=$(echo "$issue_json" | jq -r '.author.login')
    created=$(echo "$issue_json" | jq -r '.createdAt[:10]')
    updated=$(echo "$issue_json" | jq -r '.updatedAt[:10]')
    body=$(echo "$issue_json" | jq -r '.body // "(no description)"')
    label_str=$(echo "$issue_json" | jq -r '[.labels[].name] | join(", ") // "-"')
    assignee_str=$(echo "$issue_json" | jq -r '[.assignees[].login] | join(", ") // "-"')
    milestone_name=$(echo "$issue_json" | jq -r '.milestone.title // "-"')

    # Color state
    local state_colored
    case "$state" in
        OPEN)   state_colored="${GREEN}OPEN${NC}"   ;;
        CLOSED) state_colored="${RED}CLOSED${NC}"   ;;
        *)      state_colored="${YELLOW}${state}${NC}" ;;
    esac

    print_section "Issue #${number}: ${title}"

    echo ""
    echo -e "  ${BOLD}State:${NC}      $state_colored"
    echo -e "  ${BOLD}Author:${NC}     $author"
    echo -e "  ${BOLD}Labels:${NC}     $label_str"
    echo -e "  ${BOLD}Assignees:${NC}  $assignee_str"
    echo -e "  ${BOLD}Milestone:${NC}  $milestone_name"
    echo -e "  ${BOLD}Created:${NC}    $created"
    echo -e "  ${BOLD}Updated:${NC}    $updated"

    echo ""
    echo -e "  ${BOLD}${CYAN}Description:${NC}"
    echo -e "${DIM}  ──────────────────────────────────────────────────────────────────${NC}"
    echo "$body" | sed 's/^/  /'
    echo -e "${DIM}  ──────────────────────────────────────────────────────────────────${NC}"
}

display_comments() {
    local repo="$1"
    local number="$2"

    local comments_json
    comments_json=$(gh api "repos/${repo}/issues/${number}/comments" \
        --jq '.' 2>/dev/null) || {
        print_warning "Failed to fetch comments for issue #$number"
        return 1
    }

    local count
    count=$(echo "$comments_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo ""
        print_info "No comments on this issue."
        return 0
    fi

    print_section "Comments ($count)"

    echo "$comments_json" | jq -c '.[]' | while IFS= read -r comment; do
        local author created body
        author=$(echo "$comment" | jq -r '.user.login')
        created=$(echo "$comment" | jq -r '.created_at[:10]')
        body=$(echo "$comment" | jq -r '.body')

        echo ""
        echo -e "  ${BOLD}${MAGENTA}@${author}${NC}  ${DIM}${created}${NC}"
        echo -e "${DIM}  ──────────────────────────────────────────────────────────────────${NC}"
        echo "$body" | sed 's/^/  /'
        echo -e "${DIM}  ──────────────────────────────────────────────────────────────────${NC}"
    done
}

# =============================================================================
# Main function
# =============================================================================
main() {
    local repo=""
    local number=""
    local show_comments=true

    # Argument parsing
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--repo)         repo="$2";   shift 2 ;;
            -n|--number)       number="$2"; shift 2 ;;
            --no-comments)     show_comments=false; shift ;;
            --json)            OUTPUT_JSON=true; shift ;;
            --quiet)           OUTPUT_QUIET=true; shift ;;
            -h|--help)         show_help; exit 0 ;;
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

    if [[ -z "$repo" ]]; then
        repo=$(detect_repo)
    fi

    # JSON mode: output structured JSON and exit
    if [[ "$OUTPUT_JSON" == true ]]; then
        output_issue_json "$repo" "$number" "$show_comments"
        exit 0
    fi

    print_header
    print_info "Repository: $repo"

    # Display issue
    display_issue_detail "$repo" "$number"

    # Display comments
    if [[ "$show_comments" == true ]]; then
        display_comments "$repo" "$number"
    fi

    echo ""
}

main "$@"
