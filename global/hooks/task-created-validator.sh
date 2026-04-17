#!/usr/bin/env bash
# task-created-validator.sh
# Validates task quality at creation time.
# Hook Type: TaskCreated (sync, blocking)
# Exit codes: 0 = approve, 2 = block (stderr message shown to model)
#
# Rules:
#   1. description must be >= 20 characters (after trim)
#   2. description must contain at least one "- [ ]" markdown checkbox

set -uo pipefail

INPUT=$(cat)

# Empty input: fail open — nothing to validate.
if [ -z "$INPUT" ]; then
    exit 0
fi

# Extract description. Try common field paths used by TaskCreate.
DESC=""
if command -v jq >/dev/null 2>&1; then
    DESC=$(printf '%s' "$INPUT" | jq -r '
        .tool_input.description //
        .description //
        .task.description //
        empty
    ' 2>/dev/null) || DESC=""
elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    PY=$(command -v python3 || command -v python)
    DESC=$(printf '%s' "$INPUT" | "$PY" -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for path in (("tool_input","description"), ("description",), ("task","description")):
    cur = d
    ok = True
    for key in path:
        if isinstance(cur, dict) and key in cur:
            cur = cur[key]
        else:
            ok = False
            break
    if ok and isinstance(cur, str):
        sys.stdout.write(cur)
        break
' 2>/dev/null) || DESC=""
else
    # No JSON parser available — fail open rather than block legitimate tasks.
    exit 0
fi

# Trim whitespace
TRIMMED=$(printf '%s' "$DESC" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# Rule 1: minimum length
LEN=${#TRIMMED}
if [ "$LEN" -lt 20 ]; then
    echo "TaskCreated rejected: description must be at least 20 characters (got ${LEN}). Add scope, context, and acceptance criteria." >&2
    exit 2
fi

# Rule 2: must contain at least one checkbox marker
if ! printf '%s' "$DESC" | grep -qE '\- \[ \]'; then
    echo "TaskCreated rejected: description must contain at least one '- [ ]' checkbox marker for acceptance criteria." >&2
    exit 2
fi

exit 0
