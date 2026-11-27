#!/usr/bin/env bash
# test-verify-sync.sh -- scripts/verify.sh compares every file the installers
# deploy: hook libraries, non-markdown skill files and an installed project,
# not only the top-level .sh hooks and *.md skills (#944).
#
# Lays out a deployed global layer and project the way the installers do, in a
# temporary HOME and project directory, and checks that verify.sh reports
# nothing. Then damages the tree the ways a stale install differs and checks
# that each difference is reported, and that a line-ending-only change is not.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/verify-sync.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

HOME_DIR="$TMP/home"
CLAUDE="$HOME_DIR/.claude"
PROJ="$TMP/project"
OUT="$TMP/out.txt"
mkdir -p "$CLAUDE/hooks/lib" "$PROJ/.claude"

case "${OS:-}$(uname -s 2> /dev/null)" in
    Windows_NT* | *MINGW* | *MSYS* | *CYGWIN*) win=1 ;;
    *) win=0 ;;
esac

# Global layer, with the file lists of install.sh / install.ps1.
for f in CLAUDE.md commit-settings.md .claudeignore; do
    cp "$REPO_ROOT/global/$f" "$CLAUDE/$f"
done
if [ "$win" -eq 1 ]; then
    settings_profile="$REPO_ROOT/global/settings.windows.json"
else
    settings_profile="$REPO_ROOT/global/settings.json"
fi
# This HOME has no memory sync, so the installers publish the profile without
# the memory hooks (#1024). Their own helper drops them here too.
cp "$settings_profile" "$CLAUDE/settings.json"
(
    export HOME="$HOME_DIR"
    unset CLAUDE_MEMORY_REPO_URL
    . "$REPO_ROOT/scripts/install-manifest.sh"
    drop_memory_hooks_unless_synced "$CLAUDE/settings.json" > /dev/null
)
cp -R "$REPO_ROOT/global/skills" "$CLAUDE/skills"
for f in "$REPO_ROOT"/global/hooks/*; do
    if [ -f "$f" ]; then cp "$f" "$CLAUDE/hooks/"; fi
done
for f in "$REPO_ROOT"/global/hooks/lib/*; do
    if [ -f "$f" ]; then cp "$f" "$CLAUDE/hooks/lib/"; fi
done
for lib in validate-commit-message.sh validate-language.sh validate-traceability.sh; do
    cp "$REPO_ROOT/hooks/lib/$lib" "$CLAUDE/hooks/lib/"
done
# Memory sync scripts and validators: install.sh / bootstrap.sh only (#958).
# Memory sync is Unix-only (#795), so install.ps1 deploys none of them.
if [ "$win" -eq 0 ]; then
    mkdir -p "$CLAUDE/scripts/memory"
    for f in memory-sync.sh memory-status.sh memory-notify.sh; do
        cp "$REPO_ROOT/scripts/$f" "$CLAUDE/scripts/"
    done
    cp "$REPO_ROOT"/scripts/memory/*.sh "$CLAUDE/scripts/memory/"
fi

# Project layer. The installers render rules/X.md.tmpl over X.md.
cp "$REPO_ROOT/project/CLAUDE.md" "$REPO_ROOT/project/.claudeignore" "$PROJ/"
cp "$REPO_ROOT/project/.claude/settings.json" "$PROJ/.claude/"
for d in rules reference skills commands agents; do
    if [ -d "$REPO_ROOT/project/.claude/$d" ]; then
        cp -R "$REPO_ROOT/project/.claude/$d" "$PROJ/.claude/$d"
    fi
done
while IFS= read -r t; do
    sed -e 's/{{[A-Z_]*}}/rendered/g' -e '/tmpl-contract/d' "$t" > "${t%.tmpl}"
    rm -f "$t"
done < <(find "$PROJ/.claude/rules" -name '*.md.tmpl' -type f)
echo '{"files": {}}' > "$PROJ/.claude/.install-manifest.json"

esc="$(printf '\033')"
run_verify() {
    # $1: directory to run from; remaining arguments go to verify.sh.
    local dir="$1"
    shift
    (cd "$dir" && HOME="$HOME_DIR" bash "$REPO_ROOT/scripts/verify.sh" "$@" < /dev/null 2>&1 || true) \
        | sed "s/${esc}\[[0-9;]*m//g" > "$OUT"
}
findings() {
    grep -E '(DIFF|MISS): ' "$OUT" | sed -E 's/^[^A-Z]*//' || true
}
fail() {
    echo "FAIL: $1"
    findings
    echo "--- verify.sh output, last 40 lines"
    tail -40 "$OUT"
    exit 1
}
expect() {
    grep -qF -- "$1" "$OUT" || fail "expected '$1'"
}

# 1. A complete install reports nothing, and cwd detection finds the project.
run_verify "$PROJ"
[ -z "$(findings)" ] || fail "a complete install reported differences"
expect "SYNC: project/.claude/rules/core/communication.md (rendered)"
expect "SYNC: hooks/lib/"
if [ "$win" -eq 0 ]; then
    expect "SYNC: scripts/memory-sync.sh"
    expect "SYNC: scripts/memory/validate.sh"
else
    grep -q 'scripts/memory' "$OUT" && fail "a Windows tree checked the memory scripts"
fi
echo "complete install: PASS"

# 2. Outside a project the section is skipped unless --project-dir is given.
run_verify "$TMP"
expect "--project-dir <"
grep -q 'SYNC: project/' "$OUT" && fail "project section ran without a project"
run_verify "$TMP" --project-dir "$PROJ"
expect "SYNC: project/CLAUDE.md"
echo "project detection: PASS"

# 3. commit-settings.md is deployed rendered from its .tmpl for the content
# policy, so verify compares it with the rendering for the policy the installed
# settings.json records, not with the english-canonical .md (#974).
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/lib/install-prompts.sh"
cp "$CLAUDE/settings.json" "$TMP/settings.json.orig"
jq '.env.CLAUDE_CONTENT_LANGUAGE = "exclusive_bilingual"' "$TMP/settings.json.orig" > "$CLAUDE/settings.json"
CONTENT_LANGUAGE=exclusive_bilingual render_policy_tmpl \
    "$REPO_ROOT/global/commit-settings.md.tmpl" "$CLAUDE/commit-settings.md"
run_verify "$PROJ"
[ -z "$(findings)" ] || fail "an exclusive_bilingual install reported differences"
expect "SYNC: commit-settings.md (rendered: exclusive_bilingual)"
cp "$TMP/settings.json.orig" "$CLAUDE/settings.json"
run_verify "$PROJ"
expect "DIFF: commit-settings.md (rendered: english)"
[ "$(findings | wc -l | tr -d ' ')" -eq 1 ] || fail "expected exactly 1 finding for a policy mismatch"
cp "$REPO_ROOT/global/commit-settings.md" "$CLAUDE/commit-settings.md"
echo "rendered commit-settings.md: PASS"

# 4. settings.json is compared with the profile as this machine receives it
# (#1024). Without memory sync, a deployed file that still registers the memory
# hooks is stale; with ~/.claude/memory-shared it is what the installer writes.
cp "$CLAUDE/settings.json" "$TMP/settings.json.dropped"
grep -q 'memory-' "$TMP/settings.json.dropped" && fail "the staged settings.json still has a memory hook"
cp "$settings_profile" "$CLAUDE/settings.json"
run_verify "$PROJ"
expect "DIFF: settings.json (hooks + permissions) -- hooks"
mkdir -p "$CLAUDE/memory-shared"
run_verify "$PROJ"
[ -z "$(findings)" ] || fail "with memory-shared, the full profile reported differences"
expect "SYNC: settings.json (hooks + permissions)"
rmdir "$CLAUDE/memory-shared"
cp "$TMP/settings.json.dropped" "$CLAUDE/settings.json"
echo "memory hooks in settings.json: PASS"

# 4b. Where only TMPDIR is writable, the expected profile is still built, and
# where no temp file can be created the check says so instead of reporting a
# difference in hooks (#1056). The shim stands in for such a sandbox.
SHIM_DIR="$TMP/shim-bin"
mkdir -p "$SHIM_DIR"
cp "$REPO_ROOT/tests/scripts/lib/mktemp-sandbox-shim.sh" "$SHIM_DIR/mktemp"
chmod +x "$SHIM_DIR/mktemp"
real_mktemp="$(command -v mktemp)"
run_verify_shim() {
    # $1: 1 to refuse every temp file, 0 to allow templates under TMPDIR.
    (cd "$PROJ" && HOME="$HOME_DIR" PATH="$SHIM_DIR:$PATH" TMPDIR="${TMPDIR:-/tmp}" \
        MKTEMP_SHIM_REAL="$real_mktemp" MKTEMP_SHIM_LOG="$TMP/shim.log" MKTEMP_SHIM_DENY_ALL="$1" \
        bash "$REPO_ROOT/scripts/verify.sh" < /dev/null 2>&1 || true) \
        | sed "s/${esc}\[[0-9;]*m//g" > "$OUT"
}
: > "$TMP/shim.log"
run_verify_shim 0
[ -s "$TMP/shim.log" ] || fail "verify.sh did not call the mktemp shim"
[ -z "$(findings)" ] || fail "with writes under TMPDIR only, a complete install reported differences"
expect "SYNC: settings.json (hooks + permissions)"
run_verify_shim 1
expect "FAIL: settings.json (hooks + permissions) -- could not build the expected profile"
grep -qF "DIFF: settings.json (hooks + permissions)" "$OUT" \
    && fail "a temp file failure was reported as a settings.json difference"
[ -z "$(findings)" ] || fail "a temp file failure was reported as a difference"
echo "temp files under TMPDIR, and a missing one reported as such: PASS"

# 4c. A deployed settings.json that lost the `_note` keys of the profile still
# registers the profile's hooks, so it is in sync; a changed timeout is not
# (#1063).
grep -q '"_note"' "$CLAUDE/settings.json" || fail "the staged settings.json has no _note to drop"
jq 'walk(if type == "object" then del(._note) else . end)' \
    "$TMP/settings.json.dropped" > "$CLAUDE/settings.json"
grep -q '"_note"' "$CLAUDE/settings.json" && fail "the _note keys were not dropped"
run_verify "$PROJ"
[ -z "$(findings)" ] || fail "a settings.json without _note keys reported differences"
expect "SYNC: settings.json (hooks + permissions)"
jq '(.hooks | .. | objects | select(has("timeout")) | .timeout) |= . + 1' \
    "$TMP/settings.json.dropped" > "$CLAUDE/settings.json"
run_verify "$PROJ"
expect "DIFF: settings.json (hooks + permissions) -- hooks"
cp "$TMP/settings.json.dropped" "$CLAUDE/settings.json"
echo "_note keys left out of the hooks comparison: PASS"

# 5. Each kind of drift is reported; a CRLF and BOM rewrite is not.
if [ "$win" -eq 1 ]; then
    hook_victim="edit-guard-dispatcher.ps1"
else
    hook_victim="$(cd "$REPO_ROOT/global/hooks" && find . -maxdepth 1 -name '*.sh' -type f | LC_ALL=C sort | head -1)"
    hook_victim="${hook_victim#./}"
fi
lib_victim="$(cd "$REPO_ROOT/global/hooks/lib" && find . -maxdepth 1 -name '*.sh' -type f | LC_ALL=C sort | head -1)"
lib_victim="${lib_victim#./}"
skill_victim="$(cd "$REPO_ROOT/global/skills" && find . -type f ! -name '*.md' | LC_ALL=C sort | head -1)"
skill_victim="${skill_victim#./}"
ref_victim="$(cd "$REPO_ROOT/project/.claude/reference" && find . -type f | LC_ALL=C sort | head -1)"
ref_victim="${ref_victim#./}"
crlf_victim="$CLAUDE/CLAUDE.md"

rm -f "$CLAUDE/hooks/$hook_victim"
echo "# drift" >> "$CLAUDE/hooks/lib/$lib_victim"
echo "drift" >> "$CLAUDE/skills/$skill_victim"
rm -f "$PROJ/.claude/reference/$ref_victim"
echo "drift" >> "$PROJ/.claude/rules/coding/essentials.md"
echo "{{AGENT_LANGUAGE}}" >> "$PROJ/.claude/rules/core/communication.md"
{ printf '\357\273\277'; awk '{ printf "%s\r\n", $0 }' "$REPO_ROOT/global/CLAUDE.md"; } > "$crlf_victim.new"
mv "$crlf_victim.new" "$crlf_victim"
expected_findings=6
if [ "$win" -eq 0 ]; then
    echo "# drift" >> "$CLAUDE/scripts/memory/secret-check.sh"
    expected_findings=7
fi

run_verify "$PROJ"
expect "MISS: hooks/$hook_victim"
expect "DIFF: hooks/lib/$lib_victim"
expect "DIFF: skills/$skill_victim"
expect "MISS: project/.claude/reference/$ref_victim"
expect "DIFF: project/.claude/rules/coding/essentials.md"
expect "DIFF: project/.claude/rules/core/communication.md (unrendered placeholder)"
if [ "$win" -eq 0 ]; then
    expect "DIFF: scripts/memory/secret-check.sh"
fi
[ "$(findings | wc -l | tr -d ' ')" -eq "$expected_findings" ] \
    || fail "expected exactly $expected_findings findings"
echo "drift detection: PASS"

echo "All verify sync tests passed!"
