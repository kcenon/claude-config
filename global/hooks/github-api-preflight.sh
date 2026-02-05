#!/bin/bash
# github-api-preflight.sh
# Checks GitHub API connectivity before executing GitHub-related commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0=allow (always, warning only)
# Response format: hookSpecificOutput (modern format)

CMD="${CLAUDE_TOOL_INPUT:-}"

# Only check GitHub-related commands
if ! echo "$CMD" | grep -qE '(gh |github\.com|api\.github\.com)'; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
EOF
    exit 0
fi

# Test GitHub API connectivity with short timeout
HTTP_CODE=$(curl -s --connect-timeout 3 -o /dev/null -w "%{http_code}" https://api.github.com/zen 2>/dev/null)
CURL_EXIT=$?

if [ "$CURL_EXIT" -ne 0 ] || [ "$HTTP_CODE" = "000" ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "allow",
    "message": "GitHub API may be unreachable (sandbox/TLS issue detected). Suggestions: Use local git operations if possible, check network/certificate settings, consider /sandbox to manage restrictions."
  }
}
EOF
    exit 0
fi

# Check GitHub CLI auth status for gh commands
if echo "$CMD" | grep -qE '^gh '; then
    if ! gh auth status >/dev/null 2>&1; then
        cat <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "allow",
    "message": "GitHub CLI not authenticated. Run 'gh auth login' or 'gh auth status' to check."
  }
}
EOF
        exit 0
    fi
fi

# All checks passed
cat <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
EOF
exit 0
