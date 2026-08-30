#!/bin/bash
# Test suite for prune-permission-rules.sh
# Run: bash tests/hooks/test-prune-permission-rules.sh
#
# The hook rewrites a project-scope .claude/settings.local.json, so every case
# builds a throwaway project directory and feeds the hook a SessionEnd payload
# whose cwd points at it. HOME is redirected too, so the hook's best-effort log
# never touches the real one.

HOOK="global/hooks/prune-permission-rules.sh"
PS_HOOK="global/hooks/prune-permission-rules.ps1"
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

TEST_ROOT="${TMPDIR:-/tmp}/test-prune-permission-rules-$$"
mkdir -p "$TEST_ROOT"
trap 'rm -rf "$TEST_ROOT"' EXIT

check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        ((PASS++))
        echo "  PASS: $label"
    else
        ((FAIL++))
        ERRORS+=("FAIL: $label -- expected [$expected], got [$actual]")
        echo "  FAIL: $label"
        echo "        expected: $expected"
        echo "        actual:   $actual"
    fi
}

# Build a project dir containing the given settings body, run the hook against
# it, and echo the directory so the caller can inspect the result.
make_project() {
    local name="$1" body="$2"
    local dir="$TEST_ROOT/$name"
    mkdir -p "$dir/.claude"
    printf '%s' "$body" > "$dir/.claude/settings.local.json"
    printf '%s' "$dir"
}

run_hook() {
    local dir="$1"
    printf '{"cwd":"%s","session_id":"test","hook_event_name":"SessionEnd"}' "$dir" |
        HOME="$TEST_ROOT/home" bash "$HOOK" >/dev/null 2>&1
    return $?
}

echo "=== prune-permission-rules.sh tests ==="
echo ""

# --- Classification: dead entries go, live entries stay -------------------
echo "[Classification]"

MIXED='{
  "permissions": {
    "allow": [
      "Bash(gh:*)",
      "Bash(gh pr list --limit 5)",
      "PowerShell(Remove-Item *)",
      "PowerShell(docker run *)",
      "Bash(git commit -m '"'"':*)",
      "Bash(cd /tmp/claude-501/592fccf2-dd2a-4e3f-8107-d18162a879df/scratchpad)",
      "Bash(echo one; echo two)",
      "Bash(cat a | grep b)",
      "Read",
      "WebFetch",
      "Skill",
      "Bash(npm run build:*)"
    ],
    "deny": []
  }
}'

dir=$(make_project mixed "$MIXED")
run_hook "$dir"
exit_code=$?
actual=$(jq -c '.permissions.allow' "$dir/.claude/settings.local.json")
expected='["Bash(gh:*)","Read","WebFetch","Skill","Bash(npm run build:*)"]'
check "Keeps prefix rules and bare strings, drops the rest" "$expected" "$actual"
check "Exit code is 0" "0" "$exit_code"

# Each removal class, asserted individually so a regression names itself.
echo ""
echo "[Removal classes]"

one_entry_result() {
    local name="$1" entry="$2" dir
    dir=$(make_project "$name" "{
  \"permissions\": {
    \"allow\": [
      \"Bash(keepme:*)\",
      $entry
    ]
  }
}")
    run_hook "$dir"
    jq -c '.permissions.allow' "$dir/.claude/settings.local.json"
}

check "Denylist: unbounded-argument rule removed" \
    '["Bash(keepme:*)"]' "$(one_entry_result deny1 '"PowerShell(Remove-Item *)"')"
check "Denylist: quote-anchored prefix removed" \
    '["Bash(keepme:*)"]' "$(one_entry_result deny2 '"Bash(git commit -m '"'"':*)"')"
check "Session UUID path removed" \
    '["Bash(keepme:*)"]' "$(one_entry_result uuid '"Bash(ls /tmp/592fccf2-dd2a-4e3f-8107-d18162a879df/x)"')"
check "Compound with semicolon removed" \
    '["Bash(keepme:*)"]' "$(one_entry_result semi '"Bash(a; b)"')"
check "Compound with pipe removed" \
    '["Bash(keepme:*)"]' "$(one_entry_result pipe '"Bash(a | b)"')"

LONG=$(printf 'x%.0s' $(seq 1 130))
check "Over-long literal removed" \
    '["Bash(keepme:*)"]' "$(one_entry_result long "\"Bash(echo $LONG)\"")"

# --- Subsumption ----------------------------------------------------------
echo ""
echo "[Subsumption]"

dir=$(make_project subsume '{
  "permissions": {
    "allow": [
      "Bash(gh:*)",
      "Bash(gh api repos/foo)",
      "Bash(ghost-command run)"
    ]
  }
}')
run_hook "$dir"
check "Subsumed entry removed, similarly-named command kept" \
    '["Bash(gh:*)","Bash(ghost-command run)"]' \
    "$(jq -c '.permissions.allow' "$dir/.claude/settings.local.json")"

# --- Bracket inside a rule string must not end the array ------------------
echo ""
echo "[Bracket safety]"

dir=$(make_project bracket '{
  "permissions": {
    "allow": [
      "Bash(sed -i '"'"''"'"' '"'"'s/[*_~]//g'"'"' f.txt)",
      "PowerShell(Remove-Item *)",
      "Read"
    ]
  }
}')
run_hook "$dir"
check "A ] inside a rule string is not read as the array terminator" \
    '["Bash(sed -i '"'"''"'"' '"'"'s/[*_~]//g'"'"' f.txt)","Read"]' \
    "$(jq -c '.permissions.allow' "$dir/.claude/settings.local.json")"

# --- Fail-open: malformed input leaves the file byte-identical ------------
echo ""
echo "[Fail-open]"

MALFORMED='{ "permissions": { "allow": [ "Bash(a; b)", ] '
dir=$(make_project malformed "$MALFORMED")
before=$(shasum -a 256 "$dir/.claude/settings.local.json" | cut -d' ' -f1)
run_hook "$dir"
exit_code=$?
after=$(shasum -a 256 "$dir/.claude/settings.local.json" | cut -d' ' -f1)
check "Malformed JSON leaves the file byte-identical" "$before" "$after"
check "Malformed JSON still exits 0" "0" "$exit_code"

# A collapsed array is a shape the line-based filter does not handle; it must
# be left alone rather than reformatted.
dir=$(make_project collapsed '{ "permissions": { "allow": ["Bash(a; b)", "Read"] } }')
before=$(shasum -a 256 "$dir/.claude/settings.local.json" | cut -d' ' -f1)
run_hook "$dir"
after=$(shasum -a 256 "$dir/.claude/settings.local.json" | cut -d' ' -f1)
check "Collapsed array left byte-identical" "$before" "$after"

# Nothing to remove means nothing to write.
dir=$(make_project nochange '{
  "permissions": {
    "allow": [
      "Bash(gh:*)",
      "Read"
    ]
  }
}')
before=$(shasum -a 256 "$dir/.claude/settings.local.json" | cut -d' ' -f1)
run_hook "$dir"
after=$(shasum -a 256 "$dir/.claude/settings.local.json" | cut -d' ' -f1)
check "No removable entries leaves the file byte-identical" "$before" "$after"

# Missing target, missing cwd: both are no-ops that still exit 0.
printf '{"cwd":"%s/does-not-exist","hook_event_name":"SessionEnd"}' "$TEST_ROOT" |
    HOME="$TEST_ROOT/home" bash "$HOOK" >/dev/null 2>&1
check "Missing settings file exits 0" "0" "$?"

printf '{"hook_event_name":"SessionEnd"}' | HOME="$TEST_ROOT/home" bash "$HOOK" >/dev/null 2>&1
check "Payload without cwd exits 0" "0" "$?"

printf 'not json at all' | HOME="$TEST_ROOT/home" bash "$HOOK" >/dev/null 2>&1
check "Non-JSON payload exits 0" "0" "$?"

# --- Other keys must survive ----------------------------------------------
echo ""
echo "[Key preservation]"

dir=$(make_project keys '{
  "permissions": {
    "allow": [
      "Bash(gh:*)",
      "Bash(echo one; echo two)"
    ],
    "deny": ["Bash(rm:*)"]
  },
  "skillOverrides": { "some-skill": true, "other-skill": false },
  "hooks": { "SessionEnd": [{ "hooks": [] }] },
  "env": { "FOO": "bar" }
}')
run_hook "$dir"
S="$dir/.claude/settings.local.json"
check "skillOverrides survives" '{"some-skill":true,"other-skill":false}' "$(jq -c '.skillOverrides' "$S")"
check "hooks survives" '{"SessionEnd":[{"hooks":[]}]}' "$(jq -c '.hooks' "$S")"
check "permissions.deny survives" '["Bash(rm:*)"]' "$(jq -c '.permissions.deny' "$S")"
check "env survives" '{"FOO":"bar"}' "$(jq -c '.env' "$S")"
check "allow was still pruned" '["Bash(gh:*)"]' "$(jq -c '.permissions.allow' "$S")"

# --- No temp files left behind --------------------------------------------
echo ""
echo "[Housekeeping]"

leftovers=$(find "$dir/.claude" -name '*.prune.*' 2>/dev/null | wc -l | tr -d ' ')
check "No temp file left in the target directory" "0" "$leftovers"

# --- Idempotency ----------------------------------------------------------
echo ""
echo "[Idempotency]"

dir=$(make_project idem "$MIXED")
run_hook "$dir"
first=$(shasum -a 256 "$dir/.claude/settings.local.json" | cut -d' ' -f1)
run_hook "$dir"
second=$(shasum -a 256 "$dir/.claude/settings.local.json" | cut -d' ' -f1)
check "Second run is a no-op" "$first" "$second"

# --- Hook contract --------------------------------------------------------
echo ""
echo "[Hook contract]"

output=$(printf '{"cwd":"%s","hook_event_name":"SessionEnd"}' "$(make_project quiet "$MIXED")" |
    HOME="$TEST_ROOT/home" bash "$HOOK" 2>/dev/null)
check "Produces no stdout" "" "$output"

if grep -q 'SessionEnd' "$HOOK"; then
    ((PASS++)); echo "  PASS: Declares Hook Type: SessionEnd"
else
    ((FAIL++)); ERRORS+=("FAIL: Missing SessionEnd declaration"); echo "  FAIL: Declares Hook Type: SessionEnd"
fi

# --- PowerShell parity ----------------------------------------------------
echo ""
echo "[PowerShell parity]"

if command -v pwsh >/dev/null 2>&1; then
    sh_dir=$(make_project parity_sh "$MIXED")
    run_hook "$sh_dir"
    sh_result=$(jq -c '.permissions.allow' "$sh_dir/.claude/settings.local.json")

    ps_dir=$(make_project parity_ps "$MIXED")
    printf '{"cwd":"%s","hook_event_name":"SessionEnd"}' "$ps_dir" |
        HOME="$TEST_ROOT/home" pwsh -NoProfile -File "$PS_HOOK" >/dev/null 2>&1
    ps_result=$(jq -c '.permissions.allow' "$ps_dir/.claude/settings.local.json")

    check "PowerShell half classifies identically" "$sh_result" "$ps_result"
else
    echo "  SKIP: pwsh not available"
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
