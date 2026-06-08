#!/usr/bin/env bash
# check_agents.sh — Drift guard for the 8 agent definitions that are
# duplicated across plugin/agents/ and project/.claude/agents/.
#
# plugin/ is a standalone distribution, so the two copies of each agent are
# NOT byte-identical by design:
#   - YAML frontmatter differs per layer (project carries `color:`; neither
#     carries the non-canonical `temperature:` field anymore — see #648/#662).
#   - The body genericizes exactly one repo-specific sentence (the
#     "language-specific rules" note that names rules/coding/cpp-specifics.md
#     in the project copy and a generic phrasing in the plugin copy).
#
# This guard strips the frontmatter and normalizes that single known
# sentence, then requires the agent BODIES to be otherwise identical, so the
# near-duplicate pair cannot silently diverge (e.g. a behavioral instruction
# edited in one copy but not the other).
#
# Reference drift is intentionally NOT guarded here: the plugin skill
# reference tree is a curated RE-STRUCTURING of rules/ (content is split and
# recombined across files, e.g. observability -> observability + logging), so
# a per-file 1:1 comparison would false-positive. The 4 byte-identical
# project-workflow references remain covered by check_references.sh.
#
# Exit: 0 = in sync, 2 = drift.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

AGENTS=(
    code-reviewer
    codebase-analyzer
    dependency-auditor
    documentation-writer
    qa-reviewer
    refactor-assistant
    structure-explorer
    test-strategist
)

# Strip YAML frontmatter (through the second '---') and collapse the single
# intentional repo-path sentence to a placeholder so it is not flagged.
strip_and_norm() {
    awk 'BEGIN{f=0} /^---$/{f++; next} f>=2{print}' "$1" \
        | sed -E 's/^If .*language-specific rules.*read them before starting\.$/<RULES_PATH_NOTE>/'
}

drift=0
for a in "${AGENTS[@]}"; do
    p="$ROOT_DIR/plugin/agents/$a.md"
    c="$ROOT_DIR/project/.claude/agents/$a.md"
    if [ ! -f "$p" ]; then echo "FAIL: missing plugin/agents/$a.md" >&2; drift=1; continue; fi
    if [ ! -f "$c" ]; then echo "FAIL: missing project/.claude/agents/$a.md" >&2; drift=1; continue; fi
    if ! diff -q <(strip_and_norm "$p") <(strip_and_norm "$c") >/dev/null 2>&1; then
        echo "FAIL: agent body drift: plugin/agents/$a.md vs project/.claude/agents/$a.md" >&2
        # `|| true`: diff exits 1 on differences; without it set -e/pipefail
        # would abort the loop before checking the remaining agents.
        diff <(strip_and_norm "$p") <(strip_and_norm "$c") 2>/dev/null | sed 's/^/    /' >&2 || true
        drift=1
    fi
done

if [ "$drift" -eq 0 ]; then
    echo "check_agents: OK (${#AGENTS[@]} agent pairs in sync)"
    exit 0
fi

echo "" >&2
echo "check_agents: drift detected between plugin/agents and project/.claude/agents." >&2
echo "The body content must match (frontmatter and the single rules-path" >&2
echo "sentence may differ by design). Reconcile the divergent lines above." >&2
exit 2
