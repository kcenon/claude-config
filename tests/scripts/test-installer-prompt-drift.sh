#!/bin/bash
# test-installer-prompt-drift.sh
# Drift regression for the installer prompt deduplication.
#
# scripts/lib/install-prompts.sh and scripts/lib/InstallPrompts.psm1 are
# the single source of truth for installer prompts and the policy phrase
# table. Their bash and PowerShell forms must agree on:
#
#   1. the four canonical policy values
#   2. the policy -> phrase mapping
#   3. the legacy-vs-surfaced classification
#
# This test extracts the relevant tables from each file via static
# pattern matching (no PowerShell runtime required) and diffs them.
#
# Run: bash tests/scripts/test-installer-prompt-drift.sh
# Exit: 0 on no drift, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BASH_LIB="$REPO_ROOT/scripts/lib/install-prompts.sh"
PS_LIB="$REPO_ROOT/scripts/lib/InstallPrompts.psm1"

# shellcheck disable=SC1090
source "$BASH_LIB"

PASS=0
FAIL=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $name"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $name"
        echo "    bash:       $expected"
        echo "    PowerShell: $actual"
    fi
}

echo "=== Installer prompt drift test ==="
echo ""
echo "[1] Canonical policy list (bash all_policy_values vs PowerShell switch)"

# Bash side: comma-joined list from all_policy_values.
bash_policies="$(all_policy_values | paste -sd, -)"

# PowerShell side: extract the @('...','...',...) literal from
# Get-AllPolicyValues. Normalize whitespace and quotes.
ps_policies="$(grep -oE "@\(([^)]+)\)" "$PS_LIB" \
    | head -1 \
    | tr -d "@()' " \
    | tr ',' '\n' \
    | grep -v '^$' \
    | paste -sd, -)"

check "policy list matches" "$bash_policies" "$ps_policies"

echo ""
echo "[2] policy -> phrase mapping"

while IFS= read -r policy; do
    [ -n "$policy" ] || continue
    bash_phrase="$(get_policy_phrase "$policy")"
    # Extract phrase from PowerShell module: lines like
    #     'english'  { return 'English' }
    ps_phrase="$(grep -E "^[[:space:]]*'$policy'[[:space:]]*\{" "$PS_LIB" \
        | head -1 \
        | sed -E "s/.*return[[:space:]]+'([^']+)'.*/\1/")"
    check "phrase[$policy]" "$bash_phrase" "$ps_phrase"
done < <(all_policy_values)

echo ""
echo "[3] Legacy vs surfaced classification"

# Surfaced policies (offered in the simplified UI) must match between
# the two libs. Hard-coded expected set: english, exclusive_bilingual.
expected_surfaced="english,exclusive_bilingual"

# Bash side: detect via detect_legacy_content_language returning false.
bash_surfaced=""
while IFS= read -r policy; do
    [ -n "$policy" ] || continue
    if ! detect_legacy_content_language "$policy"; then
        bash_surfaced="${bash_surfaced:+$bash_surfaced,}$policy"
    fi
done < <(all_policy_values)

# PowerShell side: any policy where Test-LegacyContentLanguage returns
# false. Static check: scan for the explicit equality terms.
ps_legacy_terms="$(grep -oE "'(korean_plus_english|any)'" "$PS_LIB" \
    | sort -u | tr -d "'" | paste -sd, -)"
ps_surfaced=""
while IFS= read -r policy; do
    [ -n "$policy" ] || continue
    case ",$ps_legacy_terms," in
        *",$policy,"*) : ;;
        *) ps_surfaced="${ps_surfaced:+$ps_surfaced,}$policy" ;;
    esac
done < <(all_policy_values)

check "surfaced policies (bash)"       "$expected_surfaced" "$bash_surfaced"
check "surfaced policies (PowerShell)" "$expected_surfaced" "$ps_surfaced"

echo ""
echo "[4] Prompt-string parity (selection prompts)"

# Both libs must use the same "Selection (1-2) [default: N]" defaults
# for both prompts. Defaults: agent=2, content=1.
# The agent prompt appears first in both files; the content prompt appears
# second. Extract the digit inside the [default: N] suffix.
extract_default() {
    local file="$1" rank="$2"  # rank = "head" | "tail"
    grep -E 'Selection \(1-2\) \[default: [0-9]\]' "$file" \
        | "$rank" -1 \
        | sed -E 's/.*\[default: ([0-9])\].*/\1/'
}

bash_agent_default="$(extract_default "$BASH_LIB" head)"
bash_content_default="$(extract_default "$BASH_LIB" tail)"
ps_agent_default="$(extract_default "$PS_LIB" head)"
ps_content_default="$(extract_default "$PS_LIB" tail)"

check "agent default"   "$bash_agent_default"   "$ps_agent_default"
check "content default" "$bash_content_default" "$ps_content_default"
check "agent default = 2" "2" "$bash_agent_default"
check "content default = 1" "1" "$bash_content_default"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
