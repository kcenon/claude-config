#!/bin/bash
# Test suite: the minimal PreToolUse file-channel hook set (#964)
# Run: bash tests/hooks/test-file-channel-minimal.sh
#
# #964 removed the file-channel policy guards: pre-edit-read-guard (read before
# Edit/Write, now the native Edit/Write contract) and sensitive-file-guard (now
# permissions.deny). This suite feeds PreToolUse inputs for Edit, Write and Read
# through EVERY hook that global/settings.json still registers for that tool,
# read from the file rather than hard-coded, and merges their decisions the way
# Claude Code does (deny > ask > allow). It asserts that the edits the removed
# guards used to block are allowed, and that memory-write-guard still denies a
# secret written into the shared memory tree.
#
# A second section asserts with jq that permissions.deny carries every pattern
# sensitive-file-guard used to deny, in both settings files.
#
# Any hook registered on Edit, Write or Read later is exercised automatically,
# so a policy guard that comes back fails here.

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
REPO_ROOT="$(pwd)"
SETTINGS="$REPO_ROOT/global/settings.json"
WIN_SETTINGS="$REPO_ROOT/global/settings.windows.json"

PASS=0
FAIL=0
ERRORS=()

SCRATCH_ROOT="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "$SCRATCH_ROOT/file-channel-minimal.XXXXXX" 2>/dev/null) \
    || { WORK="$SCRATCH_ROOT/file-channel-minimal.$$"; mkdir -p "$WORK"; }
trap 'rm -rf "$WORK"' EXIT

# Hooks write logs and per-session state here, never into ~/.claude or the
# caller's TMPDIR. One session id for the whole run, as in a real session.
export CLAUDE_LOG_DIR="$WORK/logs"
export TMPDIR="$WORK/tmp"
mkdir -p "$CLAUDE_LOG_DIR" "$TMPDIR"
unset CLAUDE_SESSION_ID
SESSION="test-964-file-channel"

# Same memory fixture as tests/hooks/test-memory-write-guard.sh: a HOME with a
# memory-shared tree, the real validators linked in, and a test owner so
# secret-check.sh runs its detection paths (#618).
export HOME="$WORK/home"
MEM="$HOME/.claude/memory-shared/memories"
mkdir -p "$MEM" "$HOME/.claude/scripts/memory"
for v in validate.sh secret-check.sh injection-check.sh; do
    ln -sf "$REPO_ROOT/scripts/memory/$v" "$HOME/.claude/scripts/memory/$v"
done
export OWNER_EMAILS="test-owner@example.com"
export OWNER_GITHUB_HANDLE="test-owner"
export OWNER_HOME_USER="test-owner"

CLEAN_BODY="---
name: Clean memory
description: A clean test fixture.
type: feedback
---

This is a body. **Why:** because we need a clean test fixture incident reference. **How to apply:** use this exact pattern when validating new feedback memories.
"

SECRET_BODY="---
name: Bad memory
description: Has a leaked AWS key.
type: feedback
---

body body body body body. **Why:** test reason. **How to apply:** key is AKIAIOSFODNN7EXAMPLE oh no.
"

# An ordinary project the session works in.
PROJECT="$WORK/project"
mkdir -p "$PROJECT"
printf '# Project\n' >"$PROJECT/README.md"
printf 'old line\n' >"$PROJECT/notes.md"

# hooks_for <tool>
#   Prints the repository path of every PreToolUse hook whose matcher applies
#   to <tool> in global/settings.json. Matchers are tool-name alternations, so
#   a block applies when its whole matcher matches the tool name.
hooks_for() {
    local tool="$1" cmd script
    jq -r --arg t "$tool" '
        .hooks.PreToolUse[]
        | select((.matcher // "") as $m
                 | $m == "" or $m == "*" or ($t | test("^(" + $m + ")$")))
        | .hooks[].command' "$SETTINGS" |
        while IFS= read -r cmd; do
            [ -n "$cmd" ] || continue
            script="${cmd%% *}"
            printf '%s\n' "$REPO_ROOT/global/hooks/${script##*/}"
        done
}

echo "=== file-channel minimal hook set (#964) ==="
for tool in Edit Write Read; do
    echo "Registered PreToolUse $tool hooks:"
    hooks_for "$tool" | while IFS= read -r h; do echo "  - ${h##*/}"; done
done
echo ""

# run_all <payload>
#   Runs every hook registered for the payload's tool and prints the merged
#   decision followed by a tab and the names of the hooks that produced it.
#   A hook that prints nothing allows; exit code 2 is a blocking deny.
run_all() {
    local payload="$1" tool hook out rc decision
    local denies="" asks=""
    tool=$(printf '%s' "$payload" | jq -r '.tool_name')
    while IFS= read -r hook; do
        [ -n "$hook" ] || continue
        if [ ! -f "$hook" ]; then
            denies="$denies missing:${hook##*/}"
            continue
        fi
        rc=0
        out=$(cd "$PROJECT" && printf '%s' "$payload" | bash "$hook" 2>/dev/null) || rc=$?
        decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null | tail -n1)
        [ "$rc" -eq 2 ] && decision="deny"
        case "$decision" in
            deny) denies="$denies ${hook##*/}" ;;
            ask)  asks="$asks ${hook##*/}" ;;
        esac
    done < <(hooks_for "$tool")
    if [ -n "$denies" ]; then
        printf 'deny\t%s\n' "$denies"
    elif [ -n "$asks" ]; then
        printf 'ask\t%s\n' "$asks"
    else
        printf 'allow\t\n'
    fi
}

# expect <decision> <label> <payload> [hook-that-must-decide]
expect() {
    local expected="$1" label="$2" payload="$3" by="${4:-}"
    local result got who
    result=$(run_all "$payload")
    got="${result%%$'\t'*}"
    who="${result#*$'\t'}"
    if [ "$got" != "$expected" ]; then
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label - expected $expected, got $got (by:$who)")
        echo "  FAIL: $label (expected $expected, got $got by:$who)"
        return
    fi
    if [ -n "$by" ] && [[ " $who " != *" $by "* ]]; then
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $label - $expected came from:$who, not $by")
        echo "  FAIL: $label ($expected came from:$who, not $by)"
        return
    fi
    PASS=$((PASS + 1))
    echo "  PASS: $label -> $got"
}

read_payload() {
    jq -nc --arg s "$SESSION" --arg fp "$1" \
        '{session_id: $s, tool_name: "Read", tool_input: {file_path: $fp}}'
}

edit_payload() {
    jq -nc --arg s "$SESSION" --arg fp "$1" --arg old "$2" --arg new "$3" \
        '{session_id: $s, tool_name: "Edit", tool_input: {file_path: $fp, old_string: $old, new_string: $new, replace_all: false}}'
}

write_payload() {
    jq -nc --arg s "$SESSION" --arg fp "$1" --arg c "$2" \
        '{session_id: $s, tool_name: "Write", tool_input: {file_path: $fp, content: $c}}'
}

echo "[allow - read-before-edit is the native Edit/Write contract, not a hook]"
# The session reads one file first, as every real session does. A hook that
# tracks reads per session would now have a read set without notes.md in it.
expect allow "Read of README.md" "$(read_payload "$PROJECT/README.md")"
expect allow "Edit of a file never read in this session" \
    "$(edit_payload "$PROJECT/notes.md" 'old line' 'new line')"

# The session creates a file with Write, then overwrites it.
expect allow "Write that creates a new file" "$(write_payload "$PROJECT/draft.md" 'first')"
printf 'first' >"$PROJECT/draft.md"
expect allow "Write that overwrites a file created earlier in the session" \
    "$(write_payload "$PROJECT/draft.md" 'second')"

echo ""
echo "[deny - memory-write-guard still gates the shared memory tree]"
expect deny "Write of a memory file that contains a secret" \
    "$(write_payload "$MEM/feedback_secret.md" "$SECRET_BODY")" "memory-write-guard.sh"
printf '%s' "$CLEAN_BODY" >"$MEM/feedback_edit_target.md"
expect deny "Edit that injects a secret into a memory file" \
    "$(edit_payload "$MEM/feedback_edit_target.md" 'This is a body.' 'AKIAIOSFODNN7EXAMPLE leaked.')" "memory-write-guard.sh"
# Positive control: the deny above is a finding, not a broken guard.
expect allow "Write of a clean memory file" "$(write_payload "$MEM/feedback_clean.md" "$CLEAN_BODY")"

echo ""
echo "[permissions.deny covers every sensitive-file-guard pattern]"
# Read deny rules carry the patterns. Per the permissions reference, a Read deny
# rule also blocks the Edit and Write tools on the same path, including creating
# a file there (Claude Code v2.1.228+), and Claude Code never matches a
# Write(path) rule. Edit deny rules would also become sandbox write denies,
# which the removed guard never imposed, so only the four existing .env rules
# stay. See https://code.claude.com/docs/en/permissions.
# '**/' patterns are relative to the working directory, so the home-directory
# AWS credentials file needs its own '~/'-anchored rule (#973). ~/.ssh has none
# on purpose: sandboxed SSH commit signing reads the key file.
# shellcheck disable=SC2088  # '~' is rule text compared with jq, not a path
READ_PATTERNS=(
    '.env' '.env.*' '**/.env' '**/.env.*' '**/.envrc' '**/*.env' '**/*.env.*'
    '**/*.pem' '**/*.key' '**/*.p12' '**/*.pfx'
    '**/id_rsa' '**/id_rsa.*' '**/id_ed25519' '**/id_ed25519.*'
    '**/id_ecdsa' '**/id_ecdsa.*' '**/id_dsa' '**/id_dsa.*'
    '**/.aws/**/credentials' '**/.aws/**/config' '~/.aws/credentials'
    '**/secrets/**' '**/credentials/**' '**/*password*'
    '**/*secrets/**' '**/*credentials/**' '**/*passwords/**'
)
EDIT_PATTERNS=('.env' '.env.*' '**/.env' '**/.env.*')

# has_rule <settings-file> <rule>
has_rule() {
    jq -e --arg r "$2" '(.permissions.deny // []) | index($r) != null' "$1" >/dev/null 2>&1
}

for f in "$SETTINGS" "$WIN_SETTINGS"; do
    name="${f##*/}"
    missing=""
    for p in "${READ_PATTERNS[@]}"; do
        has_rule "$f" "Read($p)" || missing="$missing Read($p)"
    done
    for p in "${EDIT_PATTERNS[@]}"; do
        has_rule "$f" "Edit($p)" || missing="$missing Edit($p)"
    done
    if [ -z "$missing" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $name denies every sensitive-file pattern"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $name permissions.deny is missing:$missing")
        echo "  FAIL: $name permissions.deny is missing:$missing"
    fi
    if jq -e '[(.permissions.deny // [])[] | select(startswith("Write("))] | length == 0' "$f" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $name has no Write(path) deny rule (never matched)"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $name has a Write(path) deny rule, which Claude Code never matches; use Read(path)")
        echo "  FAIL: $name has a Write(path) deny rule"
    fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do
        echo "  $err"
    done
    exit 1
fi
exit 0
