#!/bin/bash
# merge-gate-guard.sh
# Blocks gh pr merge commands when any PR check is not passing.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Enforces the "ABSOLUTE CI GATE" rule from global/CLAUDE.md at the Bash
# tool boundary. Mirrors the commit-message-guard / pr-language-guard
# enforcement model: a deterministic hook gate that catches drift in
# long-running batch workflows where the model occasionally rationalizes
# failing checks as "unrelated" or "infrastructure-only".
#
# Allow policy: every check must be in bucket "pass" or "skipping".
# Anything in bucket "fail", "pending", or "cancel" blocks the merge.
#
# Fail policy: FAIL-OPEN on gh CLI errors. If gh is missing, unauthenticated,
# or the API call fails for any reason, the merge is allowed and a diagnostic
# is written to stderr. This prevents transient network issues from
# permanently blocking user work — the policy is "best-effort gate", not
# "hard-fail on tool unavailability". Server-side branch protection rules
# remain as the authoritative gate.

set -euo pipefail

# --- Resolve script dir + load shared helpers ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/timeout-wrapper.sh
. "$SCRIPT_DIR/lib/timeout-wrapper.sh"

# Wall-clock budget for any single `gh pr checks` invocation. Slow networks
# and GitHub degradation can otherwise pin the entire PreToolUse chain on
# the gh internal default (~30 s). 10 s is short enough to keep merge UX
# snappy and long enough to ride out typical jitter.
GH_CHECKS_TIMEOUT_SEC="${GH_CHECKS_TIMEOUT_SEC:-10}"

# Opt-in pending-check escape hatch (Issue #747 / WS4).
# UNSET or empty (the default) preserves the strict behavior: any check not in
# bucket pass/skipping hard-blocks the merge. When set to a positive integer N,
# checks stuck in the *pending* bucket for more than N minutes are downgraded
# from a hard deny to an allow-with-warning. fail/cancel/error buckets remain
# hard-blocked regardless of this setting — only pending is ever relaxed.
GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES="${GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES:-}"

# --- Response helpers ---
# Use jq -nc --arg reason ... so the JSON library handles all escaping
# (quotes, backslashes, newlines, tabs, carriage returns, etc.). This closes
# the historical injection class where a crafted reason string concatenated
# into the heredoc could flip the decision (issue #567 / sub-issue #579).
deny_response() {
    local reason="$1"
    jq -nc \
        --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    exit 0
}

allow_response() {
    jq -nc \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
    exit 0
}

# allow_with_context <warning> — allow the merge but surface a warning to the
# model. Used only for the opt-in pending-timeout downgrade; the strict default
# path never reaches this.
allow_with_context() {
    local context="$1"
    jq -nc \
        --arg context "$context" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", additionalContext: $context}}'
    exit 0
}

# is_positive_int <value> — 0 if the value is a non-empty string of digits with
# a value > 0, else 1. Rejects "0", negatives, and non-numeric junk so a
# malformed env var falls back to strict behavior rather than failing open.
is_positive_int() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -gt 0 ] 2>/dev/null
}

log_diag() {
    echo "merge-gate-guard: $1" >&2
}

# --- Read input from stdin ---
INPUT=$(cat)

# Empty input: fail open — nothing to validate
if [ -z "$INPUT" ]; then
    allow_response
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || CMD=""
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

if [ -z "$CMD" ]; then
    allow_response
fi

# --- Scope: only validate gh pr merge commands ---
if ! echo "$CMD" | grep -qE 'gh[[:space:]]+pr[[:space:]]+merge'; then
    allow_response
fi

# --- Squash-only enforcement (Issue #478) ---
# The branching strategy mandates squash merges to develop/main. Reject
# `--merge` and `--rebase` flags so the gh CLI cannot bypass that policy
# even when the model is convinced "this one time" is fine.
if echo "$CMD" | grep -qE -- '(^|[[:space:]])--(merge|rebase)([[:space:]]|=|$)'; then
    deny_response "gh pr merge --merge/--rebase blocked: branching strategy requires squash merges (use --squash). See workflow/branching-strategy.md."
fi

# --- Extract PR number ---
# Supports: gh pr merge 123, gh pr merge 123 --squash, gh pr merge --squash 123,
#           gh pr merge https://github.com/owner/repo/pull/123
PR_NUM=""

# Try positional integer immediately after 'gh pr merge'
PR_NUM=$(printf '%s' "$CMD" | sed -nE 's/.*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+([0-9]+).*/\1/p' | head -n1)

# Try URL form
if [ -z "$PR_NUM" ]; then
    PR_NUM=$(printf '%s' "$CMD" | sed -nE 's|.*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+https?://github\.com/[^/]+/[^/]+/pull/([0-9]+).*|\1|p' | head -n1)
fi

# Try positional integer anywhere after 'gh pr merge' (handles flags before PR)
if [ -z "$PR_NUM" ]; then
    PR_NUM=$(printf '%s' "$CMD" | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge.*' | grep -oE '(^|[[:space:]])[0-9]+([[:space:]]|$)' | head -n1 | tr -d '[:space:]')
fi

# No PR number found — likely interactive mode (gh pr merge with no args)
# or unparseable form. Allow and let gh handle it interactively.
if [ -z "$PR_NUM" ]; then
    log_diag "could not extract PR number from command, allowing"
    allow_response
fi

# --- Extract repo (-R / --repo) ---
REPO=""
REPO=$(printf '%s' "$CMD" | sed -nE 's/.*--repo[[:space:]=]+["'"'"']?([^[:space:]"'"'"']+).*/\1/p' | head -n1)
if [ -z "$REPO" ]; then
    REPO=$(printf '%s' "$CMD" | sed -nE 's/.*[[:space:]]-R[[:space:]]+["'"'"']?([^[:space:]"'"'"']+).*/\1/p' | head -n1)
fi

# --- Verify gh is available ---
if ! command -v gh >/dev/null 2>&1; then
    log_diag "gh CLI not installed, allowing merge (fail-open)"
    allow_response
fi

# --- Call gh pr checks (bounded by cross-platform timeout wrapper) ---
# Request startedAt only when the pending-timeout escape hatch is active, so
# the default strict path keeps its existing minimal field set.
CHECKS_FIELDS="bucket,name,state"
if is_positive_int "$GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES"; then
    CHECKS_FIELDS="bucket,name,state,startedAt"
fi

GH_RC=0
if [ -n "$REPO" ]; then
    CHECKS_JSON=$(_run_with_timeout "$GH_CHECKS_TIMEOUT_SEC" gh pr checks "$PR_NUM" -R "$REPO" --json "$CHECKS_FIELDS" 2>&1) || GH_RC=$?
else
    CHECKS_JSON=$(_run_with_timeout "$GH_CHECKS_TIMEOUT_SEC" gh pr checks "$PR_NUM" --json "$CHECKS_FIELDS" 2>&1) || GH_RC=$?
fi

# 124 is the GNU-timeout sentinel; the wrapper normalizes perl/bash fallbacks
# to the same code so a single branch covers all platforms. Fail-open per
# the guard's stated policy — server-side branch protection remains the
# authoritative gate.
if [ $GH_RC -eq 124 ]; then
    log_diag "gh pr checks timed out after ${GH_CHECKS_TIMEOUT_SEC}s, allowing merge (fail-open)"
    allow_response
fi

if [ $GH_RC -ne 0 ]; then
    log_diag "gh pr checks failed (exit $GH_RC), allowing merge (fail-open): ${CHECKS_JSON}"
    allow_response
fi

# Empty JSON array means no checks are configured for this PR — allow.
if [ -z "$CHECKS_JSON" ] || [ "$CHECKS_JSON" = "[]" ]; then
    log_diag "no checks configured for PR #${PR_NUM}, allowing"
    allow_response
fi

# --- Parse non-passing checks ---
# Allowed buckets: pass, skipping. Anything else blocks the merge.
JQ_RC=0
NON_PASSING=$(printf '%s' "$CHECKS_JSON" | jq -r '
    [.[] | select(.bucket != "pass" and .bucket != "skipping")
         | "\(.name) [\(.bucket)/\(.state)]"]
    | join(", ")
' 2>/dev/null) || JQ_RC=$?

if [ $JQ_RC -ne 0 ]; then
    log_diag "jq parse failed, allowing merge (fail-open): ${CHECKS_JSON}"
    allow_response
fi

# Nothing outside pass/skipping — clean gate, allow.
if [ -z "$NON_PASSING" ]; then
    allow_response
fi

# --- Pending-timeout escape hatch (opt-in; Issue #747) ---
# The downgrade applies ONLY when:
#   (a) GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES is a positive integer, AND
#   (b) EVERY non-passing check is in the `pending` bucket (no fail/cancel/
#       error/other), AND
#   (c) EVERY pending check has been pending longer than the threshold.
# If any of these fail we fall through to the strict deny below, so a single
# failing check or a not-yet-timed-out pending check still hard-blocks.
if is_positive_int "$GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES"; then
    # Are there any non-passing, non-pending checks? Those can never be relaxed.
    NON_PENDING_BLOCKERS=$(printf '%s' "$CHECKS_JSON" | jq -r '
        [.[] | select(.bucket != "pass" and .bucket != "skipping" and .bucket != "pending")]
        | length
    ' 2>/dev/null) || NON_PENDING_BLOCKERS="parse_error"

    if [ "$NON_PENDING_BLOCKERS" = "0" ]; then
        # Only pending checks remain. Count those NOT yet past the threshold
        # (missing/zero startedAt counts as not-yet-timed-out → still blocks).
        THRESHOLD_SEC=$((GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES * 60))
        NOW_EPOCH=$(date -u +%s 2>/dev/null || echo 0)
        STILL_FRESH=$(printf '%s' "$CHECKS_JSON" | NOW_EPOCH="$NOW_EPOCH" THRESHOLD_SEC="$THRESHOLD_SEC" jq -r '
            ($ENV.NOW_EPOCH | tonumber) as $now
            | ($ENV.THRESHOLD_SEC | tonumber) as $thr
            | [ .[]
                | select(.bucket == "pending")
                | ((.startedAt // "") | if . == "" or . == null then 0
                    else (fromdateiso8601? // 0) end) as $started
                | select($started == 0 or ($now - $started) <= $thr) ]
            | length
        ' 2>/dev/null) || STILL_FRESH="parse_error"

        if [ "$STILL_FRESH" = "0" ] && [ "$NOW_EPOCH" != "0" ]; then
            allow_with_context "merge-gate-guard: PR #${PR_NUM} has only pending checks (${NON_PASSING}), all stuck > ${GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES} min. Downgraded to a warning by GH_MERGE_GATE_PENDING_TIMEOUT_MINUTES. Confirm these checks are genuinely stuck (not legitimately running) before merging — server-side branch protection remains the authoritative gate."
        fi
    fi
fi

# Strict default: any non-passing check (including not-yet-timed-out pending)
# hard-blocks the merge.
deny_response "Merge blocked by ABSOLUTE CI GATE: PR #${PR_NUM} has non-passing checks: ${NON_PASSING}. Wait for all checks to pass before merging — never rationalize a failure as unrelated, infrastructure, or pre-existing."
