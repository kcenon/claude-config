#!/usr/bin/env bash
# Verify mirror reference files match the canonical copy.
# Exits with 2 if any mirror drifts from canonical; 0 otherwise.
#
# Canonical: project/.claude/rules/workflow/
# Mirrors:   project/.claude/skills/project-workflow/reference/
#            plugin/skills/project-workflow/reference/
#
# Usage: scripts/check_references.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

CANONICAL="project/.claude/rules/workflow"
MIRRORS=(
    "project/.claude/skills/project-workflow/reference"
    "plugin/skills/project-workflow/reference"
)
FILES=(
    "git-commit-format.md"
    "github-issue-5w1h.md"
    "github-pr-5w1h.md"
    "performance-analysis.md"
)

drift=0
for file in "${FILES[@]}"; do
    src="$ROOT_DIR/$CANONICAL/$file"
    if [ ! -f "$src" ]; then
        echo "FAIL: canonical missing: $CANONICAL/$file" >&2
        drift=1
        continue
    fi
    for mirror in "${MIRRORS[@]}"; do
        dst="$ROOT_DIR/$mirror/$file"
        if [ ! -f "$dst" ]; then
            echo "FAIL: mirror missing: $mirror/$file" >&2
            drift=1
            continue
        fi
        if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
            echo "FAIL: drift detected: $mirror/$file" >&2
            diff -u "$src" "$dst" | head -20 >&2 || true
            drift=1
        fi
    done
done

if [ "$drift" -eq 0 ]; then
    echo "check_references: OK (all ${#FILES[@]} files match across ${#MIRRORS[@]} mirrors)"
    exit 0
fi

echo "" >&2
echo "check_references: drift detected. Run scripts/sync_references.sh to regenerate mirrors." >&2
exit 2
