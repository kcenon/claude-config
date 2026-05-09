#!/bin/bash
# Regression suite for hooks/lib/installer-fetch.sh (#620).
#
# Exercises the four documented exit codes (OK, DOWNLOAD, MISMATCH, RUN) with
# a local file:// fixture so the test runs deterministically without network.
#
# Run: bash tests/scripts/installer-fetch-tests.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

LIB="hooks/lib/installer-fetch.sh"
PASS=0
FAIL=0
ERRORS=()

note_pass() { ((PASS++)); echo "  PASS: $1"; }
note_fail() { ((FAIL++)); ERRORS+=("FAIL: $1"); echo "  FAIL: $1"; }

run_lib() {
    # Sub-shell so the lib's RETURN trap doesn't leak. We capture rc and
    # suppress stdout/stderr — failure messages are evaluated by exit code.
    local url="$1" sha="$2" label="${3:-installer}"
    (
        # shellcheck disable=SC1090
        source "$LIB"
        installer_fetch_verify_run "$url" "$sha" "$label" >/dev/null 2>&1
    )
    return $?
}

echo "=== installer-fetch.sh regression ($LIB) ==="
echo ""

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

# Plant a "installer" that prints a marker. We will measure success by the
# lib's exit code, not by reading the marker, since the lib runs the script.
cat > "$TMP/installer.sh" <<'EOF'
#!/bin/bash
echo "INSTALLER_RAN_OK"
exit 0
EOF
chmod +x "$TMP/installer.sh"

GOOD_SHA=$(sha256sum "$TMP/installer.sh" | awk '{print $1}')
BAD_SHA="0000000000000000000000000000000000000000000000000000000000000000"
GOOD_URL="file://$TMP/installer.sh"

# Plant a script that exits non-zero to exercise RUN failure.
cat > "$TMP/bad-exit.sh" <<'EOF'
#!/bin/bash
exit 7
EOF
chmod +x "$TMP/bad-exit.sh"
BAD_EXIT_SHA=$(sha256sum "$TMP/bad-exit.sh" | awk '{print $1}')
BAD_EXIT_URL="file://$TMP/bad-exit.sh"

echo "[Happy path]"
run_lib "$GOOD_URL" "$GOOD_SHA" "test-ok"; rc=$?
if (( rc == 0 )); then note_pass "valid sha + reachable file → exit 0"
else note_fail "happy path returned $rc (expected 0)"; fi

echo ""
echo "[DOWNLOAD failure]"
run_lib "file://$TMP/does-not-exist" "$GOOD_SHA" "test-dl"; rc=$?
if (( rc == 10 )); then note_pass "missing file → exit 10 (DOWNLOAD)"
else note_fail "missing file returned $rc (expected 10)"; fi

echo ""
echo "[MISMATCH]"
run_lib "$GOOD_URL" "$BAD_SHA" "test-mismatch"; rc=$?
if (( rc == 12 )); then note_pass "wrong sha → exit 12 (MISMATCH)"
else note_fail "wrong sha returned $rc (expected 12)"; fi

echo ""
echo "[RUN failure]"
run_lib "$BAD_EXIT_URL" "$BAD_EXIT_SHA" "test-run-fail"; rc=$?
if (( rc == 13 )); then note_pass "installer exits non-zero → exit 13 (RUN)"
else note_fail "RUN failure returned $rc (expected 13)"; fi

echo ""
echo "[Argument validation]"
(
    # shellcheck disable=SC1090
    source "$LIB"
    installer_fetch_verify_run "" "$GOOD_SHA" "test-noargs" >/dev/null 2>&1
)
rc=$?
if (( rc == 64 )); then note_pass "empty url → exit 64 (usage)"
else note_fail "empty url returned $rc (expected 64)"; fi

(
    # shellcheck disable=SC1090
    source "$LIB"
    installer_fetch_verify_run "$GOOD_URL" "" "test-noargs" >/dev/null 2>&1
)
rc=$?
if (( rc == 64 )); then note_pass "empty sha → exit 64 (usage)"
else note_fail "empty sha returned $rc (expected 64)"; fi

echo ""
echo "[Empty body integrity]"
# A zero-byte download still has a deterministic sha256 (e3b0c44...).
# Use a different expected sha to ensure mismatch fires correctly.
: > "$TMP/empty.sh"
run_lib "file://$TMP/empty.sh" "$GOOD_SHA" "test-empty"; rc=$?
if (( rc == 12 )); then note_pass "empty body + wrong sha → exit 12 (MISMATCH)"
else note_fail "empty body returned $rc (expected 12)"; fi

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
