#!/bin/bash
# dangerous-command-guard.sh
# Blocks dangerous bash commands
# Hook Type: PreToolUse (Bash)
# Exit codes: 0=allow, 2=block

CMD="${CLAUDE_TOOL_INPUT:-}"

# Block recursive delete at root
if echo "$CMD" | grep -qE 'rm\s+(-rf|--recursive)\s+/($|[^a-zA-Z])'; then
    echo "[BLOCKED] Dangerous delete command blocked" >&2
    exit 2
fi

# Block dangerous chmod
if echo "$CMD" | grep -qE 'chmod\s+(777|a\+rwx)'; then
    echo "[BLOCKED] Dangerous permission change blocked" >&2
    exit 2
fi

# Block remote script execution
if echo "$CMD" | grep -qE '(curl|wget).*\|.*sh'; then
    echo "[BLOCKED] Remote script execution blocked" >&2
    exit 2
fi

exit 0
