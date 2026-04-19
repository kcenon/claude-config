#!/bin/bash
# preflight: run-all.sh
# Orchestrates every check script under scripts/, printing a JSON line per check
# and a final summary on stderr. Exit code is non-zero iff any check reports fail.
#
# Usage:
#   bash global/skills/preflight/scripts/run-all.sh [--only <check>] [--skip <check>] [--verbose]
#
# Invoked by hooks/pre-push when CLAUDE_PREFLIGHT=1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ONLY=""
SKIP=""
VERBOSE_FLAG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="$2"; shift 2 ;;
        --skip) SKIP="$2"; shift 2 ;;
        --verbose) VERBOSE_FLAG="--verbose"; export CLAUDE_PREFLIGHT_VERBOSE=1; shift ;;
        *) shift ;;
    esac
done

# Canonical order — cheap checks first so failures surface fast.
CHECKS=(
    "deprecated-api:run-deprecated-api.sh"
    "cmake-configure:run-cmake-configure.sh"
    "act-linux:run-act.sh"
    "msvc-docker:run-msvc-docker.sh"
)

any_fail=0
ran=0
skipped=0
passed=0
failed=0

for entry in "${CHECKS[@]}"; do
    id="${entry%%:*}"
    script="${entry##*:}"

    # Filter by --only / --skip.
    if [ -n "$ONLY" ] && [ "$id" != "$ONLY" ]; then
        continue
    fi
    if [ -n "$SKIP" ] && [ "$id" = "$SKIP" ]; then
        continue
    fi

    ran=$((ran + 1))
    # Run the check and capture stdout (one JSON line).
    out=$(bash "$SCRIPT_DIR/$script" $VERBOSE_FLAG 2>&1)
    rc=$?
    # Pass through the JSON line verbatim.
    # Some scripts emit the JSON before build output on stderr; split cleanly.
    json_line=$(echo "$out" | grep -E '^\{"check":' | head -1)
    rest=$(echo "$out" | grep -vE '^\{"check":' || true)

    if [ -n "$json_line" ]; then
        echo "$json_line"
    else
        # Malformed check script — record it as a failure against the id.
        printf '{"check":"%s","status":"fail","reason":"no JSON report emitted"}\n' "$id"
        rc=1
    fi

    if [ -n "$rest" ]; then
        echo "$rest" >&2
    fi

    case "$rc" in
        0)
            case "$json_line" in
                *'"status":"skip"'*) skipped=$((skipped + 1)) ;;
                *) passed=$((passed + 1)) ;;
            esac
            ;;
        *)
            failed=$((failed + 1))
            any_fail=1
            ;;
    esac
done

echo "preflight summary: ran=$ran passed=$passed failed=$failed skipped=$skipped" >&2

exit "$any_fail"
