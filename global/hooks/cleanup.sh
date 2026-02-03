#!/bin/bash
# cleanup.sh
# Cleans up temporary files created during session
# Hook Type: SessionEnd
# Exit codes: 0=success
# Response format: hookSpecificOutput (modern format)

# Clean up temporary Claude files (older than 60 minutes)
find /tmp -maxdepth 1 -name "claude_*" -mmin +60 -delete 2>/dev/null
find /tmp -maxdepth 1 -name "tmp.*" -user "$(whoami)" -mmin +60 -delete 2>/dev/null

# Output modern response format
cat <<EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
EOF
exit 0
