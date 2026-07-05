#!/usr/bin/env bash
# Test suite for scripts/check_versions.sh and scripts/sync_versions.sh.
# Run: bash tests/scripts/test-check-versions.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
CHECK="$ROOT_DIR/scripts/check_versions.sh"
SYNC="$ROOT_DIR/scripts/sync_versions.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ERRORS=()

write_file() {
    local path="$1" content="$2"
    mkdir -p "$(dirname "$path")"
    printf '%s' "$content" > "$path"
}

assert_exit() {
    local expected="$1" actual="$2" label="$3"
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- expected exit $expected, got $actual")
        echo "  FAIL: $label (expected $expected, got $actual)"
    fi
}

assert_contains() {
    local needle="$1" haystack="$2" label="$3"
    if echo "$haystack" | grep -Fq -- "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- output did not contain '$needle': $haystack")
        echo "  FAIL: $label"
    fi
}

assert_file_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -Fq -- "$needle" "$file"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- $file did not contain '$needle'")
        echo "  FAIL: $label"
    fi
}

write_fixture_repo() {
    local repo="$1"
    mkdir -p "$repo/scripts"
    cp "$CHECK" "$repo/scripts/check_versions.sh"
    cp "$SYNC" "$repo/scripts/sync_versions.sh"
    chmod +x "$repo/scripts/check_versions.sh" "$repo/scripts/sync_versions.sh"

    write_file "$repo/VERSION_MAP.yml" 'suite: 1.11.0
plugin: 2.3.0
plugin-lite: 1.1.0
settings-schema: 1.17.0
hooks: 1.1.1
'
    write_file "$repo/plugin/.claude-plugin/plugin.json" '{
  "version": "2.3.0"
}
'
    write_file "$repo/plugin-lite/.claude-plugin/plugin.json" '{
  "version": "1.1.0"
}
'
    write_file "$repo/global/settings.json" '{
  "version": "1.17.0"
}
'
    write_file "$repo/global/settings.windows.json" '{
  "version": "1.17.0"
}
'
    write_file "$repo/bootstrap.sh" 'GITHUB_REF="${GITHUB_REF:-v1.10.0}"
'
    write_file "$repo/bootstrap.ps1" '$GitHubRef = if ($env:GITHUB_REF) { $env:GITHUB_REF }
             elseif ($env:GITHUB_BRANCH) { $env:GITHUB_BRANCH }
             else { '"'"'v1.10.0'"'"' }
'
    write_file "$repo/README.md" '<img src="https://img.shields.io/badge/version-1.11.0-blue.svg">
GITHUB_REF=v1.10.0 \
| `GITHUB_REF` | latest release tag (e.g. `v1.10.0`) |
'
    write_file "$repo/README.ko.md" '<img src="https://img.shields.io/badge/version-1.11.0-blue.svg">
GITHUB_REF=v1.10.0 \
| `GITHUB_REF` | 최신 release tag (예: `v1.10.0`) |
'
}

echo "=== check_versions.sh tests ==="

REPO="$WORK/repo"
write_fixture_repo "$REPO"

out=$(bash "$REPO/scripts/check_versions.sh" 2>&1); rc=$?
assert_exit 2 "$rc" "stale bootstrap and README GITHUB_REF pins fail"
assert_contains "bootstrap.sh GITHUB_REF=1.10.0, VERSION_MAP[suite]=1.11.0" "$out" "bootstrap.sh drift is reported"
assert_contains "README.md GITHUB_REF pin=1.10.0, VERSION_MAP[suite]=1.11.0" "$out" "README.md drift is reported"

out=$(bash "$REPO/scripts/sync_versions.sh" 2>&1); rc=$?
assert_exit 0 "$rc" "sync exits 0"
out=$(bash "$REPO/scripts/check_versions.sh" 2>&1); rc=$?
assert_exit 0 "$rc" "sync restores version drift"
assert_file_contains "$REPO/bootstrap.sh" 'GITHUB_REF="${GITHUB_REF:-v1.11.0}"' "bootstrap.sh pin synced"
assert_file_contains "$REPO/bootstrap.ps1" "else { 'v1.11.0' }" "bootstrap.ps1 pin synced"
assert_file_contains "$REPO/README.md" 'GITHUB_REF=v1.11.0 \' "README.md code pin synced"
assert_file_contains "$REPO/README.ko.md" '예: `v1.11.0`' "README.ko.md table pin synced"

echo ""
echo "=== Summary ==="
echo "  $PASS passed, $FAIL failed"
if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo ""
    echo "Errors:"
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
    exit 1
fi
exit 0
