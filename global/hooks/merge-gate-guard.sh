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

set -uo pipefail

# --- Response helpers ---
deny_response() {
    local reason="$1"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
    exit 0
}

allow_response() {
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
    exit 0
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

# --- Call gh pr checks ---
if [ -n "$REPO" ]; then
    CHECKS_JSON=$(gh pr checks "$PR_NUM" -R "$REPO" --json bucket,name,state 2>&1)
else
    CHECKS_JSON=$(gh pr checks "$PR_NUM" --json bucket,name,state 2>&1)
fi
GH_RC=$?

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
NON_PASSING=$(printf '%s' "$CHECKS_JSON" | jq -r '
    [.[] | select(.bucket != "pass" and .bucket != "skipping")
         | "\(.name) [\(.bucket)/\(.state)]"]
    | join(", ")
' 2>/dev/null)
JQ_RC=$?

if [ $JQ_RC -ne 0 ]; then
    log_diag "jq parse failed, allowing merge (fail-open): ${CHECKS_JSON}"
    allow_response
fi

if [ -n "$NON_PASSING" ]; then
    deny_response "Merge blocked by ABSOLUTE CI GATE: PR #${PR_NUM} has non-passing checks: ${NON_PASSING}. Wait for all checks to pass before merging — never rationalize a failure as unrelated, infrastructure, or pre-existing."
fi

allow_response
