#!/bin/bash
# Regression test for scripts/install-manifest.sh (issue #420).
# Verifies that guarded_copy preserves local customizations when the user
# chooses [k]eep, and honors BOOTSTRAP_FORCE=1 to overwrite.
#
# Run: bash tests/scripts/test-install-preserves-customization.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
HELPER="$ROOT_DIR/scripts/install-manifest.sh"

if [ ! -f "$HELPER" ]; then
    echo "FAIL: helper not found: $HELPER" >&2
    exit 1
fi

PASS=0
FAIL=0
ERRORS=()

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Each case runs in its own manifest path and temp files.
new_case() {
    local name="$1"
    CASE_DIR="$WORK/$name"
    mkdir -p "$CASE_DIR"
    export MANIFEST_PATH="$CASE_DIR/manifest.json"
    unset BOOTSTRAP_FORCE
}

# shellcheck disable=SC1090
source "$HELPER"

if ! manifest_available; then
    echo "SKIP: no python3/python on PATH; guarded_copy requires JSON tool"
    exit 0
fi

assert_equal() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("$label: expected '$expected', got '$actual'")
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("$label: '$needle' not found in output")
    fi
}

# --- Case 1: first install records the hash -------------------------------
new_case "first-install"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1 content\n' > "$src"
guarded_copy "$src" "$dest" "source.md"
assert_equal "first-install: dest exists" "v1 content" "$(cat "$dest")"
assert_contains "first-install: manifest has hash" "source.md" "$(cat "$MANIFEST_PATH")"

# --- Case 2: re-install with no local edit upgrades silently --------------
new_case "clean-upgrade"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1\n' > "$src"
guarded_copy "$src" "$dest" "source.md"   # first install
printf 'v2\n' > "$src"                      # new upstream version
guarded_copy "$src" "$dest" "source.md"   # should upgrade silently
assert_equal "clean-upgrade: dest reflects v2" "v2" "$(cat "$dest")"

# --- Case 3: local edit preserved on [k] (default) ------------------------
new_case "keep-local"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1\n' > "$src"
guarded_copy "$src" "$dest" "source.md"
printf 'locally edited\n' > "$dest"
printf 'v2\n' > "$src"
# Feed empty input to read -> default keep
if echo "" | guarded_copy "$src" "$dest" "source.md" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    ERRORS+=("keep-local: guarded_copy should have returned non-zero on keep")
else
    PASS=$((PASS + 1))
fi
assert_equal "keep-local: dest unchanged" "locally edited" "$(cat "$dest")"

# --- Case 4: [o] overwrites local edit ------------------------------------
new_case "overwrite-choice"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1\n' > "$src"
guarded_copy "$src" "$dest" "source.md"
printf 'locally edited\n' > "$dest"
printf 'v2\n' > "$src"
echo "o" | guarded_copy "$src" "$dest" "source.md" >/dev/null
assert_equal "overwrite-choice: dest reflects v2" "v2" "$(cat "$dest")"

# --- Case 5: BOOTSTRAP_FORCE=1 bypasses prompt ----------------------------
new_case "force-flag"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1\n' > "$src"
guarded_copy "$src" "$dest" "source.md"
printf 'locally edited\n' > "$dest"
printf 'v2\n' > "$src"
BOOTSTRAP_FORCE=1 guarded_copy "$src" "$dest" "source.md"
assert_equal "force-flag: dest reflects v2" "v2" "$(cat "$dest")"

# --- Summary --------------------------------------------------------------
echo ""
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Errors:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    exit 1
fi
