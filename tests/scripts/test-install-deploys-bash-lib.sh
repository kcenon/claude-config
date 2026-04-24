#!/bin/bash
# Regression test for issue #447 Phase 1 / #448.
#
# Asserts that the shared bash validator library (hooks/lib/validate-*.sh)
# is deployed to ~/.claude/hooks/lib/ by both installers. Without this,
# pr-language-guard.sh falls through to its inline english-only fallback
# regardless of CLAUDE_CONTENT_LANGUAGE.
#
# Coverage split:
#   1. Source-of-truth:   repo-root hooks/lib/ must exist and define the
#                         validate_content_language dispatcher.
#   2. Unix installer:    install.sh must contain a block that copies both
#                         libs from $BACKUP_DIR/hooks/lib/ to
#                         $HOME/.claude/hooks/lib/.
#   3. Windows installer: install.ps1 must contain an equivalent block
#                         using Install-BashScript for CRLF/exec-bit
#                         normalization (regression guard for the #448 fix).
#   4. Functional:        replay the install.sh block against a temp HOME
#                         and verify both libs land, are non-empty, and
#                         the dispatcher is defined when sourced.
#
# Run: bash tests/scripts/test-install-deploys-bash-lib.sh
# Exit: 0 on all-pass, 1 on any failure.

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

# ---------------------------------------------------------------------------
# 1. Source-of-truth: repo-root hooks/lib/ contents
# ---------------------------------------------------------------------------
echo "=== Source libs in repo-root hooks/lib/ ==="

for lib in validate-commit-message.sh validate-language.sh; do
    src="$REPO_ROOT/hooks/lib/$lib"
    if [ ! -f "$src" ]; then
        fail "$lib missing from repo hooks/lib/"
        continue
    fi
    if [ ! -s "$src" ]; then
        fail "$lib exists but is empty"
        continue
    fi
    pass "$lib present and non-empty"
done

# Dispatcher must be defined by validate-language.sh (covers both installers'
# deployment contract — the hook sources this file by name).
if (. "$REPO_ROOT/hooks/lib/validate-language.sh" && command -v validate_content_language >/dev/null 2>&1); then
    pass "validate-language.sh defines validate_content_language"
else
    fail "validate-language.sh does not define validate_content_language when sourced"
fi

# ---------------------------------------------------------------------------
# 2. install.sh: deployment block present
# ---------------------------------------------------------------------------
echo ""
echo "=== install.sh deployment block ==="

INSTALL_SH="$REPO_ROOT/scripts/install.sh"
if [ ! -f "$INSTALL_SH" ]; then
    fail "scripts/install.sh missing"
elif ! grep -q 'BACKUP_DIR/hooks/lib' "$INSTALL_SH"; then
    fail "install.sh does not reference \$BACKUP_DIR/hooks/lib"
else
    pass "install.sh references \$BACKUP_DIR/hooks/lib"
fi

if grep -q 'validate-commit-message.sh validate-language.sh' "$INSTALL_SH"; then
    pass "install.sh iterates both shared libs"
else
    fail "install.sh shared-lib loop does not cover both libs"
fi

# ---------------------------------------------------------------------------
# 3. install.ps1: deployment block present (regression guard for #448)
# ---------------------------------------------------------------------------
echo ""
echo "=== install.ps1 deployment block ==="

INSTALL_PS1="$REPO_ROOT/scripts/install.ps1"
if [ ! -f "$INSTALL_PS1" ]; then
    fail "scripts/install.ps1 missing"
elif ! grep -q "Join-Path \$BackupDir 'hooks/lib'" "$INSTALL_PS1"; then
    fail "install.ps1 does not reference repo-root hooks/lib (regression)"
else
    pass "install.ps1 references repo-root hooks/lib"
fi

if grep -q "validate-commit-message.sh.*validate-language.sh\|'validate-commit-message.sh', 'validate-language.sh'" "$INSTALL_PS1"; then
    pass "install.ps1 iterates both shared libs"
else
    fail "install.ps1 shared-lib list does not cover both libs"
fi

if grep -q 'Install-BashScript.*sharedLibSource\|Install-BashScript -SourcePath \$libSrc' "$INSTALL_PS1"; then
    pass "install.ps1 uses Install-BashScript for CRLF normalization"
else
    fail "install.ps1 does not use Install-BashScript for shared-lib copy"
fi

# ---------------------------------------------------------------------------
# 4. Functional: replay the install.sh block against a temp HOME
# ---------------------------------------------------------------------------
echo ""
echo "=== Functional replay into temp HOME ==="

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t claude-install-bash-lib)"
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    fail "unable to create temp working directory (mktemp failed)"
    echo ""
    echo "Passed: $PASS"
    echo "Failed: $FAIL"
    exit 1
fi
trap 'rm -rf -- "$WORK" 2>/dev/null || true' EXIT

HOME_TMP="$WORK/home"
mkdir -p "$HOME_TMP"

# Minimal stubs mirroring install.sh helpers the block depends on.
ensure_dir() { mkdir -p "$1"; }

# Replay the deployment block with BACKUP_DIR pointing at the repo root.
BACKUP_DIR="$REPO_ROOT"
HOME="$HOME_TMP"
if [ -d "$BACKUP_DIR/hooks/lib" ]; then
    ensure_dir "$HOME/.claude/hooks/lib"
    for lib in validate-commit-message.sh validate-language.sh; do
        if [ -f "$BACKUP_DIR/hooks/lib/$lib" ]; then
            cp "$BACKUP_DIR/hooks/lib/$lib" "$HOME/.claude/hooks/lib/"
            chmod +x "$HOME/.claude/hooks/lib/$lib"
        fi
    done
fi

for lib in validate-commit-message.sh validate-language.sh; do
    deployed="$HOME/.claude/hooks/lib/$lib"
    if [ ! -f "$deployed" ]; then
        fail "$lib not deployed to temp \$HOME"
        continue
    fi
    if [ ! -s "$deployed" ]; then
        fail "$lib deployed but empty"
        continue
    fi
    if [ ! -x "$deployed" ]; then
        fail "$lib deployed but not executable"
        continue
    fi
    pass "$lib deployed, non-empty, and executable"
done

# Dispatcher must be defined after sourcing the deployed file.
if (. "$HOME/.claude/hooks/lib/validate-language.sh" && command -v validate_content_language >/dev/null 2>&1); then
    pass "deployed validate-language.sh defines validate_content_language"
else
    fail "deployed validate-language.sh does not define validate_content_language"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
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

exit 0
