#!/bin/bash
# Test suite for memory-access-logger.sh
# Run: bash tests/hooks/test-memory-access-logger.sh
#
# The hook logs a Read only when the resolved path is under the memory root, so
# the root has to be resolved as well. Before #983 it was not, and every read
# under a symlinked HOME left no line in the audit log.

set -u

HOOK="global/hooks/memory-access-logger.sh"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

# Prefer $TMPDIR (sandbox-writable); pwd -P so that the paths below are the real
# ones (macOS: /var/... -> /private/var/...).
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mal-test.XXXXXX")" || exit 1
ROOT="$(cd "$ROOT" && pwd -P)"
trap 'rm -rf "$ROOT"' EXIT

REAL="$ROOT/real"
LINK="$ROOT/link"
SHARED="$REAL/.claude/memory-shared"
MEM="$SHARED/memories"
VIA_LINK="$LINK/.claude/memory-shared/memories"
mkdir -p "$MEM" "$REAL/.claude/other" "$REAL/notes"
ln -s "$REAL" "$LINK"
: >"$MEM/e.md"
: >"$SHARED/MEMORY.md"
: >"$REAL/notes/n.md"

# run_hook <home> <tool> <path>: one call, from an empty log.
run_hook() {
    rm -f "$1/.claude/logs/memory-access.log"
    printf '{"tool_name":"%s","session_id":"s1","tool_input":{"file_path":"%s"}}' "$2" "$3" \
        | HOME="$1" bash "$HOOK" >/dev/null 2>&1
}

# logged_key <home>: the path field of the logged line, if any.
logged_key() {
    if [ -f "$1/.claude/logs/memory-access.log" ]; then
        sed -E 's/^[^ ]+ [^ ]+ read //' "$1/.claude/logs/memory-access.log"
    fi
}

# check <expected key, empty for no line> <home> <tool> <path> <label>
check() {
    local expected="$1" home="$2" tool="$3" path="$4" label="$5" got
    run_hook "$home" "$tool" "$path"
    got="$(logged_key "$home")"
    if [ "$got" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- expected '$expected', got '$got'")
        echo "  FAIL: $label (got '$got', expected '$expected')"
    fi
}

echo "=== memory-access-logger.sh tests ==="
echo ""

echo "[Path spellings of one memory file]"
check "memories/e.md" "$REAL" Read "$MEM/e.md" "real HOME, real path"
check "memories/e.md" "$REAL" Read "$VIA_LINK/e.md" "real HOME, path through a link"
check "memories/e.md" "$LINK" Read "$VIA_LINK/e.md" "HOME on a link, path through the link"
check "memories/e.md" "$LINK" Read "$MEM/e.md" "HOME on a link, real path"
check "memories/e.md" "$REAL" Read "$MEM/../memories/e.md" "existing file, dot segment"

echo ""
echo "[A file that does not exist yet]"
check "memories/n.md" "$REAL" Read "$MEM/../memories/n.md" "dot segment inside the memory root"
check "memories/n.md" "$REAL" Read "$REAL/.claude/other/../memory-shared/memories/n.md" "dot segment outside the memory root"
check "memories/n.md" "$LINK" Read "$VIA_LINK/n.md" "HOME on a link"
check "memories/n.md" "$LINK" Read "$MEM/n.md" "HOME on a link, real path"

echo ""
echo "[A memories directory that is itself a link]"
HOME2="$ROOT/home2"
STORE="$ROOT/store"
mkdir -p "$HOME2/.claude/memory-shared" "$STORE"
ln -s "$STORE" "$HOME2/.claude/memory-shared/memories"
: >"$STORE/e.md"
check "memories/e.md" "$HOME2" Read "$HOME2/.claude/memory-shared/memories/e.md" "path through the link"
check "memories/e.md" "$HOME2" Read "$STORE/e.md" "path to the link target"

echo ""
echo "[Not logged]"
check "" "$REAL" Read "$REAL/notes/n.md" "a file outside the memory root"
check "" "$REAL" Read "$SHARED/MEMORY.md" "the top-level index"
check "" "$REAL" Read "$REAL/.claude/memory-shared/memories-other/e.md" "a sibling that only shares the prefix"
check "" "$REAL" Edit "$MEM/e.md" "a tool other than Read"

echo ""
echo "[Line shape]"
run_hook "$REAL" Read "$MEM/e.md"
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z s1 read memories/e\.md$' "$REAL/.claude/logs/memory-access.log"; then
    PASS=$((PASS + 1))
    echo "  PASS: timestamp, session id, verb, key"
else
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: line shape -- got: $(cat "$REAL/.claude/logs/memory-access.log")")
    echo "  FAIL: timestamp, session id, verb, key"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
    exit 1
fi
exit 0
