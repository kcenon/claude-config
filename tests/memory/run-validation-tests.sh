#!/bin/bash
# run-validation-tests.sh -- Integration tests for the three memory validators.
#
# Exercises validate.sh, secret-check.sh, and injection-check.sh against a
# directory tree of fixtures and asserts each tool produces the documented exit
# code (and, where applicable, the expected substring in its output).
#
# Per docs/MEMORY_VALIDATION_SPEC.md section 7 the validators share a stable
# exit-code contract:
#   validate.sh        : 0 PASS, 1 FAIL-STRUCT, 2 FAIL-FORMAT, 3 WARN-SEMANTIC
#   secret-check.sh    : 0 CLEAN, 1 SECRET-DETECTED
#   injection-check.sh : 0 CLEAN, 3 FLAGGED
#
# Bash 3.2 compatible (macOS default) per spec section 8.
#
# Usage:
#   tests/memory/run-validation-tests.sh                   default invocation
#   tests/memory/run-validation-tests.sh --validators-dir <p>
#   tests/memory/run-validation-tests.sh --help|-h
#
# Exit codes:
#   0  all assertions passed
#   1  one or more assertions failed (or fatal misconfiguration)
#
# Fixture layout:
#   fixtures/valid/             validate.sh expects exit 0
#   fixtures/invalid-validate/  validate.sh expects exit per *.expected
#   fixtures/secret-positive/   secret-check.sh expects exit 1
#   fixtures/injection-positive/ injection-check.sh expects exit 3
#   fixtures/baseline/          optional; the 17 real memories. Skipped if empty.

set -u

# ----- locate self and validators -----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATORS_DIR="${REPO_ROOT}/scripts/memory"

print_help() {
  cat <<'EOF'
run-validation-tests.sh -- integration test runner for the memory validators.

USAGE:
  run-validation-tests.sh                          run with default validator path
  run-validation-tests.sh --validators-dir <path>  override validator location
  run-validation-tests.sh --help | -h              show this help

EXIT CODES:
  0   all assertions passed
  1   one or more assertions failed
EOF
}

# ----- argument parsing -----
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    --validators-dir)
      if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
        printf 'error: --validators-dir requires a path argument\n' >&2
        exit 1
      fi
      VALIDATORS_DIR="$2"
      shift 2
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      print_help >&2
      exit 1
      ;;
  esac
done

VALIDATE_SH="${VALIDATORS_DIR}/validate.sh"
SECRET_SH="${VALIDATORS_DIR}/secret-check.sh"
INJECTION_SH="${VALIDATORS_DIR}/injection-check.sh"

# ----- counters and failure record -----
PASS_COUNT=0
FAIL_COUNT=0
# Pre-declared so empty-array expansion is safe under Bash 3.2 + `set -u`.
FAILURES=("")

record_pass() {
  local label="$1"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$label"
}

record_fail() {
  local label="$1"
  local reason="$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILURES+=("${label}: ${reason}")
  printf '[FAIL] %s (%s)\n' "$label" "$reason"
}

# ----- preflight -----
if [[ ! -d "$FIXTURES_DIR" ]]; then
  printf 'fatal: fixtures directory not found: %s\n' "$FIXTURES_DIR" >&2
  exit 1
fi

for tool in "$VALIDATE_SH" "$SECRET_SH" "$INJECTION_SH"; do
  if [[ ! -f "$tool" ]]; then
    printf 'fatal: validator not found: %s\n' "$tool" >&2
    exit 1
  fi
  if [[ ! -x "$tool" ]] && ! [[ -r "$tool" ]]; then
    printf 'fatal: validator not readable: %s\n' "$tool" >&2
    exit 1
  fi
done

bash_version="$(bash --version | head -1 || true)"
printf 'Validator dir : %s\n' "$VALIDATORS_DIR"
printf 'Fixtures dir  : %s\n' "$FIXTURES_DIR"
printf 'Bash version  : %s\n' "$bash_version"
printf '\n'

# ----- helper: read a single key from a *.expected file -----
# .expected file format (one key per line):
#   exit:<code>
#   contains:<substring>
# Unknown keys are ignored (forward-compatible).
expected_get() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  grep "^${key}:" "$file" 2>/dev/null | head -1 | sed "s/^${key}://"
}

# ----- helper: count files in a directory matching a glob -----
# Echoes 0 when the directory is missing or empty. README.md and MEMORY.md
# are treated as documentation/index files and excluded from the count, so
# they never enter validator runs nor fixture-presence checks.
count_md_files() {
  local d="$1"
  local n=0
  local f base
  if [[ ! -d "$d" ]]; then
    echo 0
    return 0
  fi
  for f in "$d"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "README.md" ]] && continue
    [[ "$base" == "MEMORY.md" ]] && continue
    n=$((n + 1))
  done
  echo "$n"
}

# ----- assertion 1: valid fixtures -> validate.sh exit 0 -----
printf -- '--- valid fixtures (validate.sh expects exit 0) ---\n'
valid_dir="${FIXTURES_DIR}/valid"
n_valid="$(count_md_files "$valid_dir")"
if [[ "$n_valid" -eq 0 ]]; then
  printf '[WARN] no fixtures in %s\n' "$valid_dir"
else
  for f in "$valid_dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "README.md" ]] && continue
    [[ "$base" == "MEMORY.md" ]] && continue
    label="valid/${base}"
    output="$(bash "$VALIDATE_SH" "$f" 2>&1)"
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
      record_pass "$label"
    else
      record_fail "$label" "expected exit 0, got $rc"
    fi
  done
fi
printf '\n'

# ----- assertion 2: invalid-validate fixtures -> per .expected file -----
printf -- '--- invalid-validate fixtures (validate.sh per *.expected) ---\n'
invalid_dir="${FIXTURES_DIR}/invalid-validate"
n_invalid="$(count_md_files "$invalid_dir")"
if [[ "$n_invalid" -eq 0 ]]; then
  printf '[WARN] no fixtures in %s\n' "$invalid_dir"
else
  for f in "$invalid_dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "README.md" ]] && continue
    [[ "$base" == "MEMORY.md" ]] && continue
    label="invalid-validate/${base}"
    expected_file="${f}.expected"
    expected_exit="$(expected_get "$expected_file" 'exit')"
    expected_contains="$(expected_get "$expected_file" 'contains')"
    # default expectation: exit 1 (FAIL-STRUCT) when no .expected file present.
    if [[ -z "$expected_exit" ]]; then
      expected_exit=1
    fi
    output="$(bash "$VALIDATE_SH" "$f" 2>&1)"
    rc=$?
    ok=1
    reason=""
    if [[ "$rc" -ne "$expected_exit" ]]; then
      ok=0
      reason="expected exit $expected_exit, got $rc"
    elif [[ -n "$expected_contains" ]]; then
      if ! printf '%s' "$output" | grep -q -F -- "$expected_contains"; then
        ok=0
        reason="output missing substring '${expected_contains}'"
      fi
    fi
    if [[ "$ok" -eq 1 ]]; then
      detail="exit ${rc}"
      [[ -n "$expected_contains" ]] && detail="${detail}, contains '${expected_contains}'"
      record_pass "${label} (${detail})"
    else
      record_fail "$label" "$reason"
    fi
  done
fi
printf '\n'

# ----- assertion 3: secret-positive fixtures -> secret-check.sh exit 1 -----
printf -- '--- secret-positive fixtures (secret-check.sh expects exit 1) ---\n'
secret_dir="${FIXTURES_DIR}/secret-positive"
n_secret="$(count_md_files "$secret_dir")"
if [[ "$n_secret" -eq 0 ]]; then
  printf '[WARN] no fixtures in %s\n' "$secret_dir"
else
  for f in "$secret_dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "README.md" ]] && continue
    [[ "$base" == "MEMORY.md" ]] && continue
    label="secret-positive/${base}"
    output="$(bash "$SECRET_SH" "$f" 2>&1)"
    rc=$?
    if [[ "$rc" -eq 1 ]]; then
      record_pass "${label} (exit 1)"
    else
      record_fail "$label" "expected exit 1, got $rc"
    fi
  done
fi
printf '\n'

# ----- assertion 4: injection-positive fixtures -> injection-check.sh exit 3 -----
printf -- '--- injection-positive fixtures (injection-check.sh expects exit 3) ---\n'
injection_dir="${FIXTURES_DIR}/injection-positive"
n_injection="$(count_md_files "$injection_dir")"
if [[ "$n_injection" -eq 0 ]]; then
  printf '[WARN] no fixtures in %s\n' "$injection_dir"
else
  for f in "$injection_dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "README.md" ]] && continue
    [[ "$base" == "MEMORY.md" ]] && continue
    label="injection-positive/${base}"
    output="$(bash "$INJECTION_SH" "$f" 2>&1)"
    rc=$?
    if [[ "$rc" -eq 3 ]]; then
      record_pass "${label} (exit 3)"
    else
      record_fail "$label" "expected exit 3, got $rc"
    fi
  done
fi
printf '\n'

# ----- assertion 5: baseline regression -----
# The 17 baseline files live on the owner's machine
# (~/.claude/projects/-Users-raphaelshin-Sources/memory/) per spec section 9.
# They are not portable, so the runner skips this assertion when fixtures/baseline/
# is empty. When baseline files are present, expected verdicts are:
#   validate.sh        --all : 0 pass, 17 warn, 0 fail
#   secret-check.sh    --all : 18 clean, 0 with findings
#   injection-check.sh --all : 14 clean, 3 flagged
printf -- '--- baseline regression ---\n'
baseline_dir="${FIXTURES_DIR}/baseline"
n_baseline="$(count_md_files "$baseline_dir")"
if [[ "$n_baseline" -eq 0 ]]; then
  printf '[SKIP] baseline regression (no files in %s)\n' "$baseline_dir"
  printf '       see fixtures/baseline/README.md for setup instructions\n'
else
  # validate.sh expects 0 pass, 17 warn, 0 fail (pre-Phase-2 baseline).
  vout="$(bash "$VALIDATE_SH" --all "$baseline_dir" 2>&1)"
  vsummary="$(printf '%s\n' "$vout" | grep -E '^Summary:' | tail -1)"
  if printf '%s' "$vsummary" | grep -q '0 pass, 17 warn, 0 fail'; then
    record_pass "baseline regression: validate.sh 0 pass / 17 warn / 0 fail"
  else
    record_fail "baseline regression: validate.sh" "summary mismatch (got '${vsummary}')"
  fi

  # secret-check.sh expects 18 clean, 0 with findings.
  sout="$(bash "$SECRET_SH" --all "$baseline_dir" 2>&1)"
  ssummary="$(printf '%s\n' "$sout" | grep -E '^Summary:' | tail -1)"
  if printf '%s' "$ssummary" | grep -q '18 clean, 0 with findings'; then
    record_pass "baseline regression: secret-check.sh 18 clean"
  else
    record_fail "baseline regression: secret-check.sh" "summary mismatch (got '${ssummary}')"
  fi

  # injection-check.sh expects 14 clean, 3 flagged.
  iout="$(bash "$INJECTION_SH" --all "$baseline_dir" 2>&1)"
  isummary="$(printf '%s\n' "$iout" | grep -E '^Summary:' | tail -1)"
  if printf '%s' "$isummary" | grep -q '14 clean, 3 flagged'; then
    record_pass "baseline regression: injection-check.sh 14 clean / 3 flagged"
  else
    record_fail "baseline regression: injection-check.sh" "summary mismatch (got '${isummary}')"
  fi
fi
printf '\n'

# ----- summary -----
printf '====================================================\n'
printf 'Total: %d pass, %d fail\n' "$PASS_COUNT" "$FAIL_COUNT"
printf '====================================================\n'

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  printf '\nFailures:\n'
  # FAILURES has a leading empty sentinel; iterate from index 1 only when
  # there's something past the sentinel. This guard keeps the empty-array
  # expansion safe under Bash 3.2 + `set -u`.
  if (( ${#FAILURES[@]} > 1 )); then
    local_i=1
    while (( local_i < ${#FAILURES[@]} )); do
      printf '  %s\n' "${FAILURES[$local_i]}"
      local_i=$((local_i + 1))
    done
  fi
  exit 1
fi

exit 0
