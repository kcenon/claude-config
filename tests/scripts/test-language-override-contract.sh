#!/bin/bash
# test-language-override-contract.sh
# Contract regression for issue #762.
#
# prompt_language_profile() documents that the non-interactive env overrides
# AGENT_LANGUAGE and CONTENT_LANGUAGE are honored INDEPENDENTLY. The prompt
# unification (#757) silently broke this: it skipped the interactive prompt
# only when BOTH were set (AND-gate), so presetting just one was clobbered to
# the Hybrid default. This test locks the restored independent-override
# contract across the full 2x2 matrix of (AGENT set?, CONTENT set?).
#
# Each case runs in a clean subshell via `env -u AGENT_LANGUAGE -u
# CONTENT_LANGUAGE bash -c ...` so no ambient value leaks in. The real lib is
# sourced inside that subshell, the env under test is exported, and the
# resolved (AGENT_LANGUAGE, CONTENT_LANGUAGE, AGENT_DISPLAY_LANG) triple is
# emitted as a single comma-joined line for comparison.
#
# Run: bash tests/scripts/test-language-override-contract.sh
# Exit: 0 on all-pass, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASH_LIB="$REPO_ROOT/scripts/lib/install-prompts.sh"

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
        echo "    expected: $expected"
        echo "    actual:   $actual"
    fi
}

# emit_triple <stdin-feed> <env-assignments...>
# Runs prompt_language_profile in a pristine subshell (AGENT_LANGUAGE and
# CONTENT_LANGUAGE unset by env -u), applies the requested presets, feeds the
# given string on stdin (for the interactive case), and echoes the resolved
# triple "AGENT,CONTENT,DISPLAY".
emit_triple() {
    local feed="$1"
    shift
    # %b so "\n" in the feed is rendered as a real newline for `read`.
    printf '%b' "$feed" | env -u AGENT_LANGUAGE -u CONTENT_LANGUAGE "$@" \
        bash -c '
            source "$0" >/dev/null 2>&1
            prompt_language_profile >/dev/null 2>&1
            printf "%s,%s,%s" "$AGENT_LANGUAGE" "$CONTENT_LANGUAGE" "$AGENT_DISPLAY_LANG"
        ' "$BASH_LIB"
}

echo "=== Language override contract test (#762) ==="
echo ""

echo "[1] only AGENT_LANGUAGE set -> honored; CONTENT defaults to english (the #757 bug)"
actual="$(emit_triple "" AGENT_LANGUAGE=english)"
check "AGENT=english, CONTENT unset" "english,english,English" "$actual"

actual="$(emit_triple "" AGENT_LANGUAGE=korean)"
check "AGENT=korean, CONTENT unset" "korean,english,Korean" "$actual"

echo ""
echo "[2] only CONTENT_LANGUAGE set -> honored; AGENT defaults to korean"
actual="$(emit_triple "" CONTENT_LANGUAGE=exclusive_bilingual)"
check "CONTENT=exclusive_bilingual, AGENT unset" "korean,exclusive_bilingual,Korean" "$actual"

actual="$(emit_triple "" CONTENT_LANGUAGE=english)"
check "CONTENT=english, AGENT unset" "korean,english,Korean" "$actual"

echo ""
echo "[3] both set -> both honored (no prompt)"
actual="$(emit_triple "" AGENT_LANGUAGE=english CONTENT_LANGUAGE=exclusive_bilingual)"
check "AGENT=english, CONTENT=exclusive_bilingual" "english,exclusive_bilingual,English" "$actual"

echo ""
echo "[4] neither set -> interactive prompt (selection fed on stdin)"
# Selection 1 = English Unified.
actual="$(emit_triple "1\n")"
check "neither set, selection 1" "english,english,English" "$actual"

# Selection 2 = Korean Unified (exclusive).
actual="$(emit_triple "2\n")"
check "neither set, selection 2" "korean,exclusive_bilingual,Korean" "$actual"

# Empty selection = default 3 = Hybrid.
actual="$(emit_triple "\n")"
check "neither set, default (Hybrid)" "korean,english,Korean" "$actual"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ]
