#!/bin/bash
# preflight: run-act.sh
# Replay GitHub Actions Linux jobs locally via nektos/act.
# Emits a single JSON line to stdout and exits non-zero on failure.
#
# Usage:
#   bash global/skills/_internal/preflight/scripts/run-act.sh [--workflow <file>] [--verbose]
#
# Env:
#   CLAUDE_PREFLIGHT_ACT_WORKFLOW  Path to workflow file (default: auto-detect)
#   CLAUDE_PREFLIGHT_VERBOSE       When non-empty, print act's raw output too.

set -uo pipefail

CHECK="act-linux"
VERBOSE="${CLAUDE_PREFLIGHT_VERBOSE:-}"
WORKFLOW="${CLAUDE_PREFLIGHT_ACT_WORKFLOW:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --workflow) WORKFLOW="${2:-}"; shift 2 ;;
        --verbose) VERBOSE=1; shift ;;
        *) shift ;;
    esac
done

# emit_json STATUS [key json-value ...]
emit_json() {
    printf '{"check":"%s","status":"%s"' "$CHECK" "$1"
    shift
    while [ $# -gt 1 ]; do
        printf ',"%s":%s' "$1" "$2"
        shift 2
    done
    printf '}\n'
}

now_ms() {
    local ns
    if ns=$(date +%s%N 2>/dev/null) && [ "${ns}" != "+%s%N" ] && [[ "$ns" =~ ^[0-9]+$ ]]; then
        echo "$((ns / 1000000))"
    else
        echo "$(($(date +%s) * 1000))"
    fi
}

# Skip cleanly when act is not installed — this is normal on hosts without Docker.
if ! command -v act >/dev/null 2>&1; then
    emit_json skip reason '"act not on PATH"'
    exit 0
fi

# act requires Docker. If docker is not reachable, skip rather than spin up a broken run.
if ! docker info >/dev/null 2>&1; then
    emit_json skip reason '"docker daemon not reachable"'
    exit 0
fi

# Auto-detect the first Linux workflow when none was specified.
if [ -z "$WORKFLOW" ]; then
    WORKFLOW=$(ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | head -1 || true)
fi

if [ -z "$WORKFLOW" ] || [ ! -f "$WORKFLOW" ]; then
    emit_json skip reason '"no workflow file detected under .github/workflows/"'
    exit 0
fi

# Evidence log path in caller-writable tmp.
LOG="${TMPDIR:-/tmp}/preflight-act-$$.log"
START=$(now_ms)

# --list is the cheapest dry-run: parse workflow, enumerate jobs, validate syntax.
# Full job runs require Docker images and are left to the developer; preflight aims
# to catch misconfiguration, not to reproduce hour-long CI runs.
if act -W "$WORKFLOW" --list >"$LOG" 2>&1; then
    END=$(now_ms)
    DUR=$((END - START))
    emit_json pass duration_ms "$DUR" workflow "\"$WORKFLOW\""
    [ -n "$VERBOSE" ] && sed 's/^/    act: /' "$LOG"
    rm -f "$LOG"
    exit 0
else
    END=$(now_ms)
    DUR=$((END - START))
    emit_json fail duration_ms "$DUR" evidence "\"$LOG\""
    [ -n "$VERBOSE" ] && sed 's/^/    act: /' "$LOG" >&2
    exit 1
fi
