#!/bin/bash
# Regression test for scripts/install-manifest.sh (issue #420).
# Verifies that guarded_copy preserves local customizations when the user
# chooses [k]eep, and honors BOOTSTRAP_FORCE=1 to overwrite.
#
# Run: bash tests/scripts/test-install-preserves-customization.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
ROOT_DIR="$PWD"
HELPER="$ROOT_DIR/scripts/install-manifest.sh"

if [ ! -f "$HELPER" ]; then
    echo "FAIL: helper not found: $HELPER" >&2
    exit 1
fi

PASS=0
FAIL=0
ERRORS=()

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Each case runs in its own manifest path and temp files.
new_case() {
    local name="$1"
    CASE_DIR="$WORK/$name"
    mkdir -p "$CASE_DIR"
    export MANIFEST_PATH="$CASE_DIR/manifest.json"
    unset BOOTSTRAP_FORCE
}

# shellcheck disable=SC1090
source "$HELPER"

if ! manifest_available; then
    echo "SKIP: no python3/python on PATH; guarded_copy requires JSON tool"
    exit 0
fi

assert_equal() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("$label: expected '$expected', got '$actual'")
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("$label: '$needle' not found in output")
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        FAIL=$((FAIL + 1))
        ERRORS+=("$label: unexpected '$needle' found in output")
    else
        PASS=$((PASS + 1))
    fi
}

assert_missing() {
    local label="$1" path="$2"
    if [ ! -e "$path" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("$label: expected missing path: $path")
    fi
}

# --- Case 1: first install records the hash -------------------------------
new_case "first-install"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1 content\n' > "$src"
guarded_copy "$src" "$dest" "source.md"
assert_equal "first-install: dest exists" "v1 content" "$(cat "$dest")"
assert_contains "first-install: manifest has hash" "source.md" "$(cat "$MANIFEST_PATH")"

# --- Case 2: re-install with no local edit upgrades silently --------------
new_case "clean-upgrade"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1\n' > "$src"
guarded_copy "$src" "$dest" "source.md"   # first install
printf 'v2\n' > "$src"                      # new upstream version
guarded_copy "$src" "$dest" "source.md"   # should upgrade silently
assert_equal "clean-upgrade: dest reflects v2" "v2" "$(cat "$dest")"

# --- Case 3: local edit preserved on [k] (default) ------------------------
new_case "keep-local"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1\n' > "$src"
guarded_copy "$src" "$dest" "source.md"
printf 'locally edited\n' > "$dest"
printf 'v2\n' > "$src"
# Feed empty input to read -> default keep
if echo "" | guarded_copy "$src" "$dest" "source.md" >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    ERRORS+=("keep-local: guarded_copy should have returned non-zero on keep")
else
    PASS=$((PASS + 1))
fi
assert_equal "keep-local: dest unchanged" "locally edited" "$(cat "$dest")"

# --- Case 4: [o] overwrites local edit ------------------------------------
new_case "overwrite-choice"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1\n' > "$src"
guarded_copy "$src" "$dest" "source.md"
printf 'locally edited\n' > "$dest"
printf 'v2\n' > "$src"
echo "o" | guarded_copy "$src" "$dest" "source.md" >/dev/null
assert_equal "overwrite-choice: dest reflects v2" "v2" "$(cat "$dest")"

# --- Case 5: BOOTSTRAP_FORCE=1 bypasses prompt ----------------------------
new_case "force-flag"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1\n' > "$src"
guarded_copy "$src" "$dest" "source.md"
printf 'locally edited\n' > "$dest"
printf 'v2\n' > "$src"
BOOTSTRAP_FORCE=1 guarded_copy "$src" "$dest" "source.md"
assert_equal "force-flag: dest reflects v2" "v2" "$(cat "$dest")"

# --- Case 6: prune deletes removed managed file when unmodified -----------
new_case "prune-unmodified-removed"
src="$CASE_DIR/old-source.md"
dest="$CASE_DIR/old.md"
printf 'managed v1\n' > "$src"
guarded_copy "$src" "$dest" "old.md"
prune_log=$(manifest_prune_removed "$CASE_DIR" "active.md")
assert_missing "prune-unmodified: removed managed file deleted" "$dest"
assert_not_contains "prune-unmodified: manifest entry removed" "old.md" "$(cat "$MANIFEST_PATH")"
assert_contains "prune-unmodified: clear prune log" "Pruned removed managed file: old.md" "$prune_log"

# --- Case 7: prune preserves removed managed file after local edit ---------
new_case "prune-local-edit"
src="$CASE_DIR/old-source.md"
dest="$CASE_DIR/old.md"
printf 'managed v1\n' > "$src"
guarded_copy "$src" "$dest" "old.md"
printf 'locally edited removed file\n' > "$dest"
prune_log=$(manifest_prune_removed "$CASE_DIR" "active.md")
assert_equal "prune-local-edit: dest unchanged" "locally edited removed file" "$(cat "$dest")"
assert_contains "prune-local-edit: manifest entry retained" "old.md" "$(cat "$MANIFEST_PATH")"
assert_contains "prune-local-edit: clear preserve log" "Preserved locally edited removed managed file: old.md" "$prune_log"

# --- Case 8: retired ownership seed prunes known unmodified files ----------
new_case "prune-retired-seed"
mkdir -p "$CASE_DIR/commands"
retired="$CASE_DIR/commands/old-command.md"
printf 'retired upstream command\n' > "$retired"
retired_sha=$(_manifest_hash "$retired")
printf 'retired upstream command\r\n' > "$retired"
seed_log=$(manifest_seed_retired_managed "$CASE_DIR" "commands/old-command.md" "$retired_sha")
prune_log=$(manifest_prune_removed "$CASE_DIR" "commands/_policy.md")
assert_contains "prune-retired-seed: seed logged" "matched retired managed file: commands/old-command.md" "$seed_log"
assert_missing "prune-retired-seed: retired file deleted" "$retired"
assert_contains "prune-retired-seed: prune logged" "Pruned removed managed file: commands/old-command.md" "$prune_log"

# --- Case 9: retired seed preserves edited files without manifest ownership -
new_case "prune-retired-local-edit"
mkdir -p "$CASE_DIR/commands"
retired="$CASE_DIR/commands/old-command.md"
printf 'retired upstream command\n' > "$retired"
retired_sha=$(_manifest_hash "$retired")
printf 'local rewrite of old command\n' > "$retired"
seed_log=$(manifest_seed_retired_managed "$CASE_DIR" "commands/old-command.md" "$retired_sha")
assert_equal "prune-retired-local-edit: file preserved" "local rewrite of old command" "$(cat "$retired")"
assert_contains "prune-retired-local-edit: preserve logged" "preserved locally edited retired file: commands/old-command.md" "$seed_log"
if [ -f "$MANIFEST_PATH" ]; then
    assert_not_contains "prune-retired-local-edit: no ownership added" "old-command.md" "$(cat "$MANIFEST_PATH")"
else
    PASS=$((PASS + 1))
fi

# --- Case 10: a hand-aligned file refreshes the stored hash (#974) ---------
# The user copies the new upstream file over the deployed one by hand. Nothing
# needs copying, but the stored hash must follow, or the next upstream change
# reports a local edit that does not exist and prompts for it.
new_case "hash-refresh"
src="$CASE_DIR/source.md"
dest="$CASE_DIR/dest.md"
printf 'v1\n' > "$src"
guarded_copy "$src" "$dest" "source.md"
printf 'v2\n' > "$src"
cp "$src" "$dest"
guarded_copy "$src" "$dest" "source.md"
assert_equal "hash-refresh: stored hash follows the aligned file" \
    "$(_manifest_hash "$src")" "$(_manifest_read "source.md")"
printf 'v3\n' > "$src"
refresh_out=""
if refresh_out="$(guarded_copy "$src" "$dest" "source.md" < /dev/null 2>&1)"; then :; fi
assert_equal "hash-refresh: next upstream change upgrades" "v3" "$(cat "$dest")"
assert_not_contains "hash-refresh: no prompt" "Local changes detected" "$refresh_out"

# --- Installer cases (#974) ------------------------------------------------
# The real scripts/install.sh (global, --yes) on a minimal fixture and a
# temporary HOME, installed with the exclusive_bilingual content policy and
# then reinstalled over.
if command -v jq > /dev/null 2>&1; then
    INSTALL_FIXTURE="$WORK/install-fixture"
    FAKE_BIN="$WORK/fake-bin"
    mkdir -p "$INSTALL_FIXTURE/scripts/lib" "$INSTALL_FIXTURE/global/hooks/lib" \
        "$INSTALL_FIXTURE/hooks/lib" "$FAKE_BIN"
    printf '%s\n' '#!/bin/sh' 'echo "claude test"' > "$FAKE_BIN/claude"
    chmod +x "$FAKE_BIN/claude"
    cp scripts/install.sh scripts/install-manifest.sh "$INSTALL_FIXTURE/scripts/"
    cp scripts/lib/install-prompts.sh "$INSTALL_FIXTURE/scripts/lib/"
    cp global/commit-settings.md global/commit-settings.md.tmpl "$INSTALL_FIXTURE/global/"
    printf 'CLAUDE.md v1\n' > "$INSTALL_FIXTURE/global/CLAUDE.md"
    printf '%s\n' '{"fixture": "974", "env": {"ENABLE_TOOL_SEARCH": "auto:10"}}' \
        > "$INSTALL_FIXTURE/global/settings.json"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$INSTALL_FIXTURE/global/hooks/example.sh"
    for lib in tokenize-shell.sh path-utils.sh timeout-wrapper.sh rotate.sh; do
        printf '%s\n' '#!/bin/sh' 'return 0 2>/dev/null || exit 0' > "$INSTALL_FIXTURE/global/hooks/lib/$lib"
    done
    for lib in validate-commit-message.sh validate-language.sh validate-traceability.sh; do
        printf '%s\n' '#!/bin/sh' 'return 0 2>/dev/null || exit 0' > "$INSTALL_FIXTURE/hooks/lib/$lib"
    done

    # run_install <output>: answers every guarded-copy prompt with k.
    INSTALL_HOME="$WORK/install-home"
    mkdir -p "$INSTALL_HOME"
    run_install() {
        printf 'k\nk\nk\nk\n' | env -u MANIFEST_PATH -u BOOTSTRAP_FORCE -u CLAUDE_MEMORY_REPO_URL \
            HOME="$INSTALL_HOME" USERPROFILE="$INSTALL_HOME" PATH="$FAKE_BIN:$PATH" \
            AGENT_LANGUAGE=korean CONTENT_LANGUAGE=exclusive_bilingual INSTALL_NPM=n \
            LAUNCHD_TARGET_DIR="$INSTALL_HOME/launchd-staging" \
            SYSTEMD_USER_DIR="$INSTALL_HOME/systemd-staging" \
            bash "$INSTALL_FIXTURE/scripts/install.sh" --type 1 --yes > "$1" 2>&1
    }
    installed="$INSTALL_HOME/.claude"
    installed_manifest() {
        jq -r --arg k "$1" '.files[$k] // empty' "$installed/.install-manifest.json"
    }

    # The only upstream revision of hooks/known-issues.json (removed in #969).
    # A pre-manifest install left it untracked, so the prune never saw it.
    known_issues="$WORK/known-issues.json"
    cat > "$known_issues" << 'JSON'
{
  "known_issues": [
    {
      "versions": "2.1.69-2.1.81",
      "version_list": ["2.1.69","2.1.70","2.1.71","2.1.72","2.1.73","2.1.74","2.1.75","2.1.76","2.1.77","2.1.78","2.1.79","2.1.80","2.1.81"],
      "severity": "warning",
      "description": "Cache efficiency regression and sentinel replacement bug",
      "references": [
        "https://github.com/anthropics/claude-code/issues/34629",
        "https://github.com/anthropics/claude-code/issues/40524"
      ]
    }
  ],
  "minimum_recommended": "2.2.0",
  "last_updated": "2026-04-05"
}
JSON
    known_sha="$(_manifest_hash "$known_issues")"
    assert_contains "bootstrap.sh seeds hooks/known-issues.json" \
        "\"hooks/known-issues.json\" \"$known_sha\"" "$(cat bootstrap.sh)"

    install_out="$WORK/install-1.out"
    if run_install "$install_out"; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); ERRORS+=("installer: first install failed: $(tail -5 "$install_out")")
    fi

    # Reinstall over: CLAUDE.md aligned with a newer upstream by hand, an
    # untracked known-issues.json, a retired and a machine-local env key, and a
    # locally edited commit-settings.md.
    printf 'CLAUDE.md v2\n' > "$INSTALL_FIXTURE/global/CLAUDE.md"
    cp "$INSTALL_FIXTURE/global/CLAUDE.md" "$installed/CLAUDE.md"
    cp "$known_issues" "$installed/hooks/known-issues.json"
    jq '.env.MAX_TEAMS = "4" | .env.SOME_LOCAL_KEY = "keep me"' "$installed/settings.json" \
        > "$WORK/settings.json" && mv "$WORK/settings.json" "$installed/settings.json"
    printf '\nlocal edit\n' >> "$installed/commit-settings.md"
    install_out="$WORK/install-2.out"
    run_install "$install_out" || true
    out="$(cat "$install_out")"
    assert_equal "installer: one prompt for an edited commit-settings.md" "1" \
        "$(grep -cF "Local changes detected in: $installed/commit-settings.md" "$install_out")"
    assert_contains "installer: edited commit-settings.md kept" "local edit" "$(cat "$installed/commit-settings.md")"
    assert_missing "installer: unedited untracked known-issues.json pruned" "$installed/hooks/known-issues.json"
    assert_contains "installer: known-issues.json prune logged" \
        "Pruned removed managed file: hooks/known-issues.json" "$out"
    assert_equal "installer: env.MAX_TEAMS dropped" "false" "$(jq -r '.env | has("MAX_TEAMS")' "$installed/settings.json")"
    assert_equal "installer: env.SOME_LOCAL_KEY kept" "keep me" "$(jq -r .env.SOME_LOCAL_KEY "$installed/settings.json")"
    assert_contains "installer: retired setting reported" "removed retired setting: env.MAX_TEAMS" "$out"
    preserved_line="$(grep -F 'machine-local settings keys preserved:' "$install_out" || true)"
    assert_contains "installer: machine-local key reported" "env.SOME_LOCAL_KEY" "$preserved_line"
    assert_not_contains "installer: retired key not reported as preserved" "MAX_TEAMS" "$preserved_line"
    assert_equal "installer: stored CLAUDE.md hash follows the aligned file" \
        "$(_manifest_hash "$INSTALL_FIXTURE/global/CLAUDE.md")" "$(installed_manifest CLAUDE.md)"

    # Next upstream CLAUDE.md, and an edited untracked known-issues.json.
    printf 'CLAUDE.md v3\n' > "$INSTALL_FIXTURE/global/CLAUDE.md"
    sed -e 's/"warning"/"error"/' "$known_issues" > "$installed/hooks/known-issues.json"
    install_out="$WORK/install-3.out"
    run_install "$install_out" || true
    out="$(cat "$install_out")"
    assert_equal "installer: newer CLAUDE.md upgrades the aligned file" "CLAUDE.md v3" "$(cat "$installed/CLAUDE.md")"
    assert_not_contains "installer: no prompt for the aligned CLAUDE.md" \
        "Local changes detected in: $installed/CLAUDE.md" "$out"
    assert_contains "installer: edited known-issues.json kept" '"error"' "$(cat "$installed/hooks/known-issues.json")"
    assert_contains "installer: edited known-issues.json reported" \
        "preserved locally edited retired file: hooks/known-issues.json" "$out"
else
    echo "SKIP: installer cases need jq"
fi

# --- Summary --------------------------------------------------------------
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
