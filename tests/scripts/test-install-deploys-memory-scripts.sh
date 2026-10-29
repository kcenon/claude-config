#!/bin/bash
# Regression test for issue #958.
#
# Runs the real scripts/install.sh (global profile, --yes) against a temporary
# HOME with CLAUDE_MEMORY_REPO_URL unset, and checks that the memory sync
# scripts and the memory validators land under ~/.claude/scripts/, are tracked
# in the install manifest, and survive a reinstall. The deployed
# memory-write-guard.sh must then deny a memory write that carries a secret
# instead of failing open with "validators not found". A project-only install
# must not deploy them.
#
# Run: bash tests/scripts/test-install-deploys-memory-scripts.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
    if eval "$2"; then
        pass "$label"
    else
        fail "$label"
    fi
}

sha256_of() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

# manifest_entry <home> <key>: the hash the install manifest records for key.
manifest_entry() {
    jq -r --arg k "$2" '.files[$k] // empty' "$1/.claude/.install-manifest.json" 2>/dev/null
}

make_fake_bin() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/claude" <<'SH'
#!/bin/sh
echo "claude test"
SH
    chmod +x "$dir/claude"
}

# Minimal installer tree, as in test-install-memory-sync-hooks.sh, plus the
# real memory scripts and the real memory-write-guard.sh hook.
make_fixture() {
    local fixture="$1"
    local lib

    mkdir -p \
        "$fixture/scripts/lib" \
        "$fixture/global/hooks/lib" \
        "$fixture/hooks/lib"

    cp "$REPO_ROOT/scripts/install.sh" "$fixture/scripts/install.sh"
    cp "$REPO_ROOT/scripts/install-manifest.sh" "$fixture/scripts/install-manifest.sh"
    cp "$REPO_ROOT/scripts/lib/install-prompts.sh" "$fixture/scripts/lib/install-prompts.sh"
    cp "$REPO_ROOT"/scripts/memory-sync.sh "$REPO_ROOT"/scripts/memory-status.sh \
        "$REPO_ROOT"/scripts/memory-notify.sh "$fixture/scripts/"
    cp -R "$REPO_ROOT/scripts/memory" "$fixture/scripts/memory"

    printf '%s\n' '{"fixture": "memory-scripts"}' > "$fixture/global/settings.json"
    cp "$REPO_ROOT/global/hooks/memory-write-guard.sh" "$fixture/global/hooks/"
    for lib in tokenize-shell.sh path-utils.sh timeout-wrapper.sh rotate.sh; do
        printf '%s\n' '#!/bin/sh' 'return 0 2>/dev/null || exit 0' > "$fixture/global/hooks/lib/$lib"
    done
    for lib in validate-commit-message.sh validate-language.sh validate-traceability.sh; do
        printf '%s\n' '#!/bin/sh' 'return 0 2>/dev/null || exit 0' > "$fixture/hooks/lib/$lib"
    done
}

# run_install <home> <type> <output> [VAR=value...]
run_install() {
    local home_dir="$1" type="$2" out="$3"
    shift 3
    env -u CLAUDE_MEMORY_REPO_URL \
        HOME="$home_dir" \
        USERPROFILE="$home_dir" \
        PATH="$FAKE_BIN:$PATH" \
        AGENT_LANGUAGE=english \
        CONTENT_LANGUAGE=english \
        INSTALL_NPM=n \
        LAUNCHD_TARGET_DIR="$home_dir/launchd-staging" \
        SYSTEMD_USER_DIR="$home_dir/systemd-staging" \
        "$@" \
        bash "$FIXTURE/scripts/install.sh" --type "$type" --yes >"$out" 2>&1 </dev/null
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/install-memscripts.XXXXXX" 2>/dev/null || mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_BIN="$WORK/fake-bin"
make_fake_bin "$FAKE_BIN"
FIXTURE="$WORK/fixture"
make_fixture "$FIXTURE"

# Deployed-path keys, relative to ~/.claude: the three top-level scripts and
# every scripts/memory/*.sh (secret-check.env.example is not a script).
KEYS=()
for name in memory-sync.sh memory-status.sh memory-notify.sh; do
    KEYS+=("scripts/$name")
done
for src in "$REPO_ROOT"/scripts/memory/*.sh; do
    KEYS+=("scripts/memory/$(basename "$src")")
done

echo "=== memory script deployment test (bash, #958) ==="
echo ""

echo "[Global install, CLAUDE_MEMORY_REPO_URL unset]"
home_g="$WORK/home-global"
mkdir -p "$home_g"
out1="$WORK/install-1.out"
if run_install "$home_g" 1 "$out1"; then
    pass "install exits 0"
else
    fail "install exits 0"
    sed 's/^/    /' "$out1"
fi
assert_true "memory sync setup skipped (URL unset)" \
    "grep -q 'CLAUDE_MEMORY_REPO_URL not set' '$out1'"
assert_true "${#KEYS[@]} memory scripts expected (3 + scripts/memory/*.sh)" \
    "[ ${#KEYS[@]} -ge 10 ]"
for key in "${KEYS[@]}"; do
    assert_true "$key deployed executable" "[ -x '$home_g/.claude/$key' ]"
    assert_true "$key matches its source" \
        "cmp -s '$FIXTURE/$key' '$home_g/.claude/$key'"
    assert_true "$key tracked in the install manifest" \
        "[ \"\$(manifest_entry '$home_g' '$key')\" = \"\$(sha256_of '$FIXTURE/$key')\" ]"
done
assert_true "secret-check.env.example not deployed" \
    "[ ! -e '$home_g/.claude/scripts/memory/secret-check.env.example' ]"

echo ""
echo "[Deployed CLIs answer --help without a memory clone]"
for name in memory-sync.sh memory-status.sh memory-notify.sh; do
    assert_true "$name --help exits 0" \
        "HOME='$home_g' '$home_g/.claude/scripts/$name' --help >/dev/null 2>&1"
done
assert_true "no memory-shared clone was needed or created" \
    "[ ! -e '$home_g/.claude/memory-shared' ]"

echo ""
echo "[Deployed memory-write-guard.sh finds the deployed validators]"
memory_file="$home_g/.claude/memory-shared/memories/leak-test.md"
fake_token="ghp_$(printf '%036d' 0)"
content="---
name: Leak test
description: Carries a token-shaped string.
type: feedback
---

Body text. **Why:** regression fixture for #958. **How to apply:** token ${fake_token} must be blocked.
"
payload="$(jq -nc --arg fp "$memory_file" --arg c "$content" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')"
guard_out="$(printf '%s' "$payload" | env HOME="$home_g" \
    OWNER_EMAILS=test-owner@example.com \
    OWNER_GITHUB_HANDLE=test-owner \
    OWNER_HOME_USER=test-owner \
    bash "$home_g/.claude/hooks/memory-write-guard.sh" 2>/dev/null)"
decision="$(printf '%s' "$guard_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
reason="$(printf '%s' "$guard_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
if [ "$decision" = "deny" ]; then
    pass "guard denies a secret-bearing memory write"
else
    fail "guard denies a secret-bearing memory write (got '${decision}': $guard_out)"
fi
if printf '%s' "$reason" | grep -q 'secret-check.sh blocked write'; then
    pass "deny comes from secret-check.sh"
else
    fail "deny comes from secret-check.sh"
fi
if printf '%s' "$guard_out" | grep -q 'validators not found'; then
    fail "guard did not report missing validators"
else
    pass "guard did not report missing validators"
fi

echo ""
echo "[Reinstall is idempotent]"
snapshot() {
    local key
    for key in "${KEYS[@]}"; do
        printf '%s %s\n' "$key" "$(manifest_entry "$home_g" "$key")"
    done
}
before="$(snapshot)"
out2="$WORK/install-2.out"
if run_install "$home_g" 1 "$out2"; then
    pass "second install exits 0"
else
    fail "second install exits 0"
    sed 's/^/    /' "$out2"
fi
if [ "$(snapshot)" = "$before" ]; then
    pass "manifest entries unchanged"
else
    fail "manifest entries unchanged"
fi
assert_true "no local-change prompt" "! grep -q 'Local changes detected' '$out2'"
assert_true "memory scripts not pruned" "! grep -q 'Pruned removed managed file: scripts/' '$out2'"
for key in "${KEYS[@]}"; do
    assert_true "$key still deployed and current" \
        "[ -x '$home_g/.claude/$key' ] && cmp -s '$FIXTURE/$key' '$home_g/.claude/$key'"
done

echo ""
echo "[A locally edited validator is kept, not overwritten]"
edited="$home_g/.claude/scripts/memory/validate.sh"
printf '%s\n' '# local edit (#958 test)' >> "$edited"
edited_sha="$(sha256_of "$edited")"
out3="$WORK/install-3.out"
if run_install "$home_g" 1 "$out3"; then
    pass "third install exits 0"
else
    fail "third install exits 0"
    sed 's/^/    /' "$out3"
fi
assert_true "divergence reported for the edited validator" \
    "grep -qF 'Local changes detected in: $edited' '$out3'"
assert_true "edited validator kept byte-for-byte" \
    "[ \"\$(sha256_of '$edited')\" = '$edited_sha' ]"
assert_true "edited validator still tracked (not pruned)" \
    "[ \"\$(manifest_entry '$home_g' scripts/memory/validate.sh)\" = \"\$(sha256_of '$FIXTURE/scripts/memory/validate.sh')\" ]"

echo ""
echo "[Project-only install (type 2) leaves HOME/.claude/scripts alone]"
home_p="$WORK/home-project"
project="$WORK/project"
mkdir -p "$home_p" "$project"
out4="$WORK/install-project.out"
if run_install "$home_p" 2 "$out4" PROJECT_DIR="$project" CREATE_LOCAL=n; then
    pass "project install exits 0"
else
    fail "project install exits 0"
    sed 's/^/    /' "$out4"
fi
assert_true "HOME/.claude/scripts/memory not created" "[ ! -e '$home_p/.claude/scripts/memory' ]"
assert_true "HOME/.claude/scripts/memory-sync.sh not created" "[ ! -e '$home_p/.claude/scripts/memory-sync.sh' ]"

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
