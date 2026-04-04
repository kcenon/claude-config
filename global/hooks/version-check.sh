#!/bin/bash
# version-check.sh
# Checks Claude Code version against known problematic versions
# Hook Type: SessionStart
# Usage: Called automatically on session start
# Response format: none (lifecycle event, no JSON output needed)
#
# Known cache efficiency bugs:
# - Resume cache regression: https://github.com/anthropics/claude-code/issues/34629
# - Sentinel replacement: https://github.com/anthropics/claude-code/issues/40524

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KNOWN_ISSUES_JSON="${SCRIPT_DIR}/known-issues.json"
LOG_FILE="${HOME}/.claude/session.log"

# Hardcoded fallback if JSON or jq unavailable
FALLBACK_VERSIONS="2.1.69 2.1.70 2.1.71 2.1.72 2.1.73 2.1.74 2.1.75 2.1.76 2.1.77 2.1.78 2.1.79 2.1.80 2.1.81"

# Get Claude Code version
CC_VERSION=""
if command -v claude >/dev/null 2>&1; then
    CC_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi

if [ -z "$CC_VERSION" ]; then
    exit 0
fi

# Load known problematic versions from JSON (prefer) or fallback
KNOWN_CACHE_BUG_VERSIONS=""
if [ -f "$KNOWN_ISSUES_JSON" ] && command -v jq >/dev/null 2>&1; then
    KNOWN_CACHE_BUG_VERSIONS=$(jq -r '.known_issues[].version_list[]' "$KNOWN_ISSUES_JSON" 2>/dev/null | tr '\n' ' ')
fi
if [ -z "$KNOWN_CACHE_BUG_VERSIONS" ]; then
    KNOWN_CACHE_BUG_VERSIONS="$FALLBACK_VERSIONS"
fi

# Check against known problematic versions
for v in $KNOWN_CACHE_BUG_VERSIONS; do
    if [ "$CC_VERSION" = "$v" ]; then
        TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[VersionCheck] WARNING: Claude Code v${CC_VERSION} has known cache bugs (resume cache regression, sentinel replacement). See: https://github.com/anthropics/claude-code/issues/34629 — $TIMESTAMP" >> "$LOG_FILE" 2>/dev/null
        break
    fi
done

exit 0
