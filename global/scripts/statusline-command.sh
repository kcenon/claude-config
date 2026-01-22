#!/bin/bash
# Combined statusline: ccstatusline + claude-limitline usage info
# Displays: Session usage (resets at midnight), Weekly usage (resets Thu 5pm KST)
#
# Requirements:
#   npm install -g ccstatusline claude-limitline
#
# Usage in settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "~/.claude/statusline-command.sh"
#   }

# Read stdin once and store it
INPUT=$(cat)

# Get ccstatusline output (pass stdin)
if command -v ccstatusline &> /dev/null; then
    CCSTATUS=$(echo "$INPUT" | ccstatusline 2>/dev/null)
else
    CCSTATUS=$(echo "$INPUT" | npx ccstatusline@latest 2>/dev/null)
fi

# Get claude-limitline output (pass stdin)
if command -v claude-limitline &> /dev/null; then
    LIMITLINE=$(echo "$INPUT" | claude-limitline 2>/dev/null)
else
    LIMITLINE=""
fi

# Strip ANSI codes for parsing
LIMITLINE_CLEAN=$(echo "$LIMITLINE" | sed 's/\x1b\[[0-9;]*m//g')

# Extract session usage: ◫ XX%
SESSION_USAGE=$(echo "$LIMITLINE_CLEAN" | grep -oE '◫ [0-9]+%' | grep -oE '[0-9]+')

# Extract weekly usage: ○ XX%
WEEKLY_USAGE=$(echo "$LIMITLINE_CLEAN" | grep -oE '○ [0-9]+%' | grep -oE '[0-9]+')

# Color function based on percentage
get_color() {
    local pct=$1
    if [ "$pct" -lt 50 ]; then
        echo "32"  # green
    elif [ "$pct" -lt 80 ]; then
        echo "33"  # yellow
    else
        echo "31"  # red
    fi
}

# Calculate time until midnight (session reset) in Asia/Seoul
calc_session_reset() {
    # Get current time in Asia/Seoul
    local now=$(TZ='Asia/Seoul' date +%s)
    # Get midnight tonight in Asia/Seoul
    local midnight=$(TZ='Asia/Seoul' date -v+1d -j -f "%Y-%m-%d %H:%M:%S" "$(TZ='Asia/Seoul' date +%Y-%m-%d) 00:00:00" +%s 2>/dev/null)

    # Fallback for Linux
    if [ -z "$midnight" ]; then
        midnight=$(TZ='Asia/Seoul' date -d "$(TZ='Asia/Seoul' date +%Y-%m-%d) + 1 day" +%s 2>/dev/null)
    fi

    if [ -n "$midnight" ]; then
        local diff=$((midnight - now))
        local hours=$((diff / 3600))
        local mins=$(((diff % 3600) / 60))

        if [ "$hours" -gt 0 ]; then
            echo "${hours}h ${mins}m"
        else
            echo "${mins}m"
        fi
    else
        echo "midnight"
    fi
}

# Calculate time until weekly reset (Thursday 5pm KST)
calc_weekly_reset() {
    # Get current timestamp
    local now=$(date +%s)

    # Find next Thursday 5pm KST
    # Day of week: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun
    local current_dow=$(TZ='Asia/Seoul' date +%u)
    local current_hour=$(TZ='Asia/Seoul' date +%H)

    # Days until Thursday (4)
    local days_until_reset=$(( (4 - current_dow + 7) % 7 ))

    # If today is Thursday, check if we're past 5pm
    if [ "$days_until_reset" -eq 0 ]; then
        if [ "$current_hour" -ge 17 ]; then
            days_until_reset=7
        fi
    fi

    # Calculate target timestamp
    local target_date=$(TZ='Asia/Seoul' date -v+${days_until_reset}d +%Y-%m-%d 2>/dev/null)
    if [ -z "$target_date" ]; then
        # Linux fallback
        target_date=$(TZ='Asia/Seoul' date -d "+${days_until_reset} days" +%Y-%m-%d 2>/dev/null)
    fi

    local target_ts=$(TZ='Asia/Seoul' date -j -f "%Y-%m-%d %H:%M:%S" "${target_date} 17:00:00" +%s 2>/dev/null)
    if [ -z "$target_ts" ]; then
        # Linux fallback
        target_ts=$(TZ='Asia/Seoul' date -d "${target_date} 17:00:00" +%s 2>/dev/null)
    fi

    if [ -n "$target_ts" ]; then
        local diff=$((target_ts - now))
        local days=$((diff / 86400))
        local hours=$(((diff % 86400) / 3600))

        if [ "$days" -gt 0 ]; then
            echo "${days}d ${hours}h"
        else
            echo "${hours}h"
        fi
    else
        echo "Thu 5pm"
    fi
}

# Output ccstatusline first
echo "$CCSTATUS"

# Build usage line
OUTPUT=""

# Session usage with reset time (midnight KST)
if [ -n "$SESSION_USAGE" ]; then
    COLOR=$(get_color "$SESSION_USAGE")
    RESET_TIME=$(calc_session_reset)
    OUTPUT+="\033[${COLOR}mSession: ${SESSION_USAGE}%\033[0m \033[36m(resets in ${RESET_TIME})\033[0m"
fi

# Weekly usage with reset time (Thu 5pm KST)
if [ -n "$WEEKLY_USAGE" ]; then
    COLOR=$(get_color "$WEEKLY_USAGE")
    if [ -n "$OUTPUT" ]; then
        OUTPUT+=" | "
    fi
    RESET_TIME=$(calc_weekly_reset)
    OUTPUT+="\033[${COLOR}mWeekly: ${WEEKLY_USAGE}%\033[0m \033[36m(resets in ${RESET_TIME})\033[0m"
fi

# Print combined output
if [ -n "$OUTPUT" ]; then
    echo -e "${OUTPUT}"
fi
