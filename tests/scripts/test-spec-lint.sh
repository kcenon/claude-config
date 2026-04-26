#!/bin/bash
# Test suite for scripts/spec_lint.{py,sh}
# Run: bash tests/scripts/test-spec-lint.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
LINTER="$ROOT_DIR/scripts/spec_lint.py"
WRAPPER="$ROOT_DIR/scripts/spec_lint.sh"

PASS=0
FAIL=0
ERRORS=()

# Locate Python interpreter
PYTHON=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "SKIP: python3/python not in PATH" >&2
    exit 0
fi
if ! "$PYTHON" -c "import yaml, jsonschema" >/dev/null 2>&1; then
    echo "SKIP: missing PyYAML or jsonschema" >&2
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Helpers
write_file() {
    local path="$1" content="$2"
    mkdir -p "$(dirname "$path")"
    printf '%s' "$content" > "$path"
}

run_lint() {
    local mode="$1"; shift
    "$PYTHON" "$LINTER" --mode "$mode" --quiet "$@"
}

assert_exit() {
    local expected="$1" actual="$2" label="$3"
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (exit $actual)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- expected exit $expected, got $actual")
        echo "  FAIL: $label (expected $expected, got $actual)"
    fi
}

assert_output_contains() {
    local needle="$1" output="$2" label="$3"
    if echo "$output" | grep -Fq -- "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label -- output did not contain '$needle': $output")
        echo "  FAIL: $label"
    fi
}

echo "=== spec_lint.py / spec_lint.sh tests ==="
echo ""

# ── Fixture: valid SKILL.md ──────────────────────────────────
GOOD_SKILL="$WORK/good-skill.md"
write_file "$GOOD_SKILL" '---
name: good-skill
description: A valid SKILL.md fixture used by the spec linter test suite. Long enough to satisfy any minimum length recommendations.
disable-model-invocation: true
user-invocable: true
allowed-tools: "Bash(git *)"
context: fork
effort: high
---

content
'

echo "[case 1: valid SKILL.md passes]"
out=$(run_lint skill "$GOOD_SKILL" 2>&1); rc=$?
assert_exit 0 "$rc" "valid SKILL.md -> exit 0"

# ── Fixture: underscore typo (did-you-mean) ──────────────────
TYPO_SKILL="$WORK/typo-skill.md"
write_file "$TYPO_SKILL" '---
name: typo-skill
description: SKILL with underscore typo on disable_model_invocation field for did-you-mean coverage.
disable_model_invocation: true
---

content
'

echo ""
echo "[case 2: underscore typo caught with did-you-mean]"
out=$(run_lint skill "$TYPO_SKILL" 2>&1); rc=$?
assert_exit 1 "$rc" "underscore typo -> exit 1"
assert_output_contains "did you mean 'disable-model-invocation'" "$out" "did-you-mean suggestion present"

# ── Fixture: unknown field rejected ──────────────────────────
UNK_SKILL="$WORK/unknown-field-skill.md"
write_file "$UNK_SKILL" '---
name: unknown-field
description: SKILL with a totally unknown field that must be rejected by the additionalProperties rule.
memory: persistent
---

content
'

echo ""
echo "[case 3: unknown field rejected]"
out=$(run_lint skill "$UNK_SKILL" 2>&1); rc=$?
assert_exit 1 "$rc" "unknown 'memory' field -> exit 1"
assert_output_contains "unknown field(s)" "$out" "unknown field message"

# ── Fixture: invalid enum values ─────────────────────────────
ENUM_SKILL="$WORK/bad-enum-skill.md"
write_file "$ENUM_SKILL" '---
name: bad-enum
description: SKILL with invalid enum values for effort, context, and shell. Must be rejected by the schema.
effort: turbo
context: warp
shell: zsh
---

content
'

echo ""
echo "[case 4: invalid enum values rejected]"
out=$(run_lint skill "$ENUM_SKILL" 2>&1); rc=$?
assert_exit 1 "$rc" "bad effort/context/shell -> exit 1"
assert_output_contains "'turbo' is not one of" "$out" "effort enum error"
assert_output_contains "'warp' is not one of" "$out" "context enum error"
assert_output_contains "'zsh' is not one of" "$out" "shell enum error"

# ── Fixture: description too long ────────────────────────────
LONG_DESC="$(printf 'x%.0s' {1..1100})"
LONG_SKILL="$WORK/long-desc-skill.md"
write_file "$LONG_SKILL" "---
name: long-desc
description: $LONG_DESC
---

content
"

echo ""
echo "[case 5: description >1024 chars rejected]"
out=$(run_lint skill "$LONG_SKILL" 2>&1); rc=$?
assert_exit 1 "$rc" "1100-char description -> exit 1"
assert_output_contains "is too long" "$out" "max length error"

# ── Fixture: missing required name/description ───────────────
NO_NAME_SKILL="$WORK/no-name-skill.md"
write_file "$NO_NAME_SKILL" '---
description: SKILL missing the required name field. Must be rejected by the linter as a required-field violation.
---

content
'

echo ""
echo "[case 6: missing required name -> rejected]"
out=$(run_lint skill "$NO_NAME_SKILL" 2>&1); rc=$?
assert_exit 1 "$rc" "missing name -> exit 1"
assert_output_contains "'name' is a required property" "$out" "missing name error"

NO_DESC_SKILL="$WORK/no-desc-skill.md"
write_file "$NO_DESC_SKILL" '---
name: no-desc
---

content
'
echo ""
echo "[case 6b: missing required description -> rejected]"
out=$(run_lint skill "$NO_DESC_SKILL" 2>&1); rc=$?
assert_exit 1 "$rc" "missing description -> exit 1"
assert_output_contains "'description' is a required property" "$out" "missing description error"

# ── Fixture: plugin.json with unknown field ──────────────────
# plugin.json schema uses additionalProperties: true, so unknown top-level keys
# are allowed (forward-compat). This case verifies that an INVALID known field
# (bad semver) is rejected — the spec linter's job is enforcing declared rules.
BAD_PLUGIN="$WORK/bad-plugin.json"
write_file "$BAD_PLUGIN" '{
  "name": "test-plugin",
  "version": "not-a-semver",
  "description": "Plugin with invalid semver for version field validation.",
  "future_field": "tolerated"
}
'

echo ""
echo "[case 7: plugin.json with bad semver rejected, unknown top-level tolerated]"
out=$(run_lint plugin "$BAD_PLUGIN" 2>&1); rc=$?
assert_exit 1 "$rc" "bad semver -> exit 1"
assert_output_contains "does not match" "$out" "semver pattern error"

# ── Fixture: settings.json with unknown nested enum ──────────
# settings.json schema allows additional top-level fields (forward-compat),
# but enforces enums on declared fields like teammateMode and effortLevel.
BAD_SETTINGS="$WORK/bad-settings.json"
write_file "$BAD_SETTINGS" '{
  "teammateMode": "telepathic",
  "effortLevel": "ludicrous",
  "permissions": {
    "defaultMode": "yolo"
  }
}
'

echo ""
echo "[case 8: settings.json with bad enum rejected]"
out=$(run_lint settings "$BAD_SETTINGS" 2>&1); rc=$?
assert_exit 1 "$rc" "bad enums -> exit 1"
assert_output_contains "'telepathic' is not one of" "$out" "teammateMode enum error"
assert_output_contains "'ludicrous' is not one of" "$out" "effortLevel enum error"
assert_output_contains "'yolo' is not one of" "$out" "permissions.defaultMode enum error"

# ── Mode flags: --warn-only and --strict ─────────────────────
echo ""
echo "[case 9: --warn-only exits 0 even on violations]"
"$PYTHON" "$LINTER" --mode skill --warn-only --quiet "$ENUM_SKILL" >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "--warn-only on violations -> exit 0"

echo ""
echo "[case 10: --strict exits 2 on violations]"
"$PYTHON" "$LINTER" --mode skill --strict --quiet "$ENUM_SKILL" >/dev/null 2>&1; rc=$?
assert_exit 2 "$rc" "--strict on violations -> exit 2"

# ── Fixture: halt_conditions array form (A1, P1-a) ───────────
HALT_ARRAY_SKILL="$WORK/halt-array-skill.md"
write_file "$HALT_ARRAY_SKILL" '---
name: halt-array-skill
description: SKILL.md verifying that the new halt_conditions array form is accepted by the schema.
max_iterations: 5
halt_conditions:
  - { type: success, expr: "All checks pass" }
  - { type: limit, expr: "max_iterations reached" }
loop_safe: true
---

content
'

echo ""
echo "[case 10a: halt_conditions array form accepted]"
out=$(run_lint skill "$HALT_ARRAY_SKILL" 2>&1); rc=$?
assert_exit 0 "$rc" "halt_conditions array -> exit 0"

# ── Fixture: halt_conditions legacy string form (grace period) ─
HALT_STRING_SKILL="$WORK/halt-string-skill.md"
write_file "$HALT_STRING_SKILL" '---
name: halt-string-skill
description: SKILL.md verifying that the legacy halt_conditions single-string form is still accepted during the P1 grace period.
halt_conditions: "All checks pass OR user aborts"
---

content
'

echo ""
echo "[case 10b: halt_conditions legacy string form accepted]"
out=$(run_lint skill "$HALT_STRING_SKILL" 2>&1); rc=$?
assert_exit 0 "$rc" "halt_conditions string -> exit 0"

# ── Fixture: halt_conditions empty array (rejected) ──────────
HALT_EMPTY_SKILL="$WORK/halt-empty-skill.md"
write_file "$HALT_EMPTY_SKILL" '---
name: halt-empty-skill
description: SKILL.md verifying that an empty halt_conditions array is rejected by the schema.
halt_conditions: []
---

content
'

echo ""
echo "[case 10c: halt_conditions empty array rejected]"
out=$(run_lint skill "$HALT_EMPTY_SKILL" 2>&1); rc=$?
assert_exit 1 "$rc" "halt_conditions [] -> exit 1"

# ── Fixture: halt_conditions unknown type (rejected) ─────────
HALT_BAD_TYPE_SKILL="$WORK/halt-bad-type-skill.md"
write_file "$HALT_BAD_TYPE_SKILL" '---
name: halt-bad-type-skill
description: SKILL.md verifying that an unknown halt_conditions entry type is rejected by the enum.
halt_conditions:
  - { type: telepathy, expr: "psychic signal" }
---

content
'

echo ""
echo "[case 10d: halt_conditions unknown entry type rejected]"
out=$(run_lint skill "$HALT_BAD_TYPE_SKILL" 2>&1); rc=$?
assert_exit 1 "$rc" "halt_conditions unknown type -> exit 1"

# ── Wrapper invocation ───────────────────────────────────────
echo ""
echo "[case 11: spec_lint.sh wrapper works in --mode form]"
bash "$WRAPPER" --mode skill "$GOOD_SKILL" >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "wrapper --mode skill on valid file -> exit 0"

bash "$WRAPPER" --mode skill "$ENUM_SKILL" >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "wrapper --mode skill on bad file -> exit 1"

bash "$WRAPPER" --mode skill --warn-only "$ENUM_SKILL" >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "wrapper --warn-only -> exit 0 even on violations"

# ── Repo discovery: all canonical files must lint clean ──────
echo ""
echo "[case 12: full repo lints clean (regression guard)]"
bash "$WRAPPER" --quiet >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "all canonical SKILL.md/plugin.json/settings.json pass"

# ── sync.sh integration: --lint fast-path is side-effect free ─
echo ""
echo "[case 13: sync.sh --lint is a side-effect-free fast path]"
# --lint exec()s spec_lint.sh and returns its exit code without prompting.
bash "$ROOT_DIR/scripts/sync.sh" --lint --quiet </dev/null >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "sync.sh --lint returns linter's exit code (no prompts)"

# ── sync.sh integration: pre-flight aborts on lint failure ───
echo ""
echo "[case 14: sync.sh (no flag) aborts when spec_lint detects violations]"
# Stage a sandbox copy of sync.sh next to a stub spec_lint.sh that always fails.
# This proves the pre-flight guard runs BEFORE any interactive prompt.
SANDBOX="$WORK/sync-abort-sandbox"
mkdir -p "$SANDBOX/scripts"
cat > "$SANDBOX/scripts/spec_lint.sh" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$SANDBOX/scripts/spec_lint.sh"
cp "$ROOT_DIR/scripts/sync.sh" "$SANDBOX/scripts/sync.sh"
out=$(bash "$SANDBOX/scripts/sync.sh" </dev/null 2>&1); rc=$?
assert_exit 1 "$rc" "sync.sh aborts with exit 1 when linter fails"
assert_output_contains "Sync aborted" "$out" "abort message present"
assert_output_contains "--skip-lint"  "$out" "bypass hint present"

# ── sync.sh integration: --skip-lint bypasses pre-flight ─────
echo ""
echo "[case 15: sync.sh --skip-lint bypasses pre-flight even when linter fails]"
# Same sandbox, but with --skip-lint: must get PAST the pre-flight abort.
# Don't assert downstream exit code (the sandbox lacks the real backup tree,
# so set -e will trip later inside compare_files). The contract under test
# is: bypass is honored. Banner output proves the pre-flight did not abort.
out=$(printf '3\nn\nn\n' | bash "$SANDBOX/scripts/sync.sh" --skip-lint 2>&1 || true)
assert_output_contains "Claude Configuration Sync Tool" "$out" "banner displayed (pre-flight bypassed)"
# Negative assertion: the abort message must NOT appear when --skip-lint is set.
if echo "$out" | grep -Fq "Sync aborted to prevent deploying drift"; then
    FAIL=$((FAIL + 1))
    ERRORS+=("FAIL: --skip-lint should suppress abort message but did not")
    echo "  FAIL: --skip-lint suppresses abort message"
else
    PASS=$((PASS + 1))
    echo "  PASS: --skip-lint suppresses abort message"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
echo "  $PASS passed, $FAIL failed"
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "Errors:"
    for e in "${ERRORS[@]}"; do echo "  $e"; done
    exit 1
fi
exit 0
