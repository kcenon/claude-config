#!/bin/bash

# Batch issue-work orchestrator
# ==============================
# Spawns one fresh `claude` CLI process per open issue. Each process handles
# exactly one item, so context state cannot leak between items — item N+1
# starts with the same CLAUDE.md / skill attention pool as item 1.
#
# Usage:
#   ./scripts/batch-issue-work.sh <org/repo> [limit]
#
# Example:
#   ./scripts/batch-issue-work.sh kcenon/claude-config
#   ./scripts/batch-issue-work.sh kcenon/claude-config 3
#
# Per-item logs are written to:
#   ~/.claude/batch-logs/<timestamp>/issue-<number>.log
#
# On any item failure, the batch pauses and exits non-zero so the operator
# can inspect the log before deciding to continue. Successful items are NOT
# rolled back — reruns should skip already-merged issues by inspecting state.
#
# Each item's outcome is read from the trailing ISSUE_WORK_RESULT: marker
# line the skill prints (see SKILL.md "Output" / reference/batch-mode.md
# B-4.a) rather than the bare process exit code: a `decomposed`/`blocked`
# status pauses the batch as an operator hand-off, distinct from a `failed`
# status. When no marker is found (older skill or a crash), the script falls
# back to the previous exit-code-only behavior.

set -euo pipefail

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

highlight "Batch issue-work orchestrator"
info "Repository : $ORG_PROJECT"
info "Limit      : $LIMIT"
info "Log dir    : $LOG_DIR"
echo

# Collect open issues, oldest first, with configurable limit.
ISSUES=$(gh issue list --repo "$ORG_PROJECT" --state open --limit "$LIMIT" \
    --json number,title -q '.[] | "\(.number)\t\(.title)"')

if [[ -z "$ISSUES" ]]; then
    warning "No open issues found in $ORG_PROJECT"
    exit 0
fi

TOTAL=$(echo "$ISSUES" | wc -l | tr -d ' ')
PROCESSED=0
FAILED_ITEM=""

# IFS=newline so titles with spaces stay intact.
while IFS=$'\t' read -r ISSUE_NUMBER ISSUE_TITLE; do
    PROCESSED=$((PROCESSED + 1))
    LOG_FILE="${LOG_DIR}/issue-${ISSUE_NUMBER}.log"

    highlight "[${PROCESSED}/${TOTAL}] Processing #${ISSUE_NUMBER} — ${ISSUE_TITLE}"
    info "Log: ${LOG_FILE}"

    # Each item runs in a fresh claude process so its context state is
    # discarded on exit. --print exits after the turn completes.
    # `|| EXIT_CODE=$?` captures claude's real exit status. An `if ! claude`
    # guard would instead leave $? as the negation result (0), so a crash with
    # no marker would be misread as success in the fallback branch below.
    EXIT_CODE=0
    claude --print "/issue-work ${ORG_PROJECT} ${ISSUE_NUMBER} --solo" \
        >"$LOG_FILE" 2>&1 || EXIT_CODE=$?

    # Prefer the structured result marker over the bare exit code -- it
    # distinguishes a triage pause (decomposed/blocked) from a hard failure.
    # `|| true` so "no marker found" (older skill or a crash) does not abort
    # the script under set -e/pipefail.
    MARKER_LINE=$(grep -o 'ISSUE_WORK_RESULT:.*' "$LOG_FILE" 2>/dev/null | tail -n1 || true)
    STATUS=""
    if [[ -n "$MARKER_LINE" ]]; then
        STATUS=$(printf '%s' "$MARKER_LINE" | sed -E 's/^ISSUE_WORK_RESULT:[[:space:]]*//' \
            | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)
    fi

    case "$STATUS" in
        merged)
            success "#${ISSUE_NUMBER} merged"
            ;;
        skipped)
            warning "#${ISSUE_NUMBER} skipped (deduplicated or closed) — continuing"
            ;;
        decomposed|blocked)
            warning "#${ISSUE_NUMBER} paused for operator (${STATUS}) — not a failure, but the batch stops here."
            error "Inspect the log and resolve before resuming: ${LOG_FILE}"
            FAILED_ITEM="#${ISSUE_NUMBER} (${STATUS})"
            break
            ;;
        failed)
            error "#${ISSUE_NUMBER} failed (exit ${EXIT_CODE}). Pausing batch."
            error "Inspect the log before continuing: ${LOG_FILE}"
            FAILED_ITEM="#${ISSUE_NUMBER}"
            break
            ;;
        "")
            # No marker found -- fall back to the exit-code-only behavior
            # this script used before the marker existed.
            if [[ "$EXIT_CODE" -eq 0 ]]; then
                success "#${ISSUE_NUMBER} completed"
            else
                error "#${ISSUE_NUMBER} failed (exit ${EXIT_CODE}). Pausing batch."
                error "Inspect the log before continuing: ${LOG_FILE}"
                FAILED_ITEM="#${ISSUE_NUMBER}"
                break
            fi
            ;;
        *)
            error "#${ISSUE_NUMBER} failed (unrecognized status=${STATUS}, exit ${EXIT_CODE}). Pausing batch."
            error "Inspect the log before continuing: ${LOG_FILE}"
            FAILED_ITEM="#${ISSUE_NUMBER}"
            break
            ;;
    esac
done <<< "$ISSUES"

echo
if [[ -n "$FAILED_ITEM" ]]; then
    error "Batch paused on ${FAILED_ITEM} (${PROCESSED}/${TOTAL} processed)"
    error "Logs: ${LOG_DIR}"
    exit 1
fi

success "Batch complete: ${PROCESSED}/${TOTAL} items processed"
info "Logs: ${LOG_DIR}"
