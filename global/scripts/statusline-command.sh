#!/bin/bash
# Combined statusline: ccstatusline + claude-limitline weekly usage
# This script combines ccstatusline output with real-time weekly usage from Anthropic API

# Read stdin once and store it
INPUT=$(cat)

# Get ccstatusline output (pass stdin)
# Try global npm first, then npx
if command -v ccstatusline &> /dev/null; then
    CCSTATUS=$(echo "$INPUT" | ccstatusline 2>/dev/null)
else
    CCSTATUS=$(echo "$INPUT" | npx ccstatusline@latest 2>/dev/null)
fi

# Get claude-limitline output for weekly usage (pass stdin)
# Requires: npm install -g claude-limitline
if command -v claude-limitline &> /dev/null; then
    LIMITLINE=$(echo "$INPUT" | claude-limitline 2>/dev/null)
else
    LIMITLINE=""
fi

# Extract weekly usage from claude-limitline output
# Format: ○ 80% (wk 92%) - means 80% used, week is 92% through
WEEKLY_USAGE=$(echo "$LIMITLINE" | grep -oE '○ [0-9]+%' | head -1)

# Output ccstatusline (3 lines)
echo "$CCSTATUS"

# Add weekly usage as 4th line if available
if [ -n "$WEEKLY_USAGE" ]; then
    # Extract percentage
    PCT=$(echo "$WEEKLY_USAGE" | grep -oE '[0-9]+')

    # Color based on usage: green < 50%, yellow 50-80%, red > 80%
    if [ "$PCT" -lt 50 ]; then
        COLOR="32"  # green
    elif [ "$PCT" -lt 80 ]; then
        COLOR="33"  # yellow
    else
        COLOR="31"  # red
    fi

    printf "\033[${COLOR}mWeekly Limit: %s%% used\033[0m\n" "$PCT"
fi
