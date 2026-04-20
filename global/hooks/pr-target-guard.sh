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

# Helper function for deny response
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

# Helper function for allow response
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

# Read input from stdin (Claude Code passes JSON via stdin)
INPUT=$(cat)

# Fail-closed: deny if stdin is empty or missing
if [ -z "$INPUT" ]; then
    deny_response "Failed to parse hook input — denying for safety (fail-closed)"
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Fail-closed: deny if jq parsing failed
if [ $? -ne 0 ]; then
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

# If no --base flag found, the PR uses the repo default branch (develop).
# Allow it — this is the normal feature-to-develop workflow.
if [ -z "$BASE" ]; then
    allow_response
fi

# Strip surrounding quotes if present
BASE=$(echo "$BASE" | sed -E "s/^[\"']//;s/[\"']$//")

# Only block if base is exactly 'main' (not 'main-backup', 'maintain', etc.)
if [ "$BASE" != "main" ]; then
    allow_response
fi

# Base is 'main' — check if this is a release PR (--head develop or release/*)
HEAD=$(echo "$CMD" | sed -nE "s/.*(--head[= ])[\"']?([a-zA-Z0-9._/-]+).*/\2/p" | head -1)
if [ -z "$HEAD" ]; then
    HEAD=$(echo "$CMD" | sed -nE "s/.*-H[[:space:]]*[\"']?([a-zA-Z0-9._/-]+).*/\1/p" | head -1)
fi
HEAD=$(echo "$HEAD" | sed -E "s/^[\"']//;s/[\"']$//")

# Allow release PRs: develop → main or release/* → main
# (matches .github/workflows/validate-pr-target.yml server-side policy)
if [ "$HEAD" = "develop" ]; then
    allow_response
fi
case "$HEAD" in
    release/*)
        allow_response
        ;;
esac

# Deny: non-develop/non-release branch targeting main
deny_response "PR targeting 'main' is blocked by branching policy. Only 'develop' or 'release/*' branches may merge into 'main'. Feature/fix branches must target 'develop'."
