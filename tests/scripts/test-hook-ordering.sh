#!/bin/bash
# Regression test for issue #424: on the PreToolUse Edit|Write|Read matcher,
# sensitive-file-guard must run before pre-edit-read-guard. Swapping the order
# lets denied files reach the read-tracker, which is a load-bearing contract
# (see the _note key in both settings files).
#
# Windows routes this matcher through global/hooks/edit-guard-dispatcher.ps1
# (issue #920), so the settings file names only the dispatcher and the order
# lives in its routing table. This test follows it there rather than accepting
# a single opaque entry, and additionally asserts the short-circuit flag on
# sensitive-file-guard: order alone never enforced the contract, because the
# harness runs later PreToolUse hooks even after one denies. In-process, the
# short-circuit is what actually stops a denied path from being tracked, so
# dropping it would silently reintroduce #424 while leaving the order intact.
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
import json, os, re, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)


def dispatcher_order(base):
    """(name, attrs) per routing-table entry, in file order.

    Order in the table is execution order, so this is the dispatcher's
    equivalent of the hook list in a settings file.
    """
    disp = os.path.join("global", "hooks", base + ".ps1")
    if not os.path.exists(disp):
        print(f"{path}: registers {base} but {disp} does not exist")
        sys.exit(1)
    with open(disp, encoding="utf-8") as f:
        src = f.read()
    entries = re.findall(r"@\{\s*name\s*=\s*'([A-Za-z0-9_.-]+)'([^}]*)\}", src)
    if not entries:
        print(f"{path}: no guards parsed from routing table in {disp}")
        sys.exit(1)
    return entries


pre = data.get("hooks", {}).get("PreToolUse", [])
for block in pre:
    matcher = block.get("matcher", "")
    if "Edit" in matcher and "Write" in matcher:
        commands = [h.get("command", "") for h in block.get("hooks", [])]
        def basename(cmd):
            m = re.search(r'([A-Za-z0-9_.-]+?)\.(?:sh|ps1)', cmd)
            return m.group(1) if m else cmd
        names = [basename(c) for c in commands]

        # A lone dispatcher entry: read the real guard order out of it.
        if len(names) == 1 and names[0].endswith("-dispatcher"):
            entries = dispatcher_order(names[0])
            names = [n for n, _ in entries]
            attrs = dict(entries)
            sc = attrs.get("sensitive-file-guard", "")
            if not re.search(r"shortCircuit\s*=\s*\$true", sc):
                print(f"{path}: sensitive-file-guard must set shortCircuit = $true "
                      f"in {names[0] if names else 'the'} routing table; without it a denied "
                      f"path is still seen by the guards behind it (#424)")
                sys.exit(1)

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
