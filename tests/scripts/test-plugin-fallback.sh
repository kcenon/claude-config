#!/bin/bash
# Regression test for issue #423: when the full-suite probe file is
# present, the plugin PreToolUse guards must stand down only for hooks
# the probe explicitly advertises as owned by the global surface. Any
# other state (unknown schema, malformed JSON, flag=false, missing key)
# must fall back to the original plugin guard behaviour.
#
# Run: bash tests/scripts/test-plugin-fallback.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
HOOKS_JSON="$ROOT_DIR/plugin/hooks/hooks.json"

if [ ! -f "$HOOKS_JSON" ]; then
    echo "FAIL: hooks.json not found at $HOOKS_JSON" >&2
    exit 1
fi

PYTHON=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "SKIP: python3/python not in PATH"
    exit 0
fi

PASS=0
FAIL=0
ERRORS=()

assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("$label: expected exit=$expected, got exit=$actual")
    fi
}

extract_command() {
    local idx="$1"
    "$PYTHON" - "$HOOKS_JSON" "$idx" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
idx = int(sys.argv[2])
print(data["hooks"]["PreToolUse"][idx]["hooks"][0]["command"])
PY
}

SENSITIVE_CMD="$(extract_command 0)"
BASH_CMD="$(extract_command 1)"

WORK="$(mktemp -d -t claude-plugin-fallback)"
trap 'rm -rf -- "$WORK" 2>/dev/null || true' EXIT
export HOME="$WORK"
mkdir -p "$HOME/.claude"
PROBE="$HOME/.claude/.full-suite-active"

# Dangerous strings assembled at runtime so this script does not itself
# trigger a caller's dangerous-command-guard.
RM_ROOT="$(printf 'rm %s%s %s' '-' 'rf' '/')"

write_probe() {
    printf '%s' "$1" > "$PROBE"
}

# --- Case 1: probe owns sensitive-file-guard only -----------------------
# Plugin's sensitive guard stands down; its Bash guard still fires because
# dangerous-command-guard is explicitly false.
write_probe '{"schema":1,"hooks":{"sensitive-file-guard":true,"dangerous-command-guard":false}}'

CLAUDE_FILE_PATH="/tmp/some-secret.env" bash -c "$SENSITIVE_CMD" >/dev/null 2>&1
assert_exit "probe owns sensitive: sensitive-guard stands down" "0" "$?"

CLAUDE_TOOL_INPUT="$RM_ROOT" bash -c "$BASH_CMD" >/dev/null 2>&1
assert_exit "probe owns sensitive: bash-guard still fires" "2" "$?"

# --- Case 2: probe owns dangerous-command-guard only --------------------
write_probe '{"schema":1,"hooks":{"sensitive-file-guard":false,"dangerous-command-guard":true}}'

CLAUDE_FILE_PATH="/tmp/some-secret.env" bash -c "$SENSITIVE_CMD" >/dev/null 2>&1
assert_exit "probe owns bash: sensitive-guard still fires" "2" "$?"

CLAUDE_TOOL_INPUT="$RM_ROOT" bash -c "$BASH_CMD" >/dev/null 2>&1
assert_exit "probe owns bash: bash-guard stands down" "0" "$?"

# --- Case 3: probe owns both -------------------------------------------
write_probe '{"schema":1,"hooks":{"sensitive-file-guard":true,"dangerous-command-guard":true}}'

CLAUDE_FILE_PATH="/tmp/some-secret.env" bash -c "$SENSITIVE_CMD" >/dev/null 2>&1
assert_exit "probe owns both: sensitive-guard stands down" "0" "$?"

CLAUDE_TOOL_INPUT="$RM_ROOT" bash -c "$BASH_CMD" >/dev/null 2>&1
assert_exit "probe owns both: bash-guard stands down" "0" "$?"

# --- Case 4: unknown schema → safe fallback (both active) ---------------
write_probe '{"schema":99,"hooks":{"sensitive-file-guard":true,"dangerous-command-guard":true}}'

CLAUDE_FILE_PATH="/tmp/some-secret.env" bash -c "$SENSITIVE_CMD" >/dev/null 2>&1
assert_exit "unknown schema: sensitive-guard fires (safe default)" "2" "$?"

CLAUDE_TOOL_INPUT="$RM_ROOT" bash -c "$BASH_CMD" >/dev/null 2>&1
assert_exit "unknown schema: bash-guard fires (safe default)" "2" "$?"

# --- Case 5: malformed JSON → safe fallback ----------------------------
write_probe 'not-valid-json'

CLAUDE_FILE_PATH="/tmp/some-secret.env" bash -c "$SENSITIVE_CMD" >/dev/null 2>&1
assert_exit "malformed probe: sensitive-guard fires (safe default)" "2" "$?"

CLAUDE_TOOL_INPUT="$RM_ROOT" bash -c "$BASH_CMD" >/dev/null 2>&1
assert_exit "malformed probe: bash-guard fires (safe default)" "2" "$?"

# --- Case 6: probe missing a hook key → that hook stays active ----------
write_probe '{"schema":1,"hooks":{"sensitive-file-guard":true}}'

CLAUDE_TOOL_INPUT="$RM_ROOT" bash -c "$BASH_CMD" >/dev/null 2>&1
assert_exit "missing dangerous-command-guard key: bash-guard fires" "2" "$?"

# --- Summary ------------------------------------------------------------

echo ""
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Errors:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    exit 1
fi

echo "PASS: probe-based fallback semantics correct across all cases"
