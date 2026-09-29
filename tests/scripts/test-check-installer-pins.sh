#!/bin/bash
# Regression suite for scripts/check-installer-pins.sh (#936).
#
# Builds fixture trees with the three pin lines in their real shapes and
# serves fake installers over file:// URLs, so every exit code runs without
# network. The last case runs --offline against this repository: it fails
# when a real pin line changes shape or the two bash pins differ.
#
# Run: bash tests/scripts/test-check-installer-pins.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

CHECK="scripts/check-installer-pins.sh"
PASS=0
FAIL=0
OUT=""

note_pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-installer-pins.XXXXXX")" || exit 1
trap 'rm -rf -- "$TMP"' EXIT
SUMMARY="$TMP/summary.md"

printf 'echo "fake bash installer"\n' > "$TMP/install.sh"
printf 'Write-Output "fake PowerShell installer"\n' > "$TMP/install.ps1"
SH_SHA="$(sha256_file "$TMP/install.sh")"
PS1_SHA="$(sha256_file "$TMP/install.ps1")"
OTHER_SHA="0000000000000000000000000000000000000000000000000000000000000000"
SH_URL="file://$TMP/install.sh"
PS1_URL="file://$TMP/install.ps1"
MISSING_URL="file://$TMP/missing"

# make_tree NAME BOOTSTRAP_SH_PIN INSTALL_SH_PIN BOOTSTRAP_PS1_PIN
# Writes the three pin lines in the shapes the real files use and prints the
# tree's path.
make_tree() {
    local dir="$TMP/$1" q="'"
    mkdir -p "$dir/scripts"
    printf 'ANTHROPIC_INSTALLER_SHA256="${ANTHROPIC_INSTALLER_SHA256:-%s}"  # pinned 2026-01-01\n' "$2" > "$dir/bootstrap.sh"
    printf '    local installer_sha="${ANTHROPIC_INSTALLER_SHA256:-%s}"\n' "$3" > "$dir/scripts/install.sh"
    printf '$AnthropicInstallerSha256 = if ($env:ANTHROPIC_INSTALLER_SHA256) { $env:ANTHROPIC_INSTALLER_SHA256 } else { %s%s%s }  # pinned 2026-01-01\n' "$q" "$4" "$q" > "$dir/bootstrap.ps1"
    printf '%s\n' "$dir"
}

# run_check NAME EXPECTED_RC ARGS...
# Runs the checker outside GitHub Actions semantics (no annotations), keeps
# its combined output in $OUT and its job summary in $SUMMARY.
run_check() {
    local name="$1" expected="$2" rc
    shift 2
    : > "$SUMMARY"
    OUT="$(GITHUB_STEP_SUMMARY="$SUMMARY" GITHUB_ACTIONS="" bash "$CHECK" "$@" 2>&1)"
    rc=$?
    if [ "$rc" -eq "$expected" ]; then
        note_pass "$name: exit $rc"
    else
        note_fail "$name: expected exit $expected, got $rc"
        printf '%s\n' "$OUT" | sed 's/^/      /'
    fi
}

# expect_output NAME TEXT: the last run printed TEXT.
expect_output() {
    if printf '%s\n' "$OUT" | grep -Fq -- "$2"; then
        note_pass "$1"
    else
        note_fail "$1: output lacks '$2'"
    fi
}

# expect_summary NAME TEXT COUNT: the last job summary holds TEXT COUNT times.
expect_summary() {
    local n
    n="$(grep -Fc -- "$2" "$SUMMARY")"
    if [ "$n" -eq "$3" ]; then
        note_pass "$1"
    else
        note_fail "$1: summary holds '$2' $n times, expected $3"
    fi
}

echo "=== check-installer-pins.sh regression ($CHECK) ==="
echo ""

T="$(make_tree match "$SH_SHA" "$SH_SHA" "$PS1_SHA")"
run_check "all pins match" 0 --root "$T" --sh-url "$SH_URL" --ps1-url "$PS1_URL"
expect_summary "summary lists three passing checks" "| pass |" 3

# Positive controls: a failing check must not stop the ones after it.
T="$(make_tree ps1-drift "$SH_SHA" "$SH_SHA" "$OTHER_SHA")"
run_check "install.ps1 drift" 1 --root "$T" --sh-url "$SH_URL" --ps1-url "$PS1_URL"
expect_output "install.ps1 drift is named" "install.ps1: sha256 drift detected."
expect_output "install.sh is still checked" "install.sh: sha256 pin matches upstream."
expect_summary "summary marks one drift" "| FAIL: drift |" 1

T="$(make_tree sh-drift "$OTHER_SHA" "$OTHER_SHA" "$PS1_SHA")"
run_check "install.sh drift" 1 --root "$T" --sh-url "$SH_URL" --ps1-url "$PS1_URL"
expect_output "install.sh drift is named" "install.sh: sha256 drift detected."
expect_output "install.ps1 is still checked" "install.ps1: sha256 pin matches upstream."

T="$(make_tree parity "$SH_SHA" "$OTHER_SHA" "$PS1_SHA")"
run_check "bash pins differ" 1 --root "$T" --sh-url "$SH_URL" --ps1-url "$PS1_URL"
expect_output "parity failure is named" "parity: bootstrap.sh and scripts/install.sh carry different bash pins."
expect_output "install.sh is compared with the bootstrap.sh pin" "install.sh: sha256 pin matches upstream."
run_check "bash pins differ, offline" 1 --offline --root "$T" --sh-url "$MISSING_URL" --ps1-url "$MISSING_URL"

# Unreachable URLs prove --offline downloads nothing: a download would exit 3.
T="$(make_tree offline "$SH_SHA" "$SH_SHA" "$PS1_SHA")"
run_check "offline downloads nothing" 0 --offline --root "$T" --sh-url "$MISSING_URL" --ps1-url "$MISSING_URL"

T="$(make_tree unreadable "$SH_SHA" "$SH_SHA" "not-a-sha256")"
run_check "unreadable bootstrap.ps1 pin" 2 --root "$T" --sh-url "$SH_URL" --ps1-url "$PS1_URL"
expect_output "unreadable pin is named" "bootstrap.ps1: could not read exactly one pin line"
expect_output "install.sh is still checked" "install.sh: sha256 pin matches upstream."

T="$(make_tree duplicate "$SH_SHA" "$SH_SHA" "$PS1_SHA")"
line="$(cat "$T/bootstrap.sh")"
printf '%s\n' "$line" >> "$T/bootstrap.sh"
run_check "duplicated bootstrap.sh pin line" 2 --root "$T" --sh-url "$SH_URL" --ps1-url "$PS1_URL"

T="$(make_tree fetch "$SH_SHA" "$SH_SHA" "$PS1_SHA")"
run_check "download failure" 3 --root "$T" --sh-url "$SH_URL" --ps1-url "$MISSING_URL"
expect_output "download failure is named" "install.ps1: could not download"

# Exit code precedence: drift, then unreadable pin, then download failure.
T="$(make_tree drift-and-fetch "$OTHER_SHA" "$OTHER_SHA" "$PS1_SHA")"
run_check "drift outranks a download failure" 1 --root "$T" --sh-url "$SH_URL" --ps1-url "$MISSING_URL"
T="$(make_tree unreadable-and-fetch "$SH_SHA" "$SH_SHA" "not-a-sha256")"
run_check "unreadable pin outranks a download failure" 2 --root "$T" --sh-url "$MISSING_URL" --ps1-url "$PS1_URL"

run_check "unknown option" 64 --bogus

T="$(make_tree annotate "$SH_SHA" "$SH_SHA" "$OTHER_SHA")"
OUT="$(GITHUB_STEP_SUMMARY="$SUMMARY" GITHUB_ACTIONS=true bash "$CHECK" --root "$T" --sh-url "$SH_URL" --ps1-url "$PS1_URL" 2>&1)"
expect_output "drift raises an error annotation in Actions" "::error::install.ps1: sha256 drift detected"

# The real pin lines: a reshaped line exits 2, differing bash pins exit 1.
run_check "this repository, offline" 0 --offline

echo ""
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
