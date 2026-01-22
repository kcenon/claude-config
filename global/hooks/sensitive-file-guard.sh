#!/bin/bash
# sensitive-file-guard.sh
# Blocks access to sensitive files
# Hook Type: PreToolUse (Edit|Write|Read)
# Exit codes: 0=allow, 2=block

FILE="${CLAUDE_FILE_PATH:-}"

# Skip if no file path provided
if [ -z "$FILE" ]; then
    exit 0
fi

# Check sensitive file extensions
if echo "$FILE" | grep -qE '\.(env|pem|key|p12|pfx)$'; then
    echo "[BLOCKED] Sensitive file access blocked: $FILE" >&2
    exit 2
fi

# Check sensitive directories
if echo "$FILE" | grep -qiE '(secrets|credentials|passwords|private)[/\\]'; then
    echo "[BLOCKED] Sensitive directory access blocked: $FILE" >&2
    exit 2
fi

exit 0
