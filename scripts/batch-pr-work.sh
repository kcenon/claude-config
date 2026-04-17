#!/bin/bash

# Batch pr-work orchestrator
# ===========================
# Spawns one fresh `claude` CLI process per failing PR. Each process handles
# exactly one PR, so CI log accumulation and diff-read state cannot leak
# between items — PR N+1 starts with the same CLAUDE.md / skill attention
# pool as PR 1.
#
# Usage:
#   ./scripts/batch-pr-work.sh <org/repo> [limit]
#
# Example:
#   ./scripts/batch-pr-work.sh kcenon/claude-config
#   ./scripts/batch-pr-work.sh kcenon/claude-config 3
#
# Per-item logs are written to:
#   ~/.claude/batch-logs/<timestamp>/pr-<number>.log
#
# A PR is considered "failing" if at least one check has conclusion
# FAILURE, TIMED_OUT, CANCELLED, ACTION_REQUIRED, or STARTUP_FAILURE.
# Passing and in-progress PRs are skipped.
#
# On any item failure, the batch pauses and exits non-zero so the operator
# can inspect the log before deciding to continue.

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()      { echo -e "${BLUE}[info]${NC} $1"; }
success()   { echo -e "${GREEN}[ok]${NC}   $1"; }
warning()   { echo -e "${YELLOW}[warn]${NC} $1"; }
error()     { echo -e "${RED}[err]${NC}  $1"; }
highlight() { echo -e "${CYAN}$1${NC}"; }

if [[ $# -lt 1 ]]; then
    error "Missing required argument: <org/repo>"
    echo "Usage: $0 <org/repo> [limit]"
    exit 2
fi

ORG_PROJECT="$1"
LIMIT="${2:-5}"

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
    error "Limit must be a positive integer (got: $LIMIT)"
    exit 2
fi

if ! command -v claude >/dev/null 2>&1; then
    error "claude CLI not found on PATH. Install Claude Code and re-run."
    exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
    error "gh CLI not found on PATH. Install GitHub CLI and re-run."
    exit 2
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="$HOME/.claude/batch-logs/${TIMESTAMP}"
mkdir -p "$LOG_DIR"

highlight "Batch pr-work orchestrator"
info "Repository : $ORG_PROJECT"
info "Limit      : $LIMIT"
info "Log dir    : $LOG_DIR"
echo

# Collect open PRs that have at least one failing check. jq selects PRs
# where any statusCheckRollup entry has a terminal failure conclusion.
FAILING_PRS=$(gh pr list --repo "$ORG_PROJECT" --state open --limit 100 \
    --json number,title,statusCheckRollup \
    -q '.[] | select(
            [.statusCheckRollup[]?.conclusion] |
            any(
                . == "FAILURE" or . == "TIMED_OUT" or . == "CANCELLED" or
                . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE"
            )
        ) | "\(.number)\t\(.title)"' | head -n "$LIMIT")

if [[ -z "$FAILING_PRS" ]]; then
    warning "No open PRs with failing checks found in $ORG_PROJECT"
    exit 0
fi

TOTAL=$(echo "$FAILING_PRS" | wc -l | tr -d ' ')
PROCESSED=0
FAILED_ITEM=""

while IFS=$'\t' read -r PR_NUMBER PR_TITLE; do
    PROCESSED=$((PROCESSED + 1))
    LOG_FILE="${LOG_DIR}/pr-${PR_NUMBER}.log"

    highlight "[${PROCESSED}/${TOTAL}] Processing PR #${PR_NUMBER} — ${PR_TITLE}"
    info "Log: ${LOG_FILE}"

    if claude --print "/pr-work ${ORG_PROJECT} ${PR_NUMBER} --solo" \
        >"$LOG_FILE" 2>&1; then
        success "PR #${PR_NUMBER} completed"
    else
        EXIT_CODE=$?
        error "PR #${PR_NUMBER} failed (exit ${EXIT_CODE}). Pausing batch."
        error "Inspect the log before continuing: ${LOG_FILE}"
        FAILED_ITEM="PR #${PR_NUMBER}"
        break
    fi
done <<< "$FAILING_PRS"

echo
if [[ -n "$FAILED_ITEM" ]]; then
    error "Batch paused on ${FAILED_ITEM} (${PROCESSED}/${TOTAL} processed)"
    error "Logs: ${LOG_DIR}"
    exit 1
fi

success "Batch complete: ${PROCESSED}/${TOTAL} items processed"
info "Logs: ${LOG_DIR}"
