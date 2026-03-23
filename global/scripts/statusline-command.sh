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
