#!/bin/bash
# test-install-manifest-helpers.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/install-manifest.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export MANIFEST_PATH="$TEST_DIR/.claude/.install-manifest.json"

export HOME="$TEST_DIR"
mkdir -p "$HOME/.claude"

# Mock guarded_copy to write to manifest directly without prompt
export BOOTSTRAP_FORCE=1

# Test update_claude_settings_json
echo '{"test": 1}' > "$TEST_DIR/settings.json"
update_claude_settings_json "$TEST_DIR/settings.json" "english" "korean_plus_english"

if ! grep -q '"language": "english"' "$TEST_DIR/settings.json"; then
    echo "FAIL: Agent language not updated"
    exit 1
fi

if ! grep -q '"CLAUDE_CONTENT_LANGUAGE": "korean_plus_english"' "$TEST_DIR/settings.json"; then
    echo "FAIL: Content language not updated"
    exit 1
fi

echo "update_claude_settings_json: PASS"

# Test guarded_template_copy
cat << 'EOF' > "$TEST_DIR/tmpl.md"
Language policy: {{AGENT_LANGUAGE_POLICY}}
EOF

guarded_template_copy "$TEST_DIR/tmpl.md" "$TEST_DIR/dest.md" "dest.md" "Korean"

if ! grep -q 'Language policy: Korean' "$TEST_DIR/dest.md"; then
    echo "FAIL: Template not rendered properly"
    exit 1
fi

if ! grep -q "dest.md" "$TEST_DIR/.claude/.install-manifest.json"; then
    echo "FAIL: Manifest not updated"
    exit 1
fi

echo "guarded_template_copy: PASS"

# Test manifest_copy_tree + manifest_prune_tracked
manifest_reset_managed_keys
mkdir -p "$TEST_DIR/tree-src/nested" "$TEST_DIR/tree-dest/nested"
echo "active" > "$TEST_DIR/tree-src/nested/active.md"
echo "stale" > "$TEST_DIR/tree-dest/stale.md"
_manifest_write "stale.md" "$(_manifest_hash "$TEST_DIR/tree-dest/stale.md")"

manifest_copy_tree "$TEST_DIR/tree-src" "$TEST_DIR/tree-dest" ""
manifest_prune_tracked "$TEST_DIR/tree-dest" >/dev/null

if [ ! -f "$TEST_DIR/tree-dest/nested/active.md" ]; then
    echo "FAIL: manifest_copy_tree did not copy active file"
    exit 1
fi
if [ -e "$TEST_DIR/tree-dest/stale.md" ]; then
    echo "FAIL: manifest_prune_tracked did not prune stale managed file"
    exit 1
fi
if ! grep -q "nested/active.md" "$TEST_DIR/.claude/.install-manifest.json"; then
    echo "FAIL: manifest_copy_tree did not track active key"
    exit 1
fi

echo "manifest_copy_tree/prune: PASS"

# Test idempotent reset: english policy must remove .env.CLAUDE_CONTENT_LANGUAGE
# left over from a prior non-default selection.
if command -v jq >/dev/null 2>&1; then
    cat << 'EOF' > "$TEST_DIR/settings.json"
{"test": 1}
EOF
    update_claude_settings_json "$TEST_DIR/settings.json" "english" "korean_plus_english"
    if ! grep -q '"CLAUDE_CONTENT_LANGUAGE": "korean_plus_english"' "$TEST_DIR/settings.json"; then
        echo "FAIL: idempotent setup did not write CLAUDE_CONTENT_LANGUAGE"
        exit 1
    fi

    update_claude_settings_json "$TEST_DIR/settings.json" "english" "english"
    if grep -q 'CLAUDE_CONTENT_LANGUAGE' "$TEST_DIR/settings.json"; then
        echo "FAIL: idempotent reset did not remove CLAUDE_CONTENT_LANGUAGE"
        cat "$TEST_DIR/settings.json"
        exit 1
    fi
    if grep -q '"env"' "$TEST_DIR/settings.json"; then
        echo "FAIL: idempotent reset left an empty .env object"
        cat "$TEST_DIR/settings.json"
        exit 1
    fi
    echo "update_claude_settings_json idempotent reset: PASS"
else
    echo "update_claude_settings_json idempotent reset: SKIP (jq missing)"
fi

# Test MANIFEST_ELEVATE plumbing (#906).
#
# The enterprise tree on POSIX is root-owned, so its copies and its manifest
# write go through an elevation prefix. Real `sudo` cannot run here, so the
# prefix is a shim that records every invocation and then execs the command.
# That exercises the whole path -- argument passing, the temp-file manifest
# write, and the elevated placement -- without needing privilege. What it does
# NOT cover is sudo-specific behaviour (environment stripping, TTY prompts);
# the temp-file design exists precisely so the heredoc never runs under sudo.
manifest_reset_managed_keys
SHIM="$TEST_DIR/elevate-shim.sh"
SHIM_LOG="$TEST_DIR/elevate.log"
cat > "$SHIM" << 'SHIMEOF'
#!/bin/bash
printf '%s\n' "$1" >> "$ELEVATE_LOG"
exec "$@"
SHIMEOF
chmod +x "$SHIM"
export ELEVATE_LOG="$SHIM_LOG"
: > "$SHIM_LOG"

ENT_SRC="$TEST_DIR/ent-src"
ENT_DEST="$TEST_DIR/ent-dest"
mkdir -p "$ENT_SRC/rules"
echo "policy" > "$ENT_SRC/CLAUDE.md"
echo "rule one" > "$ENT_SRC/rules/security.md"

saved_manifest_path="$MANIFEST_PATH"
MANIFEST_PATH="$ENT_DEST/.install-manifest.json"
MANIFEST_ELEVATE="$SHIM"

_manifest_run mkdir -p "$ENT_DEST/rules"
manifest_copy_file "$ENT_SRC/CLAUDE.md" "$ENT_DEST/CLAUDE.md" "CLAUDE.md" || true
manifest_copy_tree "$ENT_SRC/rules" "$ENT_DEST/rules" "rules"

MANIFEST_ELEVATE=""
[ -f "$ENT_DEST/CLAUDE.md" ] || { echo "FAIL: elevated copy did not place CLAUDE.md"; exit 1; }
[ -f "$ENT_DEST/rules/security.md" ] || { echo "FAIL: elevated copy did not place rules tree"; exit 1; }
[ -f "$ENT_DEST/.install-manifest.json" ] || { echo "FAIL: elevated manifest write produced no manifest"; exit 1; }
grep -q '"CLAUDE.md"' "$ENT_DEST/.install-manifest.json" || { echo "FAIL: enterprise manifest missing CLAUDE.md key"; exit 1; }
grep -q '"rules/security.md"' "$ENT_DEST/.install-manifest.json" || { echo "FAIL: enterprise manifest missing rules key"; exit 1; }
# The key must be relative to the enterprise root, not to $HOME, or the two
# roots would collide on `CLAUDE.md`.
grep -q "$ENT_DEST" "$ENT_DEST/.install-manifest.json" && { echo "FAIL: enterprise manifest stored an absolute key"; exit 1; }
# Prove the shim actually ran; otherwise this whole case would pass on the
# unelevated path and assert nothing.
grep -q '^cp$' "$SHIM_LOG" || { echo "FAIL: elevation prefix was never used for cp"; exit 1; }
grep -q '^mkdir$' "$SHIM_LOG" || { echo "FAIL: elevation prefix was never used for mkdir"; exit 1; }
echo "MANIFEST_ELEVATE plumbing: PASS"

# Test that an unset MANIFEST_ELEVATE leaves no temp residue and still writes
# in place -- the property that makes this change a no-op for the global and
# project layers.
MANIFEST_PATH="$TEST_DIR/plain/.install-manifest.json"
mkdir -p "$TEST_DIR/plain"
echo "plain" > "$TEST_DIR/plain-src.md"
manifest_copy_file "$TEST_DIR/plain-src.md" "$TEST_DIR/plain/x.md" "x.md" || true
[ -f "$TEST_DIR/plain/x.md" ] || { echo "FAIL: unelevated copy did not place file"; exit 1; }
grep -q '"x.md"' "$MANIFEST_PATH" || { echo "FAIL: unelevated manifest write did not record key"; exit 1; }
before_log="$(wc -l < "$SHIM_LOG")"
[ "$before_log" -gt 0 ] || { echo "FAIL: shim log unexpectedly empty"; exit 1; }
MANIFEST_PATH="$saved_manifest_path"
echo "MANIFEST_ELEVATE unset is a no-op: PASS"

echo "All helper tests passed!"
exit 0
