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

# Read stdin once and store it
INPUT=$(cat)

# Get ccstatusline output (pass stdin)
if command -v ccstatusline &> /dev/null; then
    echo "$INPUT" | ccstatusline 2>/dev/null
else
    echo "$INPUT" | npx ccstatusline@latest 2>/dev/null
fi

# Append extra usage line from ccstatusline cache
USAGE_CACHE="$HOME/.cache/ccstatusline/usage.json"
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
