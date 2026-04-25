#!/bin/bash
# github-api-preflight.sh
# Checks GitHub API connectivity before executing GitHub-related commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0 (always — decision is in JSON, warning only)
# Response format: hookSpecificOutput with hookEventName

# Read input from stdin (Claude Code passes JSON via stdin)
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
# Fallback to environment variable for backward compatibility
if [ -z "$CMD" ]; then
    CMD="${CLAUDE_TOOL_INPUT:-}"
fi

# Helper function for allow response
allow_response() {
    local message="${1:-}"
    if [ -n "$message" ]; then
        cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "$message"
  }
}
EOF
    else
        cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
    fi
    exit 0
}

# Only check GitHub-related commands
if ! echo "$CMD" | grep -qE '(gh |github\.com|api\.github\.com)'; then
    allow_response
fi

# Test GitHub API connectivity with short timeout
HTTP_CODE=$(curl -s --connect-timeout 3 -o /dev/null -w "%{http_code}" https://api.github.com/zen 2>/dev/null)
CURL_EXIT=$?

if [ "$CURL_EXIT" -ne 0 ] || [ "$HTTP_CODE" = "000" ]; then
    allow_response "GitHub API may be unreachable (sandbox/TLS issue detected). Suggestions: Use local git operations if possible, check network/certificate settings, consider /sandbox to manage restrictions."
fi

# Check GitHub CLI auth status for gh commands.
# When GH_TOKEN or GITHUB_TOKEN is set, gh CLI uses that token directly and
# `gh auth status` may still report failure (e.g. empty keyring in containers,
# CI runners, or sandboxed envs). Token-based auth works regardless, so skip
# the keyring check in that case to avoid false-positive warnings.
if echo "$CMD" | grep -qE '^gh '; then
    if [ -z "$GH_TOKEN" ] && [ -z "$GITHUB_TOKEN" ]; then
        if ! gh auth status >/dev/null 2>&1; then
            allow_response "GitHub CLI not authenticated. Run 'gh auth login' or 'gh auth status' to check."
        fi
    fi
fi

# All checks passed
allow_response
