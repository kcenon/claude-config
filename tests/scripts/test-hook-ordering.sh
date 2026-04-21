#!/bin/bash
# Regression test for issue #424: the PreToolUse Edit|Write|Read matcher
# entry must register sensitive-file-guard before pre-edit-read-guard.
# Swapping the order lets denied files reach the read-tracker, which is
# a load-bearing contract (see the _note key in both settings files).
#
# Run: bash tests/scripts/test-hook-ordering.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

PYTHON=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "SKIP: python3/python not in PATH"
    exit 0
fi

check_file() {
    local file="$1"
    "$PYTHON" - "$file" <<'PY'
import json, re, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
pre = data.get("hooks", {}).get("PreToolUse", [])
for block in pre:
    matcher = block.get("matcher", "")
    if "Edit" in matcher and "Write" in matcher:
        commands = [h.get("command", "") for h in block.get("hooks", [])]
        def basename(cmd):
            m = re.search(r'([A-Za-z0-9_.-]+?)\.(?:sh|ps1)', cmd)
            return m.group(1) if m else cmd
        names = [basename(c) for c in commands]
        if "sensitive-file-guard" not in names:
            print(f"{path}: sensitive-file-guard missing in {matcher} block")
            sys.exit(1)
        if "pre-edit-read-guard" not in names:
            print(f"{path}: pre-edit-read-guard missing in {matcher} block")
            sys.exit(1)
        s_idx = names.index("sensitive-file-guard")
        p_idx = names.index("pre-edit-read-guard")
        if s_idx >= p_idx:
            print(f"{path}: sensitive-file-guard (pos {s_idx}) must precede pre-edit-read-guard (pos {p_idx}) in {matcher}")
            sys.exit(1)
        sys.exit(0)
print(f"{path}: no PreToolUse block covers both Edit and Write")
sys.exit(1)
PY
}

STATUS=0
for f in global/settings.json global/settings.windows.json; do
    if ! check_file "$f"; then
        STATUS=1
    fi
done

if [ $STATUS -eq 0 ]; then
    echo "PASS: hook ordering (sensitive-file-guard before pre-edit-read-guard) preserved in both settings files"
else
    exit 1
fi
