#!/bin/bash
# Statusline: ccstatusline handles all display including usage data
#
# Requirements:
#   npm install -g ccstatusline
#
# Usage in settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "~/.claude/scripts/statusline-command.sh"
#   }

# Detect terminal width for ccstatusline (tput cols reads COLUMNS env var)
# Without this, piped context causes tput to return 80 → effective width 40
if [ -z "$COLUMNS" ] || [ "$COLUMNS" -le 0 ] 2>/dev/null; then
    _W=$(stty size < /dev/tty 2>/dev/null | awk '{print $2}')
    if [ -z "$_W" ] || [ "$_W" -le 0 ] 2>/dev/null; then
        _P=$PPID
        while [ -n "$_P" ] && [ "$_P" -gt 1 ]; do
            _T=$(ps -o tty= -p "$_P" 2>/dev/null | tr -d ' ')
            if [ -n "$_T" ] && [ "$_T" != "??" ] && [ "$_T" != "?" ]; then
                _W=$(stty size < "/dev/$_T" 2>/dev/null | awk '{print $2}')
                [ -n "$_W" ] && [ "$_W" -gt 0 ] 2>/dev/null && break
            fi
            _P=$(ps -o ppid= -p "$_P" 2>/dev/null | tr -d ' ')
        done
    fi
    [ -n "$_W" ] && [ "$_W" -gt 0 ] 2>/dev/null && export COLUMNS="$_W"
fi

# Read stdin once and store it
INPUT=$(cat)

# Get ccstatusline output (pass stdin)
if command -v ccstatusline &> /dev/null; then
    echo "$INPUT" | ccstatusline 2>/dev/null
    CCSL_CMD="ccstatusline"
else
    echo "$INPUT" | npx ccstatusline@latest 2>/dev/null
    CCSL_CMD="npx ccstatusline@latest"
fi

# ccstatusline takes a "rate_limits shortcut": when Claude Code's stdin includes
# rate_limits, it skips the OAuth usage API call entirely. That means the cache
# file usage.json (which holds extraUsage* fields) never gets refreshed, and the
# Extra line below shows hours-old data while the rest of the bar stays fresh.
# Fix: when usage.json is older than ccstatusline's CACHE_MAX_AGE (180s), kick
# off a background ccstatusline run with rate_limits stripped from stdin to
# force fetchUsageData(). The next status bar refresh picks up the fresh file.
USAGE_CACHE="$HOME/.cache/ccstatusline/usage.json"
USAGE_CACHE_TTL=180
if command -v jq &> /dev/null; then
    needs_refresh=1
    if [ -f "$USAGE_CACHE" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            cache_mtime=$(stat -f '%m' "$USAGE_CACHE" 2>/dev/null || echo 0)
        else
            cache_mtime=$(stat -c '%Y' "$USAGE_CACHE" 2>/dev/null || echo 0)
        fi
        cache_age=$(( $(date +%s) - cache_mtime ))
        [ "$cache_age" -lt "$USAGE_CACHE_TTL" ] && needs_refresh=0
    fi
    if [ "$needs_refresh" -eq 1 ]; then
        ( echo "$INPUT" | jq -c 'del(.rate_limits)' 2>/dev/null \
            | $CCSL_CMD >/dev/null 2>&1 ) &
        disown 2>/dev/null || true
    fi
fi

# Append extra usage line from ccstatusline cache
if [ -f "$USAGE_CACHE" ] && command -v jq &> /dev/null; then
    enabled=$(jq -r '.extraUsageEnabled // false' "$USAGE_CACHE" 2>/dev/null)
    if [ "$enabled" = "true" ]; then
        limit=$(jq -r '.extraUsageLimit // 0' "$USAGE_CACHE" 2>/dev/null)
        used=$(jq -r '.extraUsageUsed // 0' "$USAGE_CACHE" 2>/dev/null)
        util=$(jq -r '.extraUsageUtilization // 0' "$USAGE_CACHE" 2>/dev/null)

        # Convert cents to dollars
        limit_usd=$(awk "BEGIN {printf \"%.0f\", $limit / 100}")
        used_usd=$(awk "BEGIN {printf \"%.2f\", $used / 100}")
        remain_usd=$(awk "BEGIN {printf \"%.2f\", ($limit - $used) / 100}")
        remain_pct=$(awk "BEGIN {printf \"%.0f\", 100 - $util}")

        # ANSI colors: green if >50% remain, yellow if >20%, red otherwise
        if [ "$remain_pct" -gt 50 ] 2>/dev/null; then
            color="\033[32m"
        elif [ "$remain_pct" -gt 20 ] 2>/dev/null; then
            color="\033[33m"
        else
            color="\033[31m"
        fi
        reset="\033[0m"

        printf "${color}Extra: \$%s/\$%s (%s%%)${reset} | ${color}Remain: \$%s${reset}\n" \
            "$used_usd" "$limit_usd" "$remain_pct" "$remain_usd"
    fi
fi
