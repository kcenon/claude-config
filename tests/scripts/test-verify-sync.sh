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
TMP="$(mktemp -d)"
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
    cp "$REPO_ROOT/global/settings.windows.json" "$CLAUDE/settings.json"
else
    cp "$REPO_ROOT/global/settings.json" "$CLAUDE/settings.json"
fi
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
echo "complete install: PASS"

# 2. Outside a project the section is skipped unless --project-dir is given.
run_verify "$TMP"
expect "--project-dir <"
grep -q 'SYNC: project/' "$OUT" && fail "project section ran without a project"
run_verify "$TMP" --project-dir "$PROJ"
expect "SYNC: project/CLAUDE.md"
echo "project detection: PASS"

# 3. Each kind of drift is reported; a CRLF and BOM rewrite is not.
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
echo "drift" >> "$PROJ/.claude/rules/security.md"
echo "{{AGENT_LANGUAGE}}" >> "$PROJ/.claude/rules/core/communication.md"
{ printf '\357\273\277'; awk '{ printf "%s\r\n", $0 }' "$REPO_ROOT/global/CLAUDE.md"; } > "$crlf_victim.new"
mv "$crlf_victim.new" "$crlf_victim"

run_verify "$PROJ"
expect "MISS: hooks/$hook_victim"
expect "DIFF: hooks/lib/$lib_victim"
expect "DIFF: skills/$skill_victim"
expect "MISS: project/.claude/reference/$ref_victim"
expect "DIFF: project/.claude/rules/security.md"
expect "DIFF: project/.claude/rules/core/communication.md (unrendered placeholder)"
[ "$(findings | wc -l | tr -d ' ')" -eq 6 ] || fail "expected exactly 6 findings"
echo "drift detection: PASS"

echo "All verify sync tests passed!"
