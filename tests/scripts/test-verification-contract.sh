#!/bin/bash
# test-verification-contract.sh -- the harness references bound every review
# loop by the verification contract (#1057).
#
# A retry count limits how often a review loop runs, not what it checks again.
# global/skills/_internal/harness/reference/verification-contract.md is where
# that is settled, so this suite checks that
#   - the contract keeps its rules and both brief templates,
#   - the recheck brief asks neither for a second look at what passed nor for
#     new exploration, and
#   - every harness reference that mentions a review loop links to the contract.
#
# Run: bash tests/scripts/test-verification-contract.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS="$REPO_ROOT/global/skills/_internal"
CONTRACT="$SKILLS/harness/reference/verification-contract.md"
CONTRACT_NAME="verification-contract.md"

PASS=0
FAIL=0
ERRORS=()

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); echo "  FAIL: $1"; }

# Words that mean a review loop: the two patterns built on one, and the ways
# the references describe going round again. A leading boundary keeps
# "architecture-review" from reading as "re-review".
LOOP_RE='Producer-Reviewer|Generator-Evaluator|(review|revision|retry) loop|(^|[^[:alnum:]])re-review|recheck|revision (request|feedback)|max(imum)? [0-9-]+ rounds|maximum retry count'

# What a recheck brief must not ask for.
RECHECK_FORBIDDEN_RE='again|re-?confirm|re-?verify|explor|new inputs|probe|fuzz|anything else|whole unit'

# mentions_loop <file>: true when the file mentions a review loop.
mentions_loop() {
    grep -qiE "$LOOP_RE" "$1"
}

# unlinked_loop_files <file>...: prints each file that mentions a review loop
# and does not name the contract.
unlinked_loop_files() {
    local f
    for f in "$@"; do
        [ -f "$f" ] || continue
        if mentions_loop "$f" && ! grep -qF "$CONTRACT_NAME" "$f"; then
            printf '%s\n' "$f"
        fi
    done
}

# fenced_block_after <heading> <file>: the first fenced block under a heading.
fenced_block_after() {
    awk -v heading="$1" '
        $0 == heading { armed = 1; next }
        armed && /^```/ { if (inside) exit; inside = 1; next }
        armed && inside { print }
    ' "$2"
}

echo "=== verification contract tests ==="
echo ""

echo "[The contract defines its rules]"
if [ -f "$CONTRACT" ]; then
    pass "verification-contract.md exists"
else
    fail "verification-contract.md is missing"
    echo ""
    echo "=== Results: $PASS passed, $FAIL failed ==="
    exit 1
fi
for heading in "Evidence ledger" "Scope-matched checks" "Round budget" "Severity scope" \
    "Conflict rule" "Stop signal" "Role guidance" "Brief templates"; do
    if grep -qE "^## [0-9]+\. $heading\$" "$CONTRACT"; then
        pass "section: $heading"
    else
        fail "the contract has no section '$heading'"
    fi
done
for needle in 'git rev-parse HEAD' 'git hash-object --stdin' 'one full review and one narrow recheck' \
    'two consecutive rounds'; do
    if grep -qF -- "$needle" "$CONTRACT"; then
        pass "the contract states: $needle"
    else
        fail "the contract no longer states: $needle"
    fi
done

echo ""
echo "[Both brief templates are there, and the recheck brief stays narrow]"
first_brief="$(fenced_block_after '### First review brief' "$CONTRACT")"
recheck_brief="$(fenced_block_after '### Recheck brief' "$CONTRACT")"
if [ -n "$first_brief" ] && printf '%s\n' "$first_brief" | grep -q 'Blocker'; then
    pass "first review brief template, with the severity levels"
else
    fail "the first review brief template is missing or has no severity levels"
fi
if [ -n "$recheck_brief" ] && printf '%s\n' "$recheck_brief" | grep -q 'Judge only the findings listed above'; then
    pass "recheck brief template, limited to the listed findings"
else
    fail "the recheck brief template is missing or no longer limits itself to the listed findings"
fi
forbidden="$(printf '%s\n' "$recheck_brief" | grep -niE "$RECHECK_FORBIDDEN_RE" || true)"
if [ -z "$forbidden" ]; then
    pass "the recheck brief asks for no second look at passed items and no exploration"
else
    fail "the recheck brief asks for more than the listed findings: $forbidden"
fi

echo ""
echo "[The check itself tells a linked mention from an unlinked one]"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/verification-contract.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
printf '%s\n' '# Guide' 'Use Producer-Reviewer with a maximum retry count.' > "$SCRATCH/unlinked.md"
printf '%s\n' '# Guide' 'The recheck follows `verification-contract.md`.' > "$SCRATCH/linked.md"
printf '%s\n' '# Guide' 'See docs/architecture-review-notes.md for the layout.' > "$SCRATCH/no-loop.md"
got="$(unlinked_loop_files "$SCRATCH/unlinked.md" "$SCRATCH/linked.md" "$SCRATCH/no-loop.md")"
if [ "$got" = "$SCRATCH/unlinked.md" ]; then
    pass "an unlinked mention is reported, a linked one and a file without a loop are not"
else
    fail "the check reported: '$got'"
fi

echo ""
echo "[Every harness reference that mentions a review loop links to the contract]"
checked=0
loop_files=0
for f in "$SKILLS/harness/SKILL.md" "$SKILLS"/harness/reference/*.md "$SKILLS/fleet-orchestrator/SKILL.md"; do
    [ -f "$f" ] || continue
    [ "$f" = "$CONTRACT" ] && continue
    checked=$((checked + 1))
    rel="${f#"$REPO_ROOT"/}"
    if ! mentions_loop "$f"; then
        continue
    fi
    loop_files=$((loop_files + 1))
    if [ -z "$(unlinked_loop_files "$f")" ]; then
        pass "$rel links to the contract"
    else
        fail "$rel mentions a review loop without linking to $CONTRACT_NAME"
    fi
done
if [ "$checked" -ge 9 ] && [ "$loop_files" -ge 5 ]; then
    pass "files checked: $checked, of which $loop_files mention a review loop"
else
    fail "expected at least 9 files and 5 with a review loop, found $checked and $loop_files"
fi

echo ""
echo "[The shared invariants carry the round budget and the stop signal]"
INVARIANTS="$SKILLS/_shared/invariants.md"
for needle in 'Round budget: one full review and one narrow recheck per unit' \
    'Stop signal: halt and report after two consecutive rounds'; do
    if grep -qF -- "$needle" "$INVARIANTS"; then
        pass "invariants.md: ${needle%%:*}"
    else
        fail "invariants.md no longer states: $needle"
    fi
done
if grep -qF "$CONTRACT_NAME" "$INVARIANTS"; then
    pass "invariants.md links to the contract"
else
    fail "invariants.md does not link to $CONTRACT_NAME"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
exit 0
