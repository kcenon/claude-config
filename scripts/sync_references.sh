#!/usr/bin/env bash
# Sync canonical workflow reference files to mirror locations.
# Canonical: project/.claude/rules/workflow/
# Mirrors:   project/.claude/skills/project-workflow/reference/
#            plugin/skills/project-workflow/reference/
#
# See docs/CUSTOM_EXTENSIONS.md for the SSOT design rationale.
#
# Usage: scripts/sync_references.sh

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

missing=0
for file in "${FILES[@]}"; do
    if [ ! -f "$ROOT_DIR/$CANONICAL/$file" ]; then
        echo "ERROR: canonical file missing: $CANONICAL/$file" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    exit 1
fi

for mirror in "${MIRRORS[@]}"; do
    mkdir -p "$ROOT_DIR/$mirror"
    for file in "${FILES[@]}"; do
        cp "$ROOT_DIR/$CANONICAL/$file" "$ROOT_DIR/$mirror/$file"
        echo "synced: $CANONICAL/$file -> $mirror/$file"
    done
done

echo "sync_references: done (${#FILES[@]} files x ${#MIRRORS[@]} mirrors)"
