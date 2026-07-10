#!/bin/bash
# Fail when a tests/scripts/test-* file is neither invoked by CI nor recorded
# as a reviewed manual-only exception.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
EXCEPTIONS_FILE="$SCRIPT_DIR/ci-wiring-exceptions.txt"

PASS=0
FAIL=0
WIRED=0
MANUAL=0
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t ci-wiring)"
trap 'rm -rf -- "$WORK"' EXIT

RUN_COMMANDS="$WORK/run-commands.txt"
EXCEPTION_PATHS="$WORK/exception-paths.txt"
: > "$RUN_COMMANDS"
: > "$EXCEPTION_PATHS"

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
}

# Extract only commands from YAML run keys. Paths in trigger filters, comments,
# or step descriptions must not count as executable CI wiring.
extract_run_commands() {
    awk '
        function indentation(value) {
            match(value, /^[[:space:]]*/)
            return RLENGTH
        }
        {
            line = $0
            sub(/\r$/, "", line)

            if (in_block) {
                if (line ~ /^[[:space:]]*$/) {
                    next
                }
                if (indentation(line) > block_indent) {
                    sub(/^[[:space:]]+/, "", line)
                    print line
                    next
                }
                in_block = 0
            }

            trimmed = line
            sub(/^[[:space:]]+/, "", trimmed)
            if (trimmed !~ /^run:[[:space:]]*/) {
                next
            }

            block_indent = indentation(line)
            sub(/^run:[[:space:]]*/, "", trimmed)
            if (trimmed ~ /^[|>][-+]?$/) {
                in_block = 1
                next
            }
            print trimmed
        }
    ' "$1"
}

if [ ! -d "$WORKFLOWS_DIR" ]; then
    fail "workflow directory is missing: .github/workflows"
else
    while IFS= read -r workflow; do
        extract_run_commands "$workflow" >> "$RUN_COMMANDS"
    done < <(find "$WORKFLOWS_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
fi

# Return success only when the path is an argument to an executable test
# command. Merely echoing or mentioning the path does not satisfy the gate.
commands_reference_path() {
    local test_path="$1"
    local commands_file="$2"
    awk -v path="$test_path" '
        {
            line = $0
            position = index(line, path)
            if (position == 0) {
                next
            }

            prefix = substr(line, 1, position - 1)
            suffix = substr(line, position + length(path))
            if (suffix !~ /^([[:space:]\\;&|]|$)/) {
                next
            }

            if (prefix ~ /(^|[;&|][[:space:]]*)(bash|pwsh|powershell)([[:space:]][^#]*)?$/ ||
                prefix ~ /(^|[;&|][[:space:]]*)\.?\/?$/) {
                found = 1
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$commands_file"
}

is_workflow_wired() {
    commands_reference_path "$1" "$RUN_COMMANDS"
}

# The gate must be triggered by additions under test-*; wiring the checker
# without its generic pull_request path item would leave a silent bypass.
META_TEST_PATH='tests/scripts/test-ci-wiring.sh'
META_TRIGGER_FOUND=0
while IFS= read -r workflow; do
    workflow_commands="$WORK/workflow-commands-$(basename "$workflow").txt"
    extract_run_commands "$workflow" > "$workflow_commands"
    if commands_reference_path "$META_TEST_PATH" "$workflow_commands" &&
       grep -Eq "^[[:space:]]*-[[:space:]]*['\"]tests/scripts/test-\\*['\"][[:space:]]*$" "$workflow"; then
        META_TRIGGER_FOUND=1
        break
    fi
done < <(find "$WORKFLOWS_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)

if [ "$META_TRIGGER_FOUND" -eq 1 ]; then
    pass "the CI wiring gate has a generic tests/scripts/test-* PR trigger"
else
    fail "the workflow invoking $META_TEST_PATH lacks an exact tests/scripts/test-* PR trigger"
fi

if [ ! -f "$EXCEPTIONS_FILE" ]; then
    fail "manual-only exception file is missing"
else
    line_number=0
    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        line_number=$((line_number + 1))
        raw_line="${raw_line%$'\r'}"
        case "$raw_line" in
            ''|'#'*) continue ;;
        esac

        if [[ "$raw_line" != *$'\t'* ]]; then
            fail "exception line $line_number must contain a tab-separated reason"
            continue
        fi

        test_path="${raw_line%%$'\t'*}"
        reason="${raw_line#*$'\t'}"
        if [ -z "$test_path" ] || [ -z "$reason" ]; then
            fail "exception line $line_number has an empty path or reason"
            continue
        fi
        case "$test_path" in
            tests/scripts/test-*) ;;
            *)
                fail "exception line $line_number is outside tests/scripts/test-*"
                continue
                ;;
        esac
        if [ ! -f "$REPO_ROOT/$test_path" ]; then
            fail "exception references a missing test: $test_path"
        fi
        printf '%s\n' "$test_path" >> "$EXCEPTION_PATHS"
    done < "$EXCEPTIONS_FILE"
fi

duplicates="$(LC_ALL=C sort "$EXCEPTION_PATHS" | uniq -d)"
if [ -n "$duplicates" ]; then
    while IFS= read -r duplicate; do
        fail "duplicate manual-only exception: $duplicate"
    done <<< "$duplicates"
fi

echo "=== tests/scripts CI wiring ==="
while IFS= read -r test_file; do
    test_path="${test_file#"$REPO_ROOT/"}"
    if is_workflow_wired "$test_path"; then
        WIRED=$((WIRED + 1))
        if grep -Fqx -- "$test_path" "$EXCEPTION_PATHS"; then
            fail "stale manual-only exception for wired test: $test_path"
        else
            pass "$test_path is invoked by CI"
        fi
    elif grep -Fqx -- "$test_path" "$EXCEPTION_PATHS"; then
        MANUAL=$((MANUAL + 1))
        pass "$test_path is a reviewed manual-only exception"
    else
        fail "$test_path is not invoked by CI or explicitly excepted"
    fi
done < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -name 'test-*' | LC_ALL=C sort)

echo ""
echo "Wired: $WIRED"
echo "Manual-only: $MANUAL"
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
