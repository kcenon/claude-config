#!/bin/bash
# Regression test for hook parity between global/settings.json and
# global/settings.windows.json (issue #421). Extracts every
# (event, matcher, hook-script-basename) tuple from each file and
# asserts the sets are equal.
#
# Windows routes some matchers through a dispatcher that runs the guards in one
# process instead of one process per guard: PreToolUse/Bash through
# global/hooks/bash-guard-dispatcher.ps1 (issue #895) and
# PreToolUse/Edit|Write|Read through global/hooks/edit-guard-dispatcher.ps1
# (issue #920). A naive basename diff would compare the POSIX guards against a
# single dispatcher entry and report drift for every guard, which would force an
# allow-list so broad that the test stops guaranteeing anything. Instead each
# dispatcher entry is EXPANDED to the guard names in its routing table, so the
# parity guarantee is preserved exactly: a guard dropped from a routing table, or
# added on POSIX but never routed on Windows, still fails.
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

DISPATCHERS = {
    "bash-guard-dispatcher": "global/hooks/bash-guard-dispatcher.ps1",
    "edit-guard-dispatcher": "global/hooks/edit-guard-dispatcher.ps1",
}

_guard_cache = {}


def dispatcher_guards(base):
    """Guard names listed in one dispatcher's routing table.

    A dispatcher is the sole hook on its matcher on Windows, so its routing
    table — not the settings file — is where a guard can silently go missing.
    Parsing it here is what keeps this test a real parity guarantee.
    """
    if base in _guard_cache:
        return _guard_cache[base]
    path = DISPATCHERS[base]
    if not os.path.exists(path):
        print(f"missing dispatcher referenced by settings: {path}")
        sys.exit(1)
    with open(path, encoding="utf-8") as f:
        src = f.read()
    names = set(re.findall(r"name\s*=\s*'([A-Za-z0-9_.-]+)'", src))
    if not names:
        print(f"no guards parsed from routing table in {path}")
        sys.exit(1)
    _guard_cache[base] = names
    return names


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
                    if base in DISPATCHERS:
                        # Compare against what the dispatcher actually runs,
                        # not against the dispatcher's own name.
                        for guard in dispatcher_guards(base):
                            tuples.add((event, matcher, guard))
                        continue
                    # Collapse common pairs: session-logger.sh start vs
                    # session-logger.ps1 start — strip trailing args by
                    # basename alone.
                    tuples.add((event, matcher, base))
    return tuples

unix_set = extract(sys.argv[1])
win_set  = extract(sys.argv[2])

# Intentional asymmetries on the GLOBAL settings surface (see
# docs/hooks-ownership.md). markdown-anchor-validator is project-owned: on
# POSIX it lives in project/.claude/settings.json (not global/settings.json),
# but Windows has no project settings variant, so global/settings.windows.json
# is its sole carrier. It therefore legitimately appears only in the Windows
# global file.
WIN_ONLY_ALLOW = {("PreToolUse", "Bash", "markdown-anchor-validator")}
UNIX_ONLY_ALLOW = set()

only_unix = sorted((unix_set - win_set) - UNIX_ONLY_ALLOW)
only_win  = sorted((win_set - unix_set) - WIN_ONLY_ALLOW)

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
