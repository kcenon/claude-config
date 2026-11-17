#!/bin/bash
# Test suite: the minimal PreToolUse Bash hook set (#964)
# Run: bash tests/hooks/test-bash-channel-minimal.sh
#
# #964 removed the Bash-channel policy guards (commit format, PR language,
# attribution, cross-repo gh writes, uninspectable writes, merge method, ...).
# This suite feeds PreToolUse Bash inputs through EVERY hook that
# global/settings.json still registers on the Bash matcher, read from the file
# rather than hard-coded, and merges their decisions the way Claude Code does
# (deny > ask > allow). It asserts that the commands those policy guards used
# to block are allowed, and that the destructive-operation guards still deny
# or ask.
#
# Any hook registered on Bash later is exercised automatically, so a policy
# guard that comes back fails here.

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
REPO_ROOT="$(pwd)"
SETTINGS="$REPO_ROOT/global/settings.json"

PASS=0
FAIL=0
ERRORS=()

SCRATCH_ROOT="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "$SCRATCH_ROOT/bash-channel-minimal.XXXXXX" 2>/dev/null) \
    || { WORK="$SCRATCH_ROOT/bash-channel-minimal.$$"; mkdir -p "$WORK"; }
trap 'rm -rf "$WORK"' EXIT

# Hooks write their decision logs here, never into ~/.claude/logs.
export CLAUDE_LOG_DIR="$WORK/logs"
mkdir -p "$CLAUDE_LOG_DIR"

# Pin the default content-language policy so "non-default language" means the
# same thing on every machine, whatever the caller's environment sets.
export CLAUDE_CONTENT_LANGUAGE=english

# Stub gh so no hook reaches GitHub. `gh pr checks` reports green checks, the
# shape merge-gate-guard reads (failing ones when STUB_CHECKS=fail); every
# other call succeeds with no output.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'STUB_EOF'
#!/bin/bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "checks" ]; then
    if [ "${STUB_CHECKS:-}" = "fail" ]; then
        echo '[{"bucket":"fail","name":"build","state":"FAILURE"}]'
    else
        echo '[{"bucket":"pass","name":"build","state":"COMPLETED"},{"bucket":"skipping","name":"docs","state":"SKIPPED"}]'
    fi
fi
exit 0
STUB_EOF
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# Run every hook from a throwaway repository on a feature branch with a clean
# work tree, so the guards' git checks see a predictable state. Its origin
# names a different repository than the --repo target below, which makes that
# gh call a cross-repo write.
REPO="$WORK/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" checkout -q -b feat/x
git -C "$REPO" remote add origin https://github.com/test-owner/this-repo.git
git -C "$REPO" -c user.name=test-owner -c user.email=test-owner@example.com \
    -c commit.gpgsign=false commit -q --allow-empty -m "chore: init"

# --- Registered Bash hooks, read from global/settings.json ---
HOOKS=()
while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    script="${cmd%% *}"
    base="${script##*/}"
    HOOKS+=("$REPO_ROOT/global/hooks/$base")
done < <(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$SETTINGS")

if [ "${#HOOKS[@]}" -eq 0 ]; then
    echo "FATAL: no PreToolUse Bash hooks found in $SETTINGS" >&2
    exit 1
fi

echo "=== bash-channel minimal hook set (#964) ==="
echo "Registered PreToolUse Bash hooks: ${#HOOKS[@]}"
for h in "${HOOKS[@]}"; do echo "  - ${h##*/}"; done
echo ""

# run_all <command>
#   Runs every registered hook on one Bash payload and prints the merged
#   decision followed by a tab and the names of the hooks that produced it.
#   A hook that prints nothing allows; exit code 2 is a blocking deny.
run_all() {
    local command="$1" payload hook out rc decision
    local denies="" asks=""
    payload=$(jq -nc --arg c "$command" '{tool_name: "Bash", tool_input: {command: $c}}')
    for hook in "${HOOKS[@]}"; do
        rc=0
        out=$(cd "$REPO" && printf '%s' "$payload" | bash "$hook" 2>/dev/null) || rc=$?
        decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null | tail -n1)
        [ "$rc" -eq 2 ] && decision="deny"
        case "$decision" in
            deny) denies="$denies ${hook##*/}" ;;
            ask)  asks="$asks ${hook##*/}" ;;
        esac
    done
    if [ -n "$denies" ]; then
        printf 'deny\t%s\n' "$denies"
    elif [ -n "$asks" ]; then
        printf 'ask\t%s\n' "$asks"
    else
        printf 'allow\t\n'
    fi
}

# expect <decision> <label> <command> [hook-that-must-decide]
expect() {
    local expected="$1" label="$2" command="$3" by="${4:-}"
    local result got who
    result=$(run_all "$command")
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

HEREDOC_CMD=$(printf '%s\n' "cat <<'EOF' > notes.md" "Run source ./setup.sh before the build." "EOF")

echo "[allow - policy rules that are no longer hooks]"
expect allow "python3 -c inline script" "python3 -c 'print(1)'"
expect allow "awk with a redirect" "awk '{print}' a > b"
expect allow "awk program that redirects its output" "awk '{print > \"b\"}' a"
expect allow "heredoc whose body contains the word source" "$HEREDOC_CMD"
expect allow "gh write with --repo for another repository" "gh issue edit 1 --repo other/repo --body x"
expect allow "non-Conventional commit message" 'git commit -m "not conventional"'
expect allow "PR body in a non-default language" 'gh pr create --title "x" --body "한국어 본문입니다"'
expect allow "gh pr merge --merge with green checks" "gh pr merge 5 --merge"

echo ""
echo "[deny / ask - destructive operations stay guarded]"
expect deny "direct push to main" "git push origin main" "dangerous-command-guard.sh"
expect ask "force push to a feature branch" "git push --force origin feat/x" "dangerous-command-guard.sh"

echo ""
echo "[deny - the narrowed merge gate still checks CI]"
# Proves the allow above came from green checks, not from a fail-open path.
export STUB_CHECKS=fail
expect deny "gh pr merge --merge with a failing check" "gh pr merge 5 --merge" "merge-gate-guard.sh"
unset STUB_CHECKS

echo ""
echo "[settings - the if rule on each handler (#996)]"
# A wrong rule stops a hook without any error, and the calls above never reach
# the harness that evaluates it, so the exact rules are pinned here.
expect_if() {
    local event="$1" script="$2" expected="$3" got
    got=$(jq -r --arg e "$event" --arg s "$script" \
        '.hooks[$e][].hooks[] | select(.command | endswith($s)) | .if // "none"' "$SETTINGS")
    if [ "$got" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $script -> $got"
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("FAIL: $script - expected if $expected, got $got")
        echo "  FAIL: $script (expected if $expected, got $got)"
    fi
}
expect_if PreToolUse dangerous-command-guard.sh "none"
expect_if PreToolUse merge-gate-guard.sh "Bash(*gh pr merge*)"
expect_if PreToolUse memory-write-guard.sh "none"
expect_if PostToolUse memory-access-logger.sh "Read(~/.claude/**/memor*/**)"

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
