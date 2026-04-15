#!/bin/bash
# seed-scratch-repo.sh
# Idempotently bootstraps kcenon/batch-drift-scratch with 30 trivial typo-fix
# issues for the Tier 2 benchmark (epic #287, issue #310, sub-issue #313).
#
# SCRATCH SPACE NOTICE
# --------------------
# kcenon/batch-drift-scratch is throwaway infrastructure owned by the benchmark.
# It may be force-pushed, issue-wiped, or deleted between benchmark runs.
# Do not commit anything there that you want to keep.
#
# Usage:
#   tests/batch_drift_benchmark/seed-scratch-repo.sh            # live run
#   tests/batch_drift_benchmark/seed-scratch-repo.sh --dry-run  # preview only
#   tests/batch_drift_benchmark/seed-scratch-repo.sh --help     # usage
#
# Exit codes:
#   0  success (or dry-run)
#   1  invalid argument / precondition failure
#   2  gh CLI missing or unauthenticated

set -euo pipefail

SCRATCH_REPO="kcenon/batch-drift-scratch"
TARGET_COUNT=30
DRY_RUN=false

print_help() {
    cat <<'EOF'
seed-scratch-repo.sh — idempotently seed the Tier 2 benchmark scratch repo.

Actions (in order):
  1. Verify kcenon/batch-drift-scratch exists; create it if absent.
  2. Upsert docs/file-01.md through docs/file-30.md (single-line "teh" typo).
  3. Enumerate open issues with title prefix "fix typo in docs/file-".
  4. For each file number 1..30 without a matching open issue, create one.

Options:
  --dry-run    Print the planned actions without calling `gh`. Network-free.
  --help, -h   Show this help text and exit.

Idempotence guarantees:
  - Re-run on a fully seeded repo: zero create calls (files match via SHA, all
    issues already present).
  - Re-run on a partially seeded repo: only missing files and missing issues
    are created.
  - Safe to interrupt and resume.

Post-conditions after a successful live run:
  - Repo kcenon/batch-drift-scratch exists and is public.
  - docs/file-01.md through docs/file-30.md all contain the same one-line typo.
  - Exactly 30 open issues with titles "fix typo in docs/file-01.md" through
    "fix typo in docs/file-30.md" exist.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --help|-h) print_help; exit 0 ;;
        *) echo "ERROR: unknown argument: $arg" >&2; echo "Run with --help for usage." >&2; exit 1 ;;
    esac
done

format_nn() {
    printf '%02d' "$1"
}

file_path_for() {
    echo "docs/file-$(format_nn "$1").md"
}

issue_title_for() {
    echo "fix typo in $(file_path_for "$1")"
}

file_content_for() {
    local n="$1"
    printf '# file %s\n\nteh quick brown fox jumps over the lazy dog.\n' "$(format_nn "$n")"
}

issue_body_for() {
    local n="$1"
    local path
    path="$(file_path_for "$n")"
    cat <<EOF
## What
Fix typo \`teh\` → \`the\` in ${path} line 3.

## Why
Typo blocks downstream readers; trivial single-character fix.

## How
1. Open ${path}
2. Replace \`teh\` with \`the\`
3. Commit with message \`fix(docs): correct typo in $(basename "$path")\`

## Acceptance Criteria
- [ ] ${path} contains "the" (not "teh") on line 3
- [ ] Commit follows Conventional Commits
EOF
}

if $DRY_RUN; then
    echo "[dry-run] would verify repo: $SCRATCH_REPO (create if missing)"
    echo "[dry-run] would upsert ${TARGET_COUNT} files:"
    for n in $(seq 1 "$TARGET_COUNT"); do
        echo "[dry-run]   PUT $(file_path_for "$n")"
    done
    echo "[dry-run] would enumerate open issues with prefix 'fix typo in docs/file-'"
    echo "[dry-run] would create up to ${TARGET_COUNT} issues (one per missing file number)"
    for n in $(seq 1 "$TARGET_COUNT"); do
        echo "[dry-run]   issue: $(issue_title_for "$n")"
    done
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not installed" >&2
    exit 2
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh CLI not authenticated (run: gh auth login)" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq not installed" >&2
    exit 2
fi

echo "==> verifying $SCRATCH_REPO"
if ! gh repo view "$SCRATCH_REPO" >/dev/null 2>&1; then
    echo "    repo missing — creating"
    gh repo create "$SCRATCH_REPO" --public --add-readme \
        --description "Throwaway scratch repo for claude-config Tier 2 benchmark (#287)"
else
    echo "    repo exists"
fi

echo "==> upserting ${TARGET_COUNT} typo files"
for n in $(seq 1 "$TARGET_COUNT"); do
    path="$(file_path_for "$n")"
    content="$(file_content_for "$n")"
    b64="$(printf '%s' "$content" | base64 | tr -d '\n')"

    sha=""
    if existing=$(gh api "repos/$SCRATCH_REPO/contents/$path" 2>/dev/null); then
        sha="$(printf '%s' "$existing" | jq -r '.sha // empty')"
        existing_content_b64="$(printf '%s' "$existing" | jq -r '.content // empty' | tr -d '\n')"
        if [ "$existing_content_b64" = "$b64" ]; then
            continue
        fi
    fi

    put_args=(--method PUT "repos/$SCRATCH_REPO/contents/$path"
              -f "message=chore: seed $path for benchmark"
              -f "content=$b64")
    if [ -n "$sha" ]; then
        put_args+=(-f "sha=$sha")
    fi
    gh api "${put_args[@]}" >/dev/null
    echo "    upserted $path"
done

echo "==> enumerating existing typo issues"
existing_titles=$(gh issue list --repo "$SCRATCH_REPO" --state open --limit 200 \
    --json title -q '.[] | select(.title | startswith("fix typo in docs/file-")) | .title')

created=0
skipped=0
for n in $(seq 1 "$TARGET_COUNT"); do
    title="$(issue_title_for "$n")"
    if printf '%s\n' "$existing_titles" | grep -Fxq "$title"; then
        skipped=$((skipped + 1))
        continue
    fi
    body="$(issue_body_for "$n")"
    gh issue create --repo "$SCRATCH_REPO" --title "$title" --body "$body" >/dev/null
    created=$((created + 1))
    echo "    created issue: $title"
done

echo ""
echo "==> seed complete: created=${created}, skipped=${skipped}, target=${TARGET_COUNT}"
