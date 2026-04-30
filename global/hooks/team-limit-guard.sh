#!/bin/bash
# team-limit-guard.sh
# Limits the maximum number of concurrent Agent Teams
# Hook Type: PreToolUse (TeamCreate)
# Exit codes: 0 (always — decision is in JSON)
# Response format: hookSpecificOutput with hookEventName
#
# NOTE on matcher stability: this hook is registered with
# "matcher": "TeamCreate" in settings.json (lines 203-212). The official
# PreToolUse matcher contract expects a tool name, but TeamCreate is not
# explicitly listed in the public Claude Code tool catalog at
# https://code.claude.com/docs/en/hooks. Its semantic stability across
# Claude Code versions is therefore uncertain — the matcher could be
# renamed, reclassified, or silently dropped without a deprecation cycle.
# Re-verify the matcher semantics on every Claude Code version bump and
# update the settings.json registration if the contract changes.

# Read input from stdin (Claude Code passes JSON via stdin)
# This hook doesn't need the input data — just consume stdin to avoid SIGPIPE
cat > /dev/null

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
