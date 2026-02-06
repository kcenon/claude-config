#!/bin/bash
#
# gh_issues.sh
#
# Fetch and display GitHub Issues across repositories
# using the gh CLI with colored table output.
#
# Prerequisites:
#   gh auth login -h github.com
#   jq (https://jqlang.github.io/jq/)
#
# Usage:
#   ./gh_issues.sh                           # All repos for authenticated user
#   ./gh_issues.sh -r owner/repo             # Specific repo
#   ./gh_issues.sh -s all -l 5               # All states, 5 per repo
#   ./gh_issues.sh --json                    # JSON output
#   ./gh_issues.sh --json | jq '.[].repo'   # Extract repo names
#   ./gh_issues.sh --quiet                   # Minimal output
#   ./gh_issues.sh -h                        # Show help
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
# Default constants
# =============================================================================
DEFAULT_STATE="open"
DEFAULT_LIMIT=30

# =============================================================================
# Global statistics
# =============================================================================
TOTAL_ISSUES=0
TOTAL_REPOS=0
FAILED_REPOS=0
SKIPPED_REPOS=0

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
    echo "║              GitHub Issues List Fetcher                             ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_help() {
    print_header
    echo -e "${CYAN}Usage:${NC}"
    echo "  $0 [OPTIONS]"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo "  -r, --repo REPO      Fetch issues from a specific repo (owner/repo format)"
    echo "  -u, --user USER      Fetch from a specific user's repos (default: authenticated user)"
    echo "  -s, --state STATE    Filter by state: open, closed, all (default: open)"
    echo "  -l, --limit LIMIT    Max issues per repo (default: 30)"
    echo "  --json               Output result as JSON (for programmatic use)"
    echo "  --quiet              Suppress decorative output"
    echo "  -h, --help           Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  $0                                # All repos, open issues"
    echo "  $0 -r kcenon/thread_system        # Specific repo"
    echo "  $0 -s all -l 10                   # All states, 10 per repo"
    echo "  $0 -u octocat                     # Specific user's repos"
    echo "  $0 --json                         # [{\"repo\":\"...\",\"issues\":[...]}]"
    echo "  $0 -r owner/repo --json           # Direct issues JSON array"
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

validate_state() {
    local state="$1"
    case "$state" in
        open|closed|all) return 0 ;;
        *)
            print_error "Invalid state: '$state'. Must be one of: open, closed, all"
            exit 1
            ;;
    esac
}

# =============================================================================
# Core logic
# =============================================================================
detect_current_user() {
    local user
    user=$(gh api user --jq '.login' 2>/dev/null) || {
        print_error "Failed to detect current user. Check gh auth status."
        exit 1
    }
    echo "$user"
}

fetch_user_repos() {
    local user="$1"
    local repos
    repos=$(gh repo list "$user" --json nameWithOwner --jq '.[].nameWithOwner' --limit 1000 2>/dev/null) || {
        print_error "Failed to fetch repos for user: $user"
        exit 1
    }
    echo "$repos"
}

fetch_issues() {
    local repo="$1"
    local state="$2"
    local limit="$3"

    # Fetch issues as JSON (exclude pull requests)
    gh issue list \
        --repo "$repo" \
        --state "$state" \
        --limit "$limit" \
        --json number,title,state,labels,createdAt \
        2>/dev/null || echo "[]"
}

truncate_string() {
    local str="$1"
    local max_len="$2"
    if [[ ${#str} -gt $max_len ]]; then
        echo "${str:0:$((max_len - 3))}..."
    else
        echo "$str"
    fi
}

# =============================================================================
# Display functions
# =============================================================================
display_table_header() {
    [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return
    printf "  ${BOLD}${DIM}%-6s %-42s %-8s %-22s %-12s${NC}\n" \
        "#" "Title" "State" "Labels" "Created"
    printf "  ${DIM}%-6s %-42s %-8s %-22s %-12s${NC}\n" \
        "------" "------------------------------------------" "--------" "----------------------" "------------"
}

display_issue_row() {
    [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return
    local number="$1"
    local title="$2"
    local state="$3"
    local labels="$4"
    local created="$5"

    # Truncate fields for table layout
    title=$(truncate_string "$title" 40)
    labels=$(truncate_string "$labels" 20)

    # Color state
    local state_colored
    case "$state" in
        OPEN)   state_colored="${GREEN}${state}${NC}"   ;;
        CLOSED) state_colored="${RED}${state}${NC}"     ;;
        *)      state_colored="${YELLOW}${state}${NC}"  ;;
    esac

    # Format date (keep only YYYY-MM-DD)
    created="${created:0:10}"

    printf "  ${BOLD}%-6s${NC} %-42s ${state_colored}$(printf '%*s' $((8 - ${#state})) '')%-22s ${DIM}%-12s${NC}\n" \
        "#${number}" "$title" "$labels" "$created"
}

display_repo_issues() {
    local repo="$1"
    local issues_json="$2"

    local count
    count=$(echo "$issues_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        print_info "No issues found in $repo"
        SKIPPED_REPOS=$((SKIPPED_REPOS + 1))
        return
    fi

    print_section "$repo  (${count} issues)"
    display_table_header

    echo "$issues_json" | jq -c '.[]' | while IFS= read -r issue; do
        local number title state labels created

        number=$(echo "$issue" | jq -r '.number')
        title=$(echo "$issue" | jq -r '.title')
        state=$(echo "$issue" | jq -r '.state')
        labels=$(echo "$issue" | jq -r '[.labels[].name] | join(", ")')
        created=$(echo "$issue" | jq -r '.createdAt')

        display_issue_row "$number" "$title" "$state" "$labels" "$created"
    done

    TOTAL_ISSUES=$((TOTAL_ISSUES + count))
    TOTAL_REPOS=$((TOTAL_REPOS + 1))
}

display_summary() {
    [[ "$OUTPUT_JSON" == true || "$OUTPUT_QUIET" == true ]] && return
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                            Summary                                 ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "  ${GREEN}Total issues:${NC}       $TOTAL_ISSUES"
    echo -e "  ${BLUE}Repos scanned:${NC}      $TOTAL_REPOS"
    if [[ $SKIPPED_REPOS -gt 0 ]]; then
        echo -e "  ${YELLOW}Repos (no issues):${NC} $SKIPPED_REPOS"
    fi
    if [[ $FAILED_REPOS -gt 0 ]]; then
        echo -e "  ${RED}Repos (failed):${NC}    $FAILED_REPOS"
    fi
    echo ""
}

# =============================================================================
# Main function
# =============================================================================
main() {
    local repo=""
    local user=""
    local state="$DEFAULT_STATE"
    local limit="$DEFAULT_LIMIT"

    # Argument parsing
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--repo)
                repo="$2"
                shift 2
                ;;
            -u|--user)
                user="$2"
                shift 2
                ;;
            -s|--state)
                state="$2"
                shift 2
                ;;
            -l|--limit)
                limit="$2"
                shift 2
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --quiet)
                OUTPUT_QUIET=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Run '$0 --help' for usage information." >&2
                exit 1
                ;;
        esac
    done

    # Validate inputs
    check_prerequisites
    validate_state "$state"

    print_header

    # Single repo mode
    if [[ -n "$repo" ]]; then
        print_info "Fetching issues from: $repo (state: $state, limit: $limit)"
        local issues_json
        issues_json=$(fetch_issues "$repo" "$state" "$limit")

        if [[ "$issues_json" == "[]" || -z "$issues_json" ]]; then
            print_info "No issues found in $repo"
            if [[ "$OUTPUT_JSON" == true ]]; then
                echo "[]"
            fi
        else
            if [[ "$OUTPUT_JSON" == true ]]; then
                # Single repo: output issues array directly
                echo "$issues_json" | jq '[.[] | {
                    number: .number,
                    title: .title,
                    state: .state,
                    labels: [.labels[].name],
                    created: .createdAt
                }]'
            else
                display_repo_issues "$repo" "$issues_json"
            fi
        fi

        display_summary
        return
    fi

    # Multi-repo mode
    if [[ -z "$user" ]]; then
        user=$(detect_current_user)
    fi

    print_info "User: $user"
    print_info "State: $state | Limit per repo: $limit"
    print_info "Fetching repository list..."

    local repos
    repos=$(fetch_user_repos "$user")

    local repo_count
    repo_count=$(echo "$repos" | grep -c . || true)
    print_info "Found $repo_count repositories. Scanning for issues..."

    # JSON mode: accumulate results in temp file
    local json_tmp=""
    if [[ "$OUTPUT_JSON" == true ]]; then
        json_tmp=$(mktemp /tmp/claude/gh_issues_XXXXXX.json 2>/dev/null || mktemp)
        echo "[]" > "$json_tmp"
    fi

    while IFS= read -r repo_name; do
        [[ -z "$repo_name" ]] && continue

        local issues_json
        issues_json=$(fetch_issues "$repo_name" "$state" "$limit") || {
            print_warning "Failed to fetch issues from $repo_name"
            FAILED_REPOS=$((FAILED_REPOS + 1))
            continue
        }

        if [[ "$issues_json" == "[]" || -z "$issues_json" ]]; then
            SKIPPED_REPOS=$((SKIPPED_REPOS + 1))
            continue
        fi

        if [[ "$OUTPUT_JSON" == true ]]; then
            # Accumulate JSON results
            local entry
            entry=$(jq -n --arg repo "$repo_name" --argjson issues "$issues_json" \
                '{repo: $repo, issues: [$issues[] | {
                    number: .number,
                    title: .title,
                    state: .state,
                    labels: [.labels[].name],
                    created: .createdAt
                }]}')
            jq --argjson entry "$entry" '. + [$entry]' "$json_tmp" > "${json_tmp}.tmp"
            mv "${json_tmp}.tmp" "$json_tmp"
        else
            display_repo_issues "$repo_name" "$issues_json"
        fi

        # Rate limit protection
        sleep 0.5
    done <<< "$repos"

    # Output
    if [[ "$OUTPUT_JSON" == true ]]; then
        cat "$json_tmp"
        rm -f "$json_tmp"
    else
        display_summary
    fi
}

main "$@"
