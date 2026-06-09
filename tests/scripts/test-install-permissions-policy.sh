#!/bin/bash
# Lint-style regression test: install.sh must enforce a strict permission
# policy on tracked files installed under ~/.claude.
#
# Policy:
#   ~/.claude                                  → 700 (owner-only directory)
#   ~/.claude/git-identity.md                  → 600 (sensitive: git author config)
#   ~/.claude/token-management.md              → 600 (sensitive: API token notes)
#   ~/.claude/CLAUDE.md, commit-settings.md    → 644 (world-readable docs)
#   ~/.claude/conversation-language.md         → 644 (world-readable docs)
#
# This is a lint test — it greps install.sh to ensure the policy lines exist.
# It does not invoke install.sh end-to-end (which is interactive and would
# require a fake HOME + sudo shim). A future improvement is to extract the
# chmod block into a sourceable helper and call it directly.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$ROOT_DIR/scripts/install.sh"

if [ ! -f "$INSTALL" ]; then
    echo "FAIL: install.sh not found: $INSTALL" >&2
    exit 1
fi

PASS=0
FAIL=0
ERRORS=()

check() {
    local label="$1" pattern="$2"
    if grep -qE -- "$pattern" "$INSTALL"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS+=("$label: pattern not present in install.sh — $pattern")
    fi
}

# 1. ~/.claude directory must be tightened to 0700 (owner only).
check "claude_dir_700" 'chmod 700 "\$HOME/\.claude"'

# 2. The 600-permission branch must cover both sensitive files.
#    This grep is loose (matches the && chain) so internal whitespace doesn't
#    break the test.
check "sensitive_600_branch_git_identity"  '"\$gf" = "git-identity\.md"'
check "sensitive_600_branch_token_mgmt"    '"\$gf" = "token-management\.md"'
check "sensitive_chmod_600"                'chmod 600 "\$HOME/\.claude/\$gf"'

# 3. Default branch must apply 0644 to non-sensitive tracked files.
check "default_chmod_644" 'chmod 644 "\$HOME/\.claude/\$gf"'

# 4. conversation-language.md is rendered separately (Phase 5 helper) and
#    must also be set to 0644 explicitly.
check "conversation_lang_644" 'chmod 644 "\$HOME/\.claude/conversation-language\.md"'

# --- Summary --------------------------------------------------------------
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
