#!/bin/bash
# team-report.sh — Team activity summary
# Usage: bash team-report.sh [days]
# Reads plain-text logs from ~/.claude/ and outputs a summary report.

DAYS="${1:-7}"

SESSION_LOG="${HOME}/.claude/session.log"
SUBAGENT_LOG="${HOME}/.claude/logs/subagents.log"
TASK_LOG="${HOME}/.claude/logs/tasks.log"
TOOL_FAIL_LOG="${HOME}/.claude/logs/tool-failures.log"

# Compute cutoff date (YYYY-MM-DD)
if date --version >/dev/null 2>&1; then
    # GNU date
    CUTOFF=$(date -d "-${DAYS} days" +"%Y-%m-%d")
else
    # macOS date
    CUTOFF=$(date -j -v-"${DAYS}"d +"%Y-%m-%d")
fi

# --- Helper: filter lines with [YYYY-MM-DD HH:MM:SS] prefix by date ---
filter_bracketed() {
    local file="$1"
    [ -f "$file" ] || return
    awk -v cutoff="$CUTOFF" '{
        # Extract date from [YYYY-MM-DD ...]
        if (match($0, /\[([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])/)) {
            d = substr($0, RSTART+1, 10)
            if (d >= cutoff) print
        }
    }' "$file"
}

# --- Helper: filter session.log lines (date after colon) ---
filter_session() {
    local file="$1"
    [ -f "$file" ] || return
    awk -v cutoff="$CUTOFF" '{
        # Extract date from ": YYYY-MM-DD"
        if (match($0, /: ([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])/)) {
            d = substr($0, RSTART+2, 10)
            if (d >= cutoff) print
        }
    }' "$file"
}

# --- Helper: filter tool-failures.log (multi-line blocks) ---
filter_tool_failures() {
    local file="$1"
    [ -f "$file" ] || return
    awk -v cutoff="$CUTOFF" '
        /^=== Tool Failure at / {
            if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) {
                d = substr($0, RSTART, 10)
                in_range = (d >= cutoff)
            }
        }
        in_range { print }
    ' "$file"
}

echo "========================================"
echo "  Team Activity Report"
echo "  Period: ${CUTOFF} ~ $(date +%Y-%m-%d) (${DAYS} days)"
echo "========================================"
echo ""

# --- Sessions ---
echo "--- Sessions ---"
if [ -f "$SESSION_LOG" ]; then
    STARTED=$(filter_session "$SESSION_LOG" | grep -c "session started")
    ENDED=$(filter_session "$SESSION_LOG" | grep -c "session ended")
    echo "  Started : ${STARTED}"
    echo "  Ended   : ${ENDED}"
else
    echo "  (no session log found)"
fi
echo ""

# --- Subagents ---
echo "--- Subagent Starts (by type) ---"
if [ -f "$SUBAGENT_LOG" ]; then
    SUBAGENT_DATA=$(filter_bracketed "$SUBAGENT_LOG" | grep "Subagent start")
    if [ -n "$SUBAGENT_DATA" ]; then
        echo "$SUBAGENT_DATA" | sed 's/.*Subagent start[: -]* *//' | sort | uniq -c | sort -rn | while read -r count name; do
            printf "  %-20s %d\n" "$name" "$count"
        done
    else
        echo "  (none in period)"
    fi
else
    echo "  (no subagent log found)"
fi
echo ""

# --- Task Completions ---
echo "--- Task Completions ---"
if [ -f "$TASK_LOG" ]; then
    TASK_COUNT=$(filter_bracketed "$TASK_LOG" | grep -c "Task #.*completed")
    echo "  Completed : ${TASK_COUNT}"
else
    echo "  (no task log found)"
fi
echo ""

# --- Tool Failures ---
echo "--- Tool Failures (by tool) ---"
if [ -f "$TOOL_FAIL_LOG" ]; then
    FAIL_DATA=$(filter_tool_failures "$TOOL_FAIL_LOG" | grep "^Tool: " | sed 's/^Tool: //')
    if [ -n "$FAIL_DATA" ]; then
        TOTAL=$(echo "$FAIL_DATA" | wc -l | tr -d ' ')
        echo "  Total: ${TOTAL}"
        echo "$FAIL_DATA" | sort | uniq -c | sort -rn | while read -r count name; do
            printf "  %-20s %d\n" "$name" "$count"
        done
    else
        echo "  (none in period)"
    fi
else
    echo "  (no tool-failure log found)"
fi
echo ""
echo "========================================"
