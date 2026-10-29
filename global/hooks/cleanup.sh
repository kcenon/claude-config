#!/bin/bash
# cleanup.sh
# Cleans up temporary files created during session
# Hook Type: SessionEnd
# Exit codes: 0=success
# Response format: none (lifecycle event, no JSON output needed)

set -euo pipefail

# Clean up temporary Claude files (older than 60 minutes).
# `find` errors (missing dir, permission) are best-effort; never block teardown.
find "${TMPDIR:-/tmp}" -maxdepth 1 -name "claude_*" -mmin +60 -delete 2>/dev/null || true
find "${TMPDIR:-/tmp}" -maxdepth 1 -name "tmp.*" -user "$(whoami)" -mmin +60 -delete 2>/dev/null || true

# No log rotation here: the loggers whose logs this hook used to rotate were
# removed by #964, and the hooks that still log rotate their own files. Logs
# the removed loggers left behind are deliberately not touched.

exit 0
