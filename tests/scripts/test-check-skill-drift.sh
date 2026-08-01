#!/usr/bin/env bash
# Test suite for scripts/check_skill_drift.sh.
# Run: bash tests/scripts/test-check-skill-drift.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
CHECK="$ROOT_DIR/scripts/check_skill_drift.sh"

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

write_skill_pair() {
    local repo="$1" source_tools="$2" target_tools="$3"
    write_file "$repo/plugin/skills/demo/SKILL.md" "---
name: demo
description: Demo skill used by the drift test.
allowed-tools: $source_tools
finding_levels: [S1, S2, S3]
---

# Demo

Return findings with severity.
"
    write_file "$repo/project/.claude/skills/demo/SKILL.md" "---
name: demo
description: Demo skill used by the drift test.
allowed-tools: $target_tools
finding_levels: [S1, S2, S3]
---

# Demo

Return findings with severity.
"
}

write_contract() {
    local repo="$1" extra="$2"
    write_file "$repo/skill-drift-contract.yml" "version: 1
default_watched_fields:
  - name
  - description
  - allowed-tools
  - finding_levels
pairs:
  - id: demo-pair
    source: plugin/skills/demo/SKILL.md
    target: project/.claude/skills/demo/SKILL.md
    body:
      mode: exact
$extra"
}

echo "=== check_skill_drift.sh tests ==="

REPO="$WORK/repo-pass"
write_skill_pair "$REPO" "Read, Grep, Glob" "[Read, Grep, Glob]"
write_contract "$REPO" ""
out=$(bash "$CHECK" "$REPO" "$REPO/skill-drift-contract.yml" 2>&1); rc=$?
assert_exit 0 "$rc" "matching watched fields and body pass"

REPO="$WORK/repo-field-drift"
write_skill_pair "$REPO" "Read, Grep, Glob" "[Read, Edit, Glob]"
write_contract "$REPO" ""
out=$(bash "$CHECK" "$REPO" "$REPO/skill-drift-contract.yml" 2>&1); rc=$?
assert_exit 2 "$rc" "watched field drift exits 2"

REPO="$WORK/repo-exception"
write_skill_pair "$REPO" "Read, Grep, Glob" "[Read, Edit, Glob]"
write_contract "$REPO" "    exceptions:
      - field: allowed-tools
        source: [Read, Grep, Glob]
        target: [Read, Edit, Glob]
        reason: Test fixture intentionally grants Edit in the target layer.
"
out=$(bash "$CHECK" "$REPO" "$REPO/skill-drift-contract.yml" 2>&1); rc=$?
assert_exit 0 "$rc" "explicit pinned exception permits watched field difference"

REPO="$WORK/repo-stale-exception"
write_skill_pair "$REPO" "Read, Grep, Glob" "[Read, Write, Glob]"
write_contract "$REPO" "    exceptions:
      - field: allowed-tools
        source: [Read, Grep, Glob]
        target: [Read, Edit, Glob]
        reason: Test fixture intentionally grants Edit in the target layer.
"
out=$(bash "$CHECK" "$REPO" "$REPO/skill-drift-contract.yml" 2>&1); rc=$?
assert_exit 2 "$rc" "exception is pinned to expected values"

REPO="$WORK/repo-unwatched-exception"
write_skill_pair "$REPO" "Read, Grep, Glob" "[Read, Grep, Glob]"
write_contract "$REPO" "    exceptions:
      - field: model
        source: null
        target: sonnet
        reason: Test fixture should fail because model is not watched here.
"
out=$(bash "$CHECK" "$REPO" "$REPO/skill-drift-contract.yml" 2>&1); rc=$?
assert_exit 2 "$rc" "exception for unwatched field exits 2"

REPO="$WORK/repo-body-drift"
write_skill_pair "$REPO" "Read, Grep, Glob" "[Read, Grep, Glob]"
printf '\nExtra target-only behavior.\n' >> "$REPO/project/.claude/skills/demo/SKILL.md"
write_contract "$REPO" ""
out=$(bash "$CHECK" "$REPO" "$REPO/skill-drift-contract.yml" 2>&1); rc=$?
assert_exit 2 "$rc" "body drift exits 2"

REPO="$WORK/repo-missing"
write_skill_pair "$REPO" "Read, Grep, Glob" "[Read, Grep, Glob]"
rm "$REPO/project/.claude/skills/demo/SKILL.md"
write_contract "$REPO" ""
out=$(bash "$CHECK" "$REPO" "$REPO/skill-drift-contract.yml" 2>&1); rc=$?
assert_exit 2 "$rc" "missing paired skill exits 2"

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
