#!/bin/bash
# team-limit-guard.sh
# Limits the maximum number of concurrent Agent Teams
# Hook Type: PreToolUse (TeamCreate)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName

# Read input from stdin (Claude Code passes JSON via stdin)
INPUT=$(cat)

# Configurable limit via environment variable (default: 3)
MAX_TEAMS="${MAX_TEAMS:-3}"
TEAMS_DIR="$HOME/.claude/teams"

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

# Skip check if teams directory does not exist
if [ ! -d "$TEAMS_DIR" ]; then
    allow_response
fi

# Count existing team directories
CURRENT_TEAMS=$(find "$TEAMS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

# Block if limit reached
if [ "$CURRENT_TEAMS" -ge "$MAX_TEAMS" ]; then
    deny_response "Team limit reached ($CURRENT_TEAMS/$MAX_TEAMS). Delete unused teams with TeamDelete before creating new ones."
fi

# Allow team creation
allow_response
