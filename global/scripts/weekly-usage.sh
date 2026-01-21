#!/bin/bash
# Weekly Usage Script for Claude Code Statusline
# Reads stats-cache.json and calculates weekly usage statistics

STATS_FILE="$HOME/.claude/stats-cache.json"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "W:N/A"
    exit 0
fi

# Check if stats file exists
if [ ! -f "$STATS_FILE" ]; then
    echo "W:N/A"
    exit 0
fi

# Get current date info
TODAY=$(date +%Y-%m-%d)
DAY_OF_WEEK=$(date +%u)  # 1=Monday, 7=Sunday

# Calculate days since Monday (week start)
DAYS_SINCE_MONDAY=$((DAY_OF_WEEK - 1))

# Calculate week start date (Monday)
if [[ "$OSTYPE" == "darwin"* ]]; then
    WEEK_START=$(date -v-${DAYS_SINCE_MONDAY}d +%Y-%m-%d)
else
    WEEK_START=$(date -d "$TODAY - $DAYS_SINCE_MONDAY days" +%Y-%m-%d)
fi

# Extract weekly message count from stats-cache.json
WEEKLY_MESSAGES=$(jq -r --arg start "$WEEK_START" '
    .dailyActivity
    | map(select(.date >= $start))
    | map(.messageCount)
    | add // 0
' "$STATS_FILE" 2>/dev/null)

# Extract weekly token count
WEEKLY_TOKENS=$(jq -r --arg start "$WEEK_START" '
    .dailyModelTokens
    | map(select(.date >= $start))
    | map(.tokensByModel | to_entries | map(.value) | add)
    | add // 0
' "$STATS_FILE" 2>/dev/null)

# Handle null/empty values
WEEKLY_MESSAGES=${WEEKLY_MESSAGES:-0}
WEEKLY_TOKENS=${WEEKLY_TOKENS:-0}

# Calculate days remaining until next Monday
DAYS_REMAINING=$((7 - DAY_OF_WEEK))
if [ $DAYS_REMAINING -eq 7 ]; then
    DAYS_REMAINING=0
fi

# Format message count (K)
if [ "$WEEKLY_MESSAGES" -ge 1000 ]; then
    MSG_DISPLAY=$(echo "scale=1; $WEEKLY_MESSAGES / 1000" | bc)K
else
    MSG_DISPLAY=$WEEKLY_MESSAGES
fi

# Format token count (K or M)
if [ "$WEEKLY_TOKENS" -ge 1000000 ]; then
    TOKEN_DISPLAY=$(echo "scale=1; $WEEKLY_TOKENS / 1000000" | bc)M
elif [ "$WEEKLY_TOKENS" -ge 1000 ]; then
    TOKEN_DISPLAY=$(echo "scale=0; $WEEKLY_TOKENS / 1000" | bc)K
else
    TOKEN_DISPLAY=$WEEKLY_TOKENS
fi

# Output format: Week Reset in Xd | Msgs | Tokens
# Example: W:3d 35.7K/1.3M
echo "W:${DAYS_REMAINING}d ${MSG_DISPLAY}/${TOKEN_DISPLAY}"
