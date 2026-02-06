#!/bin/bash
#
# gh_pr_read.sh
#
# Read a GitHub Pull Request's description, comments, and review comments
# using the gh CLI with colored output.
#
# Prerequisites:
#   gh auth login -h github.com
#   jq (https://jqlang.github.io/jq/)
#
# Usage:
#   ./gh_pr_read.sh -n 42                               # Auto-detect repo
#   ./gh_pr_read.sh -r owner/repo -n 42                 # Specific repo
#   ./gh_pr_read.sh -n 42 --no-comments                 # Description only
#   ./gh_pr_read.sh -n 42 --no-reviews                  # Skip review comments
#   ./gh_pr_read.sh -n 42 --json                        # JSON output
#   ./gh_pr_read.sh -n 42 --json | jq .                 # Pretty JSON
#   ./gh_pr_read.sh -n 42 --quiet                       # Minimal output
#   ./gh_pr_read.sh -h                                   # Show help
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
    echo "║              GitHub Pull Request Reader                             ║"
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
    echo "  -n, --number NUMBER      PR number (required)"
    echo "  --no-comments            Skip general comments"
    echo "  --no-reviews             Skip review comments"
    echo "  --json                   Output result as JSON (for programmatic use)"
    echo "  --quiet                  Suppress decorative output"
    echo "  -h, --help               Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  $0 -n 42                                 # Auto-detect repo"
    echo "  $0 -r kcenon/thread_system -n 10         # Specific repo"
    echo "  $0 -n 42 --no-reviews                    # Skip review comments"
    echo "  $0 -n 42 --json                          # Structured JSON"
    echo "  $0 -n 42 --json | jq '.reviews'          # Extract reviews"
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
output_pr_json() {
    local repo="$1"
    local number="$2"
    local show_comments="$3"
    local show_reviews="$4"

    local pr_json
    pr_json=$(gh pr view "$number" \
        --repo "$repo" \
        --json number,title,state,body,author,labels,assignees,baseRefName,headRefName,additions,deletions,changedFiles,createdAt,updatedAt \
        2>/dev/null) || {
        print_error "Failed to fetch PR #$number from $repo"
        exit 1
    }

    local comments_json="[]"
    if [[ "$show_comments" == true ]]; then
        comments_json=$(gh api "repos/${repo}/issues/${number}/comments" --jq '.' 2>/dev/null) || comments_json="[]"
    fi

    local reviews_json="[]"
    if [[ "$show_reviews" == true ]]; then
        reviews_json=$(gh api "repos/${repo}/pulls/${number}/reviews" --jq '.' 2>/dev/null) || reviews_json="[]"
    fi

    echo "$pr_json" | jq \
        --argjson comments "$comments_json" \
        --argjson reviews "$reviews_json" \
        '{
            number: .number,
            title: .title,
            state: .state,
            author: .author.login,
            labels: [.labels[].name],
            assignees: [.assignees[].login],
            base: .baseRefName,
            head: .headRefName,
            additions: .additions,
            deletions: .deletions,
            changed_files: .changedFiles,
            body: (.body // ""),
            created: .createdAt,
            updated: .updatedAt,
            comments: [$comments[] | {
                author: .user.login,
                created: .created_at,
                body: .body
            }],
            reviews: [$reviews[] | select(.body != "" and .body != null) | {
                author: .user.login,
                state: .state,
                body: .body,
                submitted: .submitted_at
            }]
        }'
}

# =============================================================================
# Display functions
# =============================================================================
display_pr_detail() {
    local repo="$1"
    local number="$2"

    local pr_json
    pr_json=$(gh pr view "$number" \
        --repo "$repo" \
        --json number,title,state,body,author,labels,assignees,reviewRequests,baseRefName,headRefName,additions,deletions,changedFiles,commits,createdAt,updatedAt,mergeable,isDraft \
        2>/dev/null) || {
        print_error "Failed to fetch PR #$number from $repo"
        exit 1
    }

    local title state author base_branch head_branch created updated body
    local label_str assignee_str reviewer_str
    local additions deletions changed_files commit_count is_draft mergeable

    title=$(echo "$pr_json" | jq -r '.title')
    state=$(echo "$pr_json" | jq -r '.state')
    author=$(echo "$pr_json" | jq -r '.author.login')
    base_branch=$(echo "$pr_json" | jq -r '.baseRefName')
    head_branch=$(echo "$pr_json" | jq -r '.headRefName')
    created=$(echo "$pr_json" | jq -r '.createdAt[:10]')
    updated=$(echo "$pr_json" | jq -r '.updatedAt[:10]')
    body=$(echo "$pr_json" | jq -r '.body // "(no description)"')
    label_str=$(echo "$pr_json" | jq -r '[.labels[].name] | join(", ") // "-"')
    assignee_str=$(echo "$pr_json" | jq -r '[.assignees[].login] | join(", ") // "-"')
    reviewer_str=$(echo "$pr_json" | jq -r '[.reviewRequests[].login // .reviewRequests[].name] | join(", ") // "-"')
    additions=$(echo "$pr_json" | jq -r '.additions')
    deletions=$(echo "$pr_json" | jq -r '.deletions')
    changed_files=$(echo "$pr_json" | jq -r '.changedFiles')
    commit_count=$(echo "$pr_json" | jq -r '.commits.totalCount')
    is_draft=$(echo "$pr_json" | jq -r '.isDraft')
    mergeable=$(echo "$pr_json" | jq -r '.mergeable')

    # Color state
    local state_colored
    case "$state" in
        OPEN)   state_colored="${GREEN}OPEN${NC}"     ;;
        CLOSED) state_colored="${RED}CLOSED${NC}"     ;;
        MERGED) state_colored="${MAGENTA}MERGED${NC}" ;;
        *)      state_colored="${YELLOW}${state}${NC}" ;;
    esac

    print_section "PR #${number}: ${title}"

    echo ""
    echo -e "  ${BOLD}State:${NC}      $state_colored"
    [[ "$is_draft" == "true" ]] && echo -e "  ${BOLD}Draft:${NC}      ${YELLOW}yes${NC}"
    echo -e "  ${BOLD}Author:${NC}     $author"
    echo -e "  ${BOLD}Branch:${NC}     $head_branch → $base_branch"
    echo -e "  ${BOLD}Labels:${NC}     $label_str"
    echo -e "  ${BOLD}Assignees:${NC}  $assignee_str"
    echo -e "  ${BOLD}Reviewers:${NC}  $reviewer_str"
    echo -e "  ${BOLD}Mergeable:${NC}  $mergeable"
    echo -e "  ${BOLD}Changes:${NC}    ${GREEN}+${additions}${NC} ${RED}-${deletions}${NC} in ${changed_files} files (${commit_count} commits)"
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
        print_warning "Failed to fetch comments for PR #$number"
        return 1
    }

    local count
    count=$(echo "$comments_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo ""
        print_info "No general comments on this PR."
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

display_review_comments() {
    local repo="$1"
    local number="$2"

    local reviews_json
    reviews_json=$(gh api "repos/${repo}/pulls/${number}/reviews" \
        --jq '.' 2>/dev/null) || {
        print_warning "Failed to fetch reviews for PR #$number"
        return 1
    }

    local count
    count=$(echo "$reviews_json" | jq '[.[] | select(.body != "" and .body != null)] | length')

    if [[ "$count" -eq 0 ]]; then
        echo ""
        print_info "No review comments on this PR."
        return 0
    fi

    print_section "Reviews ($count)"

    echo "$reviews_json" | jq -c '.[] | select(.body != "" and .body != null)' | while IFS= read -r review; do
        local author state body submitted
        author=$(echo "$review" | jq -r '.user.login')
        state=$(echo "$review" | jq -r '.state')
        body=$(echo "$review" | jq -r '.body')
        submitted=$(echo "$review" | jq -r '.submitted_at[:10]')

        # Color review state
        local state_colored
        case "$state" in
            APPROVED)          state_colored="${GREEN}APPROVED${NC}" ;;
            CHANGES_REQUESTED) state_colored="${RED}CHANGES_REQUESTED${NC}" ;;
            COMMENTED)         state_colored="${CYAN}COMMENTED${NC}" ;;
            *)                 state_colored="${YELLOW}${state}${NC}" ;;
        esac

        echo ""
        echo -e "  ${BOLD}${MAGENTA}@${author}${NC}  $state_colored  ${DIM}${submitted}${NC}"
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
    local show_reviews=true

    # Argument parsing
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--repo)         repo="$2";   shift 2 ;;
            -n|--number)       number="$2"; shift 2 ;;
            --no-comments)     show_comments=false; shift ;;
            --no-reviews)      show_reviews=false;  shift ;;
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
        print_error "PR number is required. Use -n to provide one."
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    if [[ -z "$repo" ]]; then
        repo=$(detect_repo)
    fi

    # JSON mode: output structured JSON and exit
    if [[ "$OUTPUT_JSON" == true ]]; then
        output_pr_json "$repo" "$number" "$show_comments" "$show_reviews"
        exit 0
    fi

    print_header
    print_info "Repository: $repo"

    # Display PR
    display_pr_detail "$repo" "$number"

    # Display comments
    if [[ "$show_comments" == true ]]; then
        display_comments "$repo" "$number"
    fi

    # Display reviews
    if [[ "$show_reviews" == true ]]; then
        display_review_comments "$repo" "$number"
    fi

    echo ""
}

main "$@"
