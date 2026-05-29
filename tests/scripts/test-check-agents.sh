#!/bin/bash
# test-check-agents.sh — tests for scripts/check_agents.sh (deep-audit P1-B).
# Verifies the plugin<->project agent drift guard: in-sync passes, a body
# divergence fails (exit 2), and frontmatter-only / rules-path-sentence
# differences are tolerated by design.
# Run: bash tests/scripts/test-check-agents.sh

set -u
PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1
ROOT="$(pwd)"

# Build an isolated sandbox repo containing all 8 agent pairs plus a copy of
# the guard, so mutations never touch the real tree. The guard derives its
# root from its own location, so it inspects the sandbox.
mk_sandbox() {
    local d="$1"
    mkdir -p "$d/scripts" "$d/plugin/agents" "$d/project/.claude/agents"
    cp "$ROOT/scripts/check_agents.sh" "$d/scripts/"
    cp "$ROOT"/plugin/agents/*.md "$d/plugin/agents/"
    cp "$ROOT"/project/.claude/agents/*.md "$d/project/.claude/agents/"
}

assert_exit() {
    local expected="$1" actual="$2" label="$3"
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $label — expected exit $expected, got $actual")
        echo "  FAIL: $label (exit $actual)"
    fi
}

echo "=== check_agents.sh tests ==="
echo ""

# 1. The real repository is in sync.
bash scripts/check_agents.sh >/dev/null 2>&1
assert_exit 0 $? "real tree in sync -> exit 0"

# 2. A body divergence is flagged.
sb=$(mktemp -d); mk_sandbox "$sb"
printf '\nEXTRA BODY LINE\n' >> "$sb/plugin/agents/qa-reviewer.md"
( cd "$sb" && bash scripts/check_agents.sh >/dev/null 2>&1 ); rc=$?
assert_exit 2 $rc "body divergence -> exit 2"
rm -rf "$sb"

# 3. A frontmatter-only difference is tolerated (frontmatter is stripped).
sb=$(mktemp -d); mk_sandbox "$sb"
sed -i '1a color: teal' "$sb/plugin/agents/test-strategist.md"
( cd "$sb" && bash scripts/check_agents.sh >/dev/null 2>&1 ); rc=$?
assert_exit 0 $rc "frontmatter-only diff -> exit 0"
rm -rf "$sb"

# 4. The intentional rules-path sentence variant is normalized (tolerated).
sb=$(mktemp -d); mk_sandbox "$sb"
sed -i 's|^If .*language-specific rules.*read them before starting\.$|If any language-specific rules exist, read them before starting.|' \
    "$sb/plugin/agents/code-reviewer.md"
( cd "$sb" && bash scripts/check_agents.sh >/dev/null 2>&1 ); rc=$?
assert_exit 0 $rc "rules-path sentence variant -> exit 0"
rm -rf "$sb"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do echo "  $err"; done
    exit 1
fi
exit 0
