#!/bin/bash
# run-semantic-review-tests.sh -- Integration tests for semantic-review.sh.
#
# Exercises the semantic-review.sh script against synthesized fixtures and
# verifies the documented exit-code contract:
#    0  success (review generated, optionally committed and notified)
#    1  claude invocation failed
#    2  recent review exists (< 25 days old); skip
#   64  usage error
#
# The tests do NOT require the real `claude` CLI; the missing-CLI path is
# itself a documented failure mode and is asserted directly. The dry-run path
# is asserted as the successful no-network analogue.
#
# Bash 3.2 compatible.
#
# Usage:
#   tests/memory/run-semantic-review-tests.sh
#   tests/memory/run-semantic-review-tests.sh --script <path>
#   tests/memory/run-semantic-review-tests.sh --help|-h
#
# Exit codes:
#   0  all assertions passed
#   1  one or more assertions failed

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/semantic-review.sh"

print_help() {
  cat <<'EOF'
run-semantic-review-tests.sh -- integration tests for semantic-review.sh.

USAGE:
  run-semantic-review-tests.sh                 run with default script path
  run-semantic-review-tests.sh --script <path> override script location
  run-semantic-review-tests.sh --help | -h     show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    --script)
      if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
        printf 'error: --script requires a path argument\n' >&2
        exit 1
      fi
      SCRIPT="$2"
      shift 2
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      print_help >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$SCRIPT" ]]; then
  printf 'fatal: semantic-review.sh not found at %s\n' "$SCRIPT" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=("")

record_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$1"
}

record_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILURES+=("$1: $2")
  printf '[FAIL] %s (%s)\n' "$1" "$2"
}

assert_exit() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    record_pass "$label"
  else
    record_fail "$label" "expected exit $expected, got $actual"
  fi
}

mk_workdir() {
  local d
  d="$(mktemp -d -t semantic-review-test.XXXXXX)"
  mkdir -p "$d/memories" "$d/audit"
  printf '%s' "$d"
}

# ----- assertion: --help exits 0 -----
"$SCRIPT" --help >/dev/null 2>&1
assert_exit 'help-flag' "$?" 0

# ----- assertion: unknown flag exits 64 -----
"$SCRIPT" --not-a-real-flag >/dev/null 2>&1
assert_exit 'usage-error' "$?" 64

# ----- assertion: missing memories dir exits 64 -----
"$SCRIPT" --memories-dir /tmp/__missing_dir_for_semantic_review_test__ \
  --no-push --no-notify >/dev/null 2>&1
assert_exit 'missing-memories-dir' "$?" 64

# ----- assertion: dry-run with fixtures exits 0 and prints prompt -----
WD="$(mk_workdir)"
cat > "$WD/memories/sample.md" <<'EOF'
---
type: project
---

Always use uppercase for SQL keywords.
EOF

OUT="$("$SCRIPT" --dry-run --memories-dir "$WD/memories" 2>&1)"
RC=$?
assert_exit 'dry-run-exit' "$RC" 0
if printf '%s' "$OUT" | grep -q 'Memories follow'; then
  record_pass 'dry-run-prompt-header'
else
  record_fail 'dry-run-prompt-header' 'expected prompt header in output'
fi
if printf '%s' "$OUT" | grep -q 'sample.md'; then
  record_pass 'dry-run-includes-memory'
else
  record_fail 'dry-run-includes-memory' 'expected fixture filename in output'
fi
rm -rf "$WD"

# ----- assertion: empty memories dir generates no-memories report -----
WD="$(mk_workdir)"
"$SCRIPT" --memories-dir "$WD/memories" --no-push --no-notify >/dev/null 2>&1
RC=$?
assert_exit 'empty-memories-exit' "$RC" 0
REPORT="$WD/audit/semantic-$(date -u +'%Y-%m').md"
if [[ -f "$REPORT" ]]; then
  if grep -q 'Status: no-memories' "$REPORT"; then
    record_pass 'empty-memories-status'
  else
    record_fail 'empty-memories-status' 'report missing no-memories status'
  fi
else
  record_fail 'empty-memories-report' "expected report at $REPORT"
fi
rm -rf "$WD"

# ----- assertion: idempotency -- recent report yields exit 2 -----
WD="$(mk_workdir)"
touch "$WD/audit/semantic-$(date -u +'%Y-%m').md"
"$SCRIPT" --memories-dir "$WD/memories" --no-push --no-notify >/dev/null 2>&1
assert_exit 'idempotent-skip' "$?" 2
rm -rf "$WD"

# ----- assertion: missing claude CLI yields exit 1 (real run path) -----
# We force a clean PATH that excludes claude. The fixture has at least one
# memory so the script reaches the invoke_claude step.
WD="$(mk_workdir)"
cat > "$WD/memories/m.md" <<'EOF'
---
type: workflow
---

Prefer rebase over merge for feature branches.
EOF
PATH=/usr/bin:/bin "$SCRIPT" --memories-dir "$WD/memories" \
  --no-push --no-notify >/dev/null 2>&1
assert_exit 'missing-claude-cli' "$?" 1
rm -rf "$WD"

# ----- summary -----
printf '\n----- summary -----\n'
printf 'Passed: %d\n' "$PASS_COUNT"
printf 'Failed: %d\n' "$FAIL_COUNT"
if (( FAIL_COUNT > 0 )); then
  printf '\nFailures:\n'
  for i in $(seq 1 $((${#FAILURES[@]} - 1))); do
    printf '  - %s\n' "${FAILURES[$i]}"
  done
  exit 1
fi
exit 0
