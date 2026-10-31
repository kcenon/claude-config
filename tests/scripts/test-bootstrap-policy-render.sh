#!/bin/bash
# test-bootstrap-policy-render.sh
# Regression test for issue #984.
#
# bootstrap.sh deployed the raw global/commit-settings.md for every content
# language policy, so an install under any other policy told Claude the English
# rule. It must deploy global/commit-settings.md.tmpl rendered for the resolved
# policy, as scripts/install.sh does.
#
# The policy is resolved only after the copy loop in install_global, from the
# environment, from settings.json on a reinstall, or from a prompt. The reinstall
# case below is the one that fails if the render ever moves in front of that.
#
# Runs install_global from the real tree into a temporary HOME through
# CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE=global-install: no clone and no CLI check.
#
# Run: bash tests/scripts/test-bootstrap-policy-render.sh
# Needs a writable default temp directory: bootstrap.sh calls bare mktemp, which
# the macOS Bash sandbox denies.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
TMPL="$REPO_ROOT/global/commit-settings.md.tmpl"
RAW="$REPO_ROOT/global/commit-settings.md"

PASS=0
FAIL=0
ERRORS=()

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    ERRORS+=("$1")
    echo "  FAIL: $1"
}

assert_true() {
    local label="$1"
    shift
    if "$@"; then
        pass "$label"
    else
        fail "$label"
    fi
}

assert_false() {
    local label="$1"
    shift
    if "$@"; then
        fail "$label"
    else
        pass "$label"
    fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-policy.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/bootstrap.out"

# run_bootstrap <home> [VAR=value...]: the caller supplies stdin. The language
# variables are unset unless passed, so a reinstall resolves its own policy.
run_bootstrap() {
    local home_dir="$1"
    shift
    env -u AGENT_LANGUAGE -u CONTENT_LANGUAGE -u BOOTSTRAP_FORCE -u MANIFEST_PATH \
        HOME="$home_dir" USERPROFILE="$home_dir" INSTALL_DIR="$REPO_ROOT" \
        FORCE_MODE=1 INSTALL_NPM=n CLAUDE_CONFIG_BOOTSTRAP_TEST_MODE=global-install \
        "$@" bash "$BOOTSTRAP" >"$OUT" 2>&1
}

# rendered <policy> <dest>: what the shared renderer makes of the template.
rendered() {
    (
        # shellcheck disable=SC1091
        . "$REPO_ROOT/scripts/lib/install-prompts.sh"
        CONTENT_LANGUAGE="$1" render_policy_tmpl "$TMPL" "$2"
    )
}

same_bytes() {
    cmp -s "$1" "$2"
}

has_line() {
    grep -qF -- "$2" "$1"
}

is_mode_644() {
    [ -n "$(find "$1" -perm 644 2>/dev/null)" ]
}

prompt_count() {
    grep -c 'Local changes detected' "$OUT" || true
}

# verify_ok <home>: scripts/verify.sh reports no failure against that HOME. It
# runs from a directory with no install manifest, or it would also compare a
# project.
verify_ok() {
    (cd "$WORK" && HOME="$1" bash "$REPO_ROOT/scripts/verify.sh" >"$WORK/verify.out" 2>&1 </dev/null)
}

BILINGUAL="$WORK/expected-bilingual.md"
rendered exclusive_bilingual "$BILINGUAL"

echo "=== Bootstrap commit-settings render test (bash, #984) ==="
echo ""

# The rendered text must differ from the raw file, or the checks below prove
# nothing.
assert_false "the bilingual render differs from the raw file" same_bytes "$BILINGUAL" "$RAW"

echo ""
echo "[Fresh install, exclusive_bilingual]"
HOME_A="$WORK/home-a"
INSTALLED_A="$HOME_A/.claude/commit-settings.md"
mkdir -p "$HOME_A"
if run_bootstrap "$HOME_A" AGENT_LANGUAGE=korean CONTENT_LANGUAGE=exclusive_bilingual </dev/null; then
    pass "install exits 0"
else
    fail "install exits 0"
    tail -n 20 "$OUT" | sed 's/^/    /'
fi
assert_true "commit-settings.md is the render for the policy" same_bytes "$INSTALLED_A" "$BILINGUAL"
assert_true "it states the chosen policy" has_line "$INSTALLED_A" "English or Korean (document-exclusive) by default"
assert_false "the tmpl-contract line does not leak" has_line "$INSTALLED_A" "tmpl-contract"
assert_true "it is world-readable, not the 0600 of a mktemp file" is_mode_644 "$INSTALLED_A"
assert_true "the manifest tracks it" has_line "$HOME_A/.claude/.install-manifest.json" '"commit-settings.md"'
if verify_ok "$HOME_A"; then
    pass "verify.sh reports 0 failures"
else
    fail "verify.sh reports 0 failures"
    grep -E 'DIFF|MISS|FAIL|실패' "$WORK/verify.out" | sed 's/^/    /'
fi

echo ""
echo "[Reinstall with the language variables unset]"
if run_bootstrap "$HOME_A" </dev/null; then
    pass "reinstall exits 0"
else
    fail "reinstall exits 0"
    tail -n 20 "$OUT" | sed 's/^/    /'
fi
assert_true "the policy from settings.json still renders" same_bytes "$INSTALLED_A" "$BILINGUAL"
assert_false "no language prompt" has_line "$OUT" "Select Language Profile Preset"
assert_true "no local-change prompt" [ "$(prompt_count)" = "0" ]

echo ""
echo "[Upgrade from a raw copy an older bootstrap left]"
cp "$RAW" "$INSTALLED_A"
(
    export MANIFEST_PATH="$HOME_A/.claude/.install-manifest.json"
    # shellcheck disable=SC1091
    . "$REPO_ROOT/scripts/install-manifest.sh"
    _manifest_write "commit-settings.md" "$(_manifest_hash "$RAW")"
)
if run_bootstrap "$HOME_A" </dev/null; then
    pass "upgrade exits 0"
else
    fail "upgrade exits 0"
    tail -n 20 "$OUT" | sed 's/^/    /'
fi
assert_true "the raw copy is replaced by the render" same_bytes "$INSTALLED_A" "$BILINGUAL"
assert_true "with no prompt, because it was not edited" [ "$(prompt_count)" = "0" ]

echo ""
echo "[Local edit, answering keep]"
printf 'local note\n' >>"$INSTALLED_A"
cp "$INSTALLED_A" "$WORK/edited.md"
run_bootstrap "$HOME_A" <<<"k"
assert_true "exactly one prompt" [ "$(prompt_count)" = "1" ]
assert_true "the prompt names commit-settings.md" has_line "$OUT" "Local changes detected in: $INSTALLED_A"
assert_true "the edit stays" same_bytes "$INSTALLED_A" "$WORK/edited.md"

echo ""
echo "[Default policy]"
HOME_B="$WORK/home-b"
mkdir -p "$HOME_B"
run_bootstrap "$HOME_B" AGENT_LANGUAGE=korean CONTENT_LANGUAGE=english </dev/null
assert_true "english equals the committed commit-settings.md" same_bytes "$HOME_B/.claude/commit-settings.md" "$RAW"

echo ""
echo "[The other installer produces the same bytes]"
HOME_C="$WORK/home-c"
mkdir -p "$HOME_C"
env -u BOOTSTRAP_FORCE -u MANIFEST_PATH HOME="$HOME_C" USERPROFILE="$HOME_C" \
    AGENT_LANGUAGE=korean CONTENT_LANGUAGE=exclusive_bilingual INSTALL_NPM=n \
    bash "$REPO_ROOT/scripts/install.sh" --type 1 --yes >"$WORK/install.out" 2>&1 </dev/null
if has_line "$WORK/install.out" "english로 재설정"; then
    # An enterprise CLAUDE.md on this machine forces english under --yes.
    echo "  SKIP: an enterprise policy on this machine overrides the language"
else
    assert_true "scripts/install.sh deploys the same file" same_bytes "$HOME_C/.claude/commit-settings.md" "$BILINGUAL"
fi

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Errors:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi

exit 0
