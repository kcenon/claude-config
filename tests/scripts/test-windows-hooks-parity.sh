#!/bin/bash
# Regression test for hook parity between global/settings.json and
# global/settings.windows.json (issue #421). Extracts every
# (event, matcher, hook-script-basename) tuple from each file and
# asserts the sets are equal.
#
# Run: bash tests/scripts/test-windows-hooks-parity.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

UNIX_JSON="global/settings.json"
WIN_JSON="global/settings.windows.json"

if [ ! -f "$UNIX_JSON" ] || [ ! -f "$WIN_JSON" ]; then
    echo "FAIL: settings files missing" >&2
    exit 1
fi

PYTHON=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "SKIP: python3/python not in PATH"
    exit 0
fi

# Build the set of (event, matcher, basename) tuples per file and diff.
DIFF=$("$PYTHON" - <<'PY' "$UNIX_JSON" "$WIN_JSON"
import json, os, re, sys

def extract(path):
    with open(path) as f:
        data = json.load(f)
    tuples = set()
    for event, blocks in (data.get("hooks") or {}).items():
        for block in blocks or []:
            matcher = block.get("matcher", "")
            for hook in block.get("hooks") or []:
                cmd = hook.get("command", "")
                # Pull every basename ending in .sh or .ps1 from the
                # command string (handles compound commands that chain
                # multiple scripts).
                for m in re.finditer(r'([A-Za-z0-9_.-]+?)\.(?:sh|ps1)', cmd):
                    base = m.group(1)
                    # Collapse common pairs: session-logger.sh start vs
                    # session-logger.ps1 start — strip trailing args by
                    # basename alone.
                    tuples.add((event, matcher, base))
    return tuples

unix_set = extract(sys.argv[1])
win_set  = extract(sys.argv[2])

only_unix = sorted(unix_set - win_set)
only_win  = sorted(win_set - unix_set)

if only_unix or only_win:
    for t in only_unix:
        print(f"only in {os.path.basename(sys.argv[1])}: {t}")
    for t in only_win:
        print(f"only in {os.path.basename(sys.argv[2])}: {t}")
    sys.exit(1)
PY
)
STATUS=$?

if [ $STATUS -ne 0 ]; then
    echo "FAIL: hook parity drift between settings.json and settings.windows.json"
    echo ""
    echo "$DIFF"
    exit 1
fi

echo "PASS: hook parity between settings.json and settings.windows.json"
