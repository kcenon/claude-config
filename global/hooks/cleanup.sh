#!/bin/bash
# cleanup.sh
# Cleans up temporary files created during session
# Hook Type: SessionEnd
# Exit codes: 0=success

# Clean up temporary Claude files (older than 60 minutes)
find /tmp -maxdepth 1 -name "claude_*" -mmin +60 -delete 2>/dev/null
find /tmp -maxdepth 1 -name "tmp.*" -user "$(whoami)" -mmin +60 -delete 2>/dev/null

exit 0
