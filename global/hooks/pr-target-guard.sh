#!/bin/bash
# pr-target-guard.sh
# Blocks PRs targeting 'main' from non-develop branches
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# Branching policy: only 'develop' may merge into 'main'.
# Feature/fix branches must target 'develop'.
# Release PRs (develop → main) are created via /release skill.

set -euo pipefail

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

# Read input from stdin (Claude Code passes JSON via stdin)
INPUT=$(cat)

# Fail-closed: deny if stdin is empty or missing
if [ -z "$INPUT" ]; then
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

# Capture jq's exit status without tripping set -e.
JQ_RC=0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || JQ_RC=$?

# Fail-closed: deny if jq parsing failed
if [ "$JQ_RC" -ne 0 ]; then
    deny_response "Failed to parse hook input JSON — denying for safety (fail-closed)"
fi

# Fallback to environment variable for backward compatibility
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# Scope gate: only check 'gh pr create' commands
if ! echo "$CMD" | grep -qE 'gh[[:space:]]+pr[[:space:]]+create'; then
    allow_response
fi

# Extract --base value (supports: --base main, --base=main, -B main)
# Uses sed -nE with /p for POSIX compatibility (BSD grep lacks \x27, \s)
BASE=$(echo "$CMD" | sed -nE "s/.*(--base[= ])[\"']?([a-zA-Z0-9._/-]+).*/\2/p" | head -1)
if [ -z "$BASE" ]; then
    BASE=$(echo "$CMD" | sed -nE "s/.*-B[[:space:]]*[\"']?([a-zA-Z0-9._/-]+).*/\1/p" | head -1)
fi

# If no --base flag found, query the repo's default branch instead of
# blindly allowing. Repos with default_branch=main (e.g. vcpkg-registry)
# previously bypassed the policy because the hook assumed develop-default.
# PR_TARGET_GUARD_DEFAULT_BRANCH_OVERRIDE allows tests to inject without gh.
if [ -z "$BASE" ]; then
    if [ -n "${PR_TARGET_GUARD_DEFAULT_BRANCH_OVERRIDE:-}" ]; then
        BASE="$PR_TARGET_GUARD_DEFAULT_BRANCH_OVERRIDE"
    else
        REPO=$(echo "$CMD" | sed -nE "s/.*--repo[= ][\"']?([a-zA-Z0-9._/-]+).*/\1/p" | head -1)
        if [ -z "$REPO" ]; then
            REPO=$(echo "$CMD" | sed -nE "s/.*-R[[:space:]]+[\"']?([a-zA-Z0-9._/-]+).*/\1/p" | head -1)
        fi
        if [ -n "$REPO" ]; then
            BASE=$(gh api "repos/$REPO" --jq .default_branch 2>/dev/null || true)
        else
            BASE=$(gh api 'repos/{owner}/{repo}' --jq .default_branch 2>/dev/null || true)
        fi
    fi
    # Graceful degradation: preserve historical allow if we cannot resolve.
    if [ -z "$BASE" ]; then
        allow_response
    fi
fi

# Strip surrounding quotes if present
BASE=$(echo "$BASE" | sed -E "s/^[\"']//;s/[\"']$//")

# Only block if base is exactly 'main' or 'master'.
if [ "$BASE" != "main" ] && [ "$BASE" != "master" ]; then
    allow_response
fi

# Base is 'main' or 'master' — check if this is a release PR (--head develop or release/*)
HEAD=$(echo "$CMD" | sed -nE "s/.*(--head[= ])[\"']?([a-zA-Z0-9._/-]+).*/\2/p" | head -1)
if [ -z "$HEAD" ]; then
    HEAD=$(echo "$CMD" | sed -nE "s/.*-H[[:space:]]*[\"']?([a-zA-Z0-9._/-]+).*/\1/p" | head -1)
fi
HEAD=$(echo "$HEAD" | sed -E "s/^[\"']//;s/[\"']$//")

# Allow release PRs: develop → main/master or release/* → main/master
# (matches .github/workflows/validate-pr-target.yml server-side policy)
if [ "$HEAD" = "develop" ]; then
    allow_response
fi
case "$HEAD" in
    release/*)
        allow_response
        ;;
esac

# Deny: non-develop/non-release branch targeting main or master
deny_response "PR targeting '${BASE}' is blocked by branching policy. Only 'develop' or 'release/*' branches may merge into '${BASE}'. Feature/fix branches must target 'develop'."
