#!/bin/bash
# setup-labels-milestones.sh — Create labels and milestones in claude-config repo
# Idempotent: re-running is safe (label create errors on dup are caught)
#
# Usage: ./setup-labels-milestones.sh [--repo OWNER/NAME] [--dry-run]

set -u

REPO="kcenon/claude-config"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h)
      cat <<EOF
Usage: $0 [--repo OWNER/NAME] [--dry-run]

Creates labels and milestones for the memory sync EPIC tracking.

  --repo       Target repository (default: kcenon/claude-config)
  --dry-run    Print actions without executing
EOF
      exit 0 ;;
    *) echo "unknown arg: $1"; exit 64 ;;
  esac
done

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

# ---- Labels ----

# Format: name|color|description (pipe-delimited)
LABELS=(
  "area/memory|0E8A16|Memory sync system"

  "type/epic|5319E7|Epic / parent issue"
  "type/feature|1D76DB|New feature"
  "type/chore|FBCA04|Maintenance task"
  "type/docs|0075CA|Documentation"
  "type/test|BFD4F2|Tests"
  "type/ci|C5DEF5|CI/CD"

  "priority/high|D93F0B|High priority"
  "priority/medium|FBCA04|Medium priority"
  "priority/low|0E8A16|Low priority"

  "size/XS|EEEEEE|< 50 LOC"
  "size/S|DDDDDD|50-200 LOC"
  "size/M|CCCCCC|200-500 LOC"
  "size/L|BBBBBB|500-1000 LOC"

  "phase/A-validation|C2E0C6|Phase A: Validation infrastructure"
  "phase/B-trust|C2E0C6|Phase B: Trust tier model"
  "phase/C-bootstrap|C2E0C6|Phase C: Repo bootstrap"
  "phase/D-engine|C2E0C6|Phase D: Sync engine"
  "phase/E-migration|C2E0C6|Phase E: Migration"
  "phase/F-audit|C2E0C6|Phase F: Audit & review"
  "phase/G-rollout|C2E0C6|Phase G: Multi-machine rollout"
)

create_labels() {
  echo "=== Creating labels in $REPO ==="
  for entry in "${LABELS[@]}"; do
    local name color description
    IFS='|' read -r name color description <<<"$entry"
    run "gh label create '$name' --repo '$REPO' --color '$color' --description '$description' --force"
  done
  echo
}

# ---- Milestones ----

# Format: title|description
MILESTONES=(
  "memory-sync-v1-validation|Phase A: Validation infrastructure (#A1-#A5)"
  "memory-sync-v1-trust|Phase B: Trust tier model (#B1-#B4)"
  "memory-sync-v1-bootstrap|Phase C: claude-memory repo + CI (#C1-#C5)"
  "memory-sync-v1-engine|Phase D: Sync engine + hooks (#D1-#D5)"
  "memory-sync-v1-single|Phase E: Single-machine migration (#E1-#E3)"
  "memory-sync-v1-audit|Phase F: Audit & review (#F1-#F4)"
  "memory-sync-v1-multi|Phase G: Multi-machine rollout (#G1-#G3)"
)

create_milestones() {
  echo "=== Creating milestones in $REPO ==="
  for entry in "${MILESTONES[@]}"; do
    local title description
    IFS='|' read -r title description <<<"$entry"
    # gh has no built-in milestone create; use gh api
    # Idempotency: GET existing first, skip if found
    local existing
    if [[ $DRY_RUN -eq 0 ]]; then
      existing="$(gh api "repos/$REPO/milestones?state=all" --jq ".[] | select(.title==\"$title\") | .number" 2>/dev/null || echo "")"
      if [[ -n "$existing" ]]; then
        echo "[skip] milestone '$title' already exists (#$existing)"
        continue
      fi
    fi
    run "gh api 'repos/$REPO/milestones' --method POST -f title='$title' -f description='$description' -f state=open"
  done
  echo
}

main() {
  echo "Repo: $REPO"
  [[ $DRY_RUN -eq 1 ]] && echo "Mode: DRY-RUN"
  echo

  if [[ $DRY_RUN -eq 0 ]]; then
    if ! gh auth status >/dev/null 2>&1; then
      echo "ERROR: gh CLI not authenticated. Run: gh auth login"
      exit 1
    fi
  fi

  create_labels
  create_milestones

  echo "=== Verification ==="
  if [[ $DRY_RUN -eq 0 ]]; then
    echo "Labels:"
    gh label list --repo "$REPO" --search "area/memory" --limit 30 || true
    echo
    echo "Milestones:"
    gh api "repos/$REPO/milestones" --jq '.[] | "  \(.title) (#\(.number))"' || true
  else
    echo "(skipped — dry-run)"
  fi
}

main "$@"
