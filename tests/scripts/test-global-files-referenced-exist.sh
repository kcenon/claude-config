#!/bin/bash
# test-global-files-referenced-exist.sh
# Regression guard for issue #777.
#
# Every global/<file> that the installers copy into ~/.claude must actually
# exist in the repo, as either the static <file> or its <file>.tmpl template
# form. This prevents the silent-skip class of bug that #777 fixed, where the
# bootstrap.sh / install.sh copy loops referenced git-identity.md and
# token-management.md that had never been committed — so the copy loop's
# `[ -f "$src" ] || continue` guard skipped them without any error, the
# personalize step opened an empty buffer, and the #748 auto-fill had no file
# to patch.
#
# Run: bash tests/scripts/test-global-files-referenced-exist.sh
# Exit: 0 when all referenced files exist, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GLOBAL_DIR="$REPO_ROOT/global"

PASS=0
FAIL=0

# Assert that global/<name> exists as a static file or a .tmpl template.
assert_global_exists() {
    local name="$1" src="$2"
    if [ -f "$GLOBAL_DIR/$name" ] || [ -f "$GLOBAL_DIR/$name.tmpl" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $name (referenced by $src)"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $name referenced by $src but missing from global/"
    fi
}

echo "=== global/ referenced-file existence test (#777) ==="
echo ""

# 1) Bash copy loops: `for gf in CLAUDE.md commit-settings.md ... ; do`
for installer in bootstrap.sh scripts/install.sh; do
    while IFS= read -r line; do
        files="$(echo "$line" | sed -E 's/.*for gf in //; s/;[[:space:]]*do.*//')"
        for f in $files; do
            [[ "$f" == *.md ]] || continue
            assert_global_exists "$f" "$installer"
        done
    done < <(grep -E "for gf in .*\.md" "$REPO_ROOT/$installer")
done

# 2) PowerShell copy loops: `$globalFiles = @('CLAUDE.md', ...)`
for installer in bootstrap.ps1 scripts/install.ps1; do
    while IFS= read -r line; do
        files="$(echo "$line" | grep -oE "'[^']+\.md'" | tr -d "'")"
        for f in $files; do
            assert_global_exists "$f" "$installer"
        done
    done < <(grep -E "globalFiles = @\(" "$REPO_ROOT/$installer")
done

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
