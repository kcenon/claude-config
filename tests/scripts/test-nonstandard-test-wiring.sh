#!/bin/bash
# Repo-wide guard for tracked test entrypoints OUTSIDE tests/scripts/test-*.
#
# The focused sibling gate tests/scripts/test-ci-wiring.sh (#823) owns
# tests/scripts/test-*. This gate (#833) covers every other tracked .sh/.ps1
# under tests/ and fails when such a file is neither executed by CI nor
# explicitly classified in tests/nonstandard-test-registry.txt.
#
# A nonstandard entrypoint is "accounted for" when, in priority order, it is:
#   1. directly wired   - invoked by an executable workflow run command
#   2. runner-covered   - swept by a wired shared runner (see COVERAGE below)
#   3. registry-listed  - classified helper / manual / obsolete with a reason
# Anything else is an orphan and fails the gate.
#
# Detection of "wired" reuses tests/scripts/lib/ci-wiring-lib.sh, the single
# source of truth shared with #823, so path-filter mentions, comments, and
# echo statements never count as wiring here either.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
REGISTRY_FILE="$REPO_ROOT/tests/nonstandard-test-registry.txt"

# shellcheck source=tests/scripts/lib/ci-wiring-lib.sh
. "$SCRIPT_DIR/lib/ci-wiring-lib.sh"

PASS=0
FAIL=0
WIRED=0
COVERED=0
CLASSIFIED=0

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t nonstd-wiring)"
trap 'rm -rf -- "$WORK"' EXIT

RUN_COMMANDS="$WORK/run-commands.txt"
REGISTRY_PATHS="$WORK/registry-paths.txt"
: > "$RUN_COMMANDS"
: > "$REGISTRY_PATHS"

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# ── Shared-runner coverage table ───────────────────────────────────────
# A file is runner-covered when it matches one of these globs AND the runner
# that sweeps that glob is itself directly wired into a workflow. The runner
# scripts themselves are directly wired, so they never rely on this table.
is_runner_covered() {
    case "$1" in
        tests/hooks/test-*.sh)
            is_workflow_wired "tests/hooks/test-runner.sh" && return 0 ;;
        tests/hooks/test-*.ps1)
            is_workflow_wired "tests/hooks/test-runner.ps1" && return 0 ;;
    esac
    return 1
}

is_workflow_wired() {
    commands_reference_path "$1" "$RUN_COMMANDS"
}

# ── Collect executable run commands from every workflow ────────────────
if [ ! -d "$WORKFLOWS_DIR" ]; then
    fail "workflow directory is missing: .github/workflows"
else
    while IFS= read -r workflow; do
        extract_run_commands "$workflow" >> "$RUN_COMMANDS"
    done < <(find "$WORKFLOWS_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
fi

# ── This gate must be triggered by any new tracked test file ───────────
# Wiring the checker without a repo-wide tests/** PR trigger would leave a
# silent bypass: a new orphan added outside the narrow path filters would
# never run the gate that is supposed to catch it.
META_TEST_PATH='tests/scripts/test-nonstandard-test-wiring.sh'
META_TRIGGER_FOUND=0
while IFS= read -r workflow; do
    workflow_commands="$WORK/wf-$(basename "$workflow").txt"
    extract_run_commands "$workflow" > "$workflow_commands"
    if commands_reference_path "$META_TEST_PATH" "$workflow_commands" &&
       grep -Eq "^[[:space:]]*-[[:space:]]*['\"]tests/\\*\\*['\"][[:space:]]*$" "$workflow"; then
        META_TRIGGER_FOUND=1
        break
    fi
done < <(find "$WORKFLOWS_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)

if [ "$META_TRIGGER_FOUND" -eq 1 ]; then
    pass "the repo-wide gate has a generic tests/** PR trigger"
else
    fail "the workflow invoking $META_TEST_PATH lacks a repo-wide tests/** PR trigger"
fi

# ── Validate the registry, collecting classified paths ─────────────────
if [ ! -f "$REGISTRY_FILE" ]; then
    fail "registry file is missing: tests/nonstandard-test-registry.txt"
else
    line_number=0
    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        line_number=$((line_number + 1))
        raw_line="${raw_line%$'\r'}"
        case "$raw_line" in
            ''|'#'*) continue ;;
        esac
        if [[ "$raw_line" != *$'\t'* ]]; then
            fail "registry line $line_number must be tab-separated"
            continue
        fi

        reg_path="${raw_line%%$'\t'*}"
        rest="${raw_line#*$'\t'}"
        disposition="${rest%%$'\t'*}"

        # Count the fields after the path so per-disposition arity is enforced.
        field_count=1
        tmp="$raw_line"
        while [ "$tmp" != "${tmp#*$'\t'}" ]; do
            field_count=$((field_count + 1))
            tmp="${tmp#*$'\t'}"
        done

        if [ -z "$reg_path" ] || [ -z "$disposition" ]; then
            fail "registry line $line_number has an empty path or disposition"
            continue
        fi
        case "$reg_path" in
            tests/scripts/test-*)
                fail "registry line $line_number is inside tests/scripts/test-* (owned by #823)"
                continue ;;
        esac
        if [ ! -f "$REPO_ROOT/$reg_path" ]; then
            fail "registry references a missing test: $reg_path"
            continue
        fi

        case "$disposition" in
            helper)
                if [ "$field_count" -ne 3 ]; then
                    fail "registry line $line_number (helper) needs exactly path, disposition, reason"
                    continue
                fi
                reason="${rest#*$'\t'}"
                [ -n "$reason" ] || { fail "registry line $line_number has an empty reason"; continue; }
                ;;
            manual|obsolete)
                if [ "$field_count" -ne 5 ]; then
                    fail "registry line $line_number ($disposition) needs path, disposition, reason, risk, removal-condition"
                    continue
                fi
                body="${rest#*$'\t'}"                 # reason<TAB>risk<TAB>removal
                reason="${body%%$'\t'*}"
                after="${body#*$'\t'}"                # risk<TAB>removal
                risk="${after%%$'\t'*}"
                removal="${after#*$'\t'}"
                if [ -z "$reason" ] || [ -z "$risk" ] || [ -z "$removal" ]; then
                    fail "registry line $line_number ($disposition) has an empty reason, risk, or removal-condition"
                    continue
                fi
                ;;
            *)
                fail "registry line $line_number has an unknown disposition: $disposition"
                continue ;;
        esac

        printf '%s\n' "$reg_path" >> "$REGISTRY_PATHS"
    done < "$REGISTRY_FILE"
fi

duplicates="$(LC_ALL=C sort "$REGISTRY_PATHS" | uniq -d)"
if [ -n "$duplicates" ]; then
    while IFS= read -r duplicate; do
        fail "duplicate registry entry: $duplicate"
    done <<< "$duplicates"
fi

# ── Account for every discovered nonstandard entrypoint ────────────────
echo "=== repo-wide nonstandard test wiring ==="
while IFS= read -r test_path; do
    [ -n "$test_path" ] || continue
    if is_workflow_wired "$test_path"; then
        WIRED=$((WIRED + 1))
        if grep -Fqx -- "$test_path" "$REGISTRY_PATHS"; then
            fail "stale registry entry for a wired test: $test_path"
        else
            pass "$test_path is invoked by CI"
        fi
    elif is_runner_covered "$test_path"; then
        COVERED=$((COVERED + 1))
        if grep -Fqx -- "$test_path" "$REGISTRY_PATHS"; then
            fail "stale registry entry for a runner-covered test: $test_path"
        else
            pass "$test_path is covered by a wired shared runner"
        fi
    elif grep -Fqx -- "$test_path" "$REGISTRY_PATHS"; then
        CLASSIFIED=$((CLASSIFIED + 1))
        pass "$test_path is explicitly classified in the registry"
    else
        fail "$test_path is neither executed nor explicitly classified"
    fi
done < <(git -C "$REPO_ROOT" ls-files tests/ \
    | grep -E '\.(sh|ps1)$' \
    | grep -vE '^tests/scripts/test-' \
    | LC_ALL=C sort)

echo ""
echo "Wired: $WIRED"
echo "Runner-covered: $COVERED"
echo "Classified: $CLASSIFIED"
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
