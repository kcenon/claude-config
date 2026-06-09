#!/bin/bash
# traceability-guard.sh
# Deterministic traceability cascade validator.
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Mirrors the multi-layer pattern proven by commit-message-guard
# (PreToolUse) + commit-msg (git hook) + validate-commit-message.sh
# (shared library). This hook is the Claude-side feedback loop for
# the cascade-update obligation captured in
# global/skills/_internal/traceability/reference/matrix-schema.md.
#
# Scope: only fires for `gh pr create` invocations. Other commands —
# including `git push`, which is the pre-push hook's responsibility —
# pass through untouched.
#
# Opt-in: when docs/.index/graph.yaml is absent, the hook allows the
# command silently. This keeps the hook safe to ship globally without
# breaking repos that have not adopted the regulated track.
#
# Sources shared validation rules from hooks/lib/validate-traceability.sh
# (single source of truth shared with the pre-push git hook).

set -euo pipefail

# --- Response helpers (match commit-message-guard.sh / pr-target-guard.sh) ---
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

# --- Source shared validation library (fail-closed) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR=""

# Try 1: repo-relative path (development / CI testing)
REPO_ROOT_DEV="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"
if [ -f "$REPO_ROOT_DEV/hooks/lib/validate-traceability.sh" ]; then
    VALIDATOR="$REPO_ROOT_DEV/hooks/lib/validate-traceability.sh"
# Try 2: sibling lib/ directory (deployed to ~/.claude/hooks/)
elif [ -f "$SCRIPT_DIR/lib/validate-traceability.sh" ]; then
    VALIDATOR="$SCRIPT_DIR/lib/validate-traceability.sh"
fi

if [ -z "$VALIDATOR" ]; then
    echo "traceability-guard: canonical validator not found at \$REPO_ROOT/hooks/lib/validate-traceability.sh nor \$SCRIPT_DIR/lib/validate-traceability.sh. Reinstall claude-config so hooks/lib/ is bundled alongside global/hooks/." >&2
    # Fail-open here — the pre-push git hook is the authoritative gate. A
    # missing PreToolUse validator must not block legitimate PR creation.
    allow_response
fi

# shellcheck source=../../hooks/lib/validate-traceability.sh
. "$VALIDATOR"

# --- Read input from stdin ---
INPUT=$(cat)

# Empty input: allow. The pre-push hook is the terminal gate.
if [ -z "$INPUT" ]; then
    allow_response
fi

JQ_RC=0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || JQ_RC=$?
if [ "$JQ_RC" -ne 0 ]; then
    # Fail-open on JSON parse errors — pre-push remains the gate.
    allow_response
fi

if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# --- Scope: only validate `gh pr create` commands ---
if ! echo "$CMD" | grep -qE 'gh[[:space:]]+pr[[:space:]]+create'; then
    allow_response
fi

# --- Discover repo root (current working directory tree) ---
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Opt-in gate: skip silently when graph.yaml is absent.
if [ ! -f "$REPO_ROOT/docs/.index/graph.yaml" ]; then
    allow_response
fi

# --- Resolve base / head refs for the diff range ---
# Default base is the repo's default branch. We follow the convention used
# by `gh pr create`: when --base is omitted, gh asks the server, but for
# pre-PR validation we approximate that with origin/HEAD or `develop`.
BASE_REF=""
BASE_FROM_CMD=$(echo "$CMD" | sed -nE 's/.*(--base[= ])[\"'"'"']?([a-zA-Z0-9._\/-]+).*/\2/p' | head -1)
BASE_REF="${BASE_FROM_CMD:-}"
if [ -z "$BASE_REF" ]; then
    if git -C "$REPO_ROOT" show-ref --verify --quiet refs/remotes/origin/develop; then
        BASE_REF="origin/develop"
    elif git -C "$REPO_ROOT" show-ref --verify --quiet refs/heads/develop; then
        BASE_REF="develop"
    else
        BASE_REF="HEAD~1"
    fi
fi
# Strip surrounding quotes if present.
BASE_REF=$(echo "$BASE_REF" | sed -E "s/^[\"']//;s/[\"']$//")

# If the user passed an unqualified branch name and a matching remote ref
# exists, prefer the remote so the diff matches what GitHub will compute.
if echo "$BASE_REF" | grep -qE '^[A-Za-z0-9_.\-]+$'; then
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/$BASE_REF"; then
        BASE_REF="origin/$BASE_REF"
    fi
fi

HEAD_REF="HEAD"

# --- Validate ---
REPORT_FILE=""
if REPORT_FILE=$(mktemp 2>/dev/null); then
    :
else
    REPORT_FILE="${TMPDIR:-/tmp}/traceability-guard.$$.txt"
    : > "$REPORT_FILE"
fi
# shellcheck disable=SC2064
trap "rm -f '$REPORT_FILE'" EXIT

set +e
( cd "$REPO_ROOT" && validate_traceability_range "$BASE_REF" "$HEAD_REF" "$REPO_ROOT" ) 2>"$REPORT_FILE"
RC=$?
set -e

if [ "$RC" -eq 0 ]; then
    allow_response
fi

# Build a concise reason string from the report.
REASON_BODY=$(head -20 "$REPORT_FILE" 2>/dev/null || echo "")
if [ -z "$REASON_BODY" ]; then
    REASON_BODY="validate-traceability returned exit code $RC but produced no report"
fi
deny_response "Traceability cascade not satisfied for ${BASE_REF}..${HEAD_REF}. Update the cascade targets declared in docs/.index/graph.yaml before creating the PR.
${REASON_BODY}"
