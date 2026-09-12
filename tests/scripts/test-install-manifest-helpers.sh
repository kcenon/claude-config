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

# merge_local_settings_keys: settings.json is published by replacing the
# destination wholesale, so anything the repo profile does not define was lost
# on every reinstall (#915). These cases pin which side wins per key.
MERGE_DIR="$TEST_DIR/merge"
mkdir -p "$MERGE_DIR"
cat > "$MERGE_DIR/profile.json" <<'JSON'
{ "description": "repo profile", "language": "korean", "effortLevel": "high",
  "permissions": { "allow": ["A"] },
  "hooks": { "PreToolUse": [{ "matcher": "Bash" }] },
  "env": { "MAX_TEAMS": "4" } }
JSON
cat > "$MERGE_DIR/live.json" <<'JSON'
{ "description": "LOCALLY EDITED", "language": "english", "effortLevel": "xhigh",
  "model": "opus", "agentPushNotifEnabled": true,
  "permissions": { "allow": ["STALE"] },
  "hooks": { "PreToolUse": [{ "matcher": "STALE" }] },
  "env": { "MAX_TEAMS": "99", "MY_LOCAL_VAR": "keep me" } }
JSON
cp "$MERGE_DIR/profile.json" "$MERGE_DIR/staged.json"
merged_keys="$(merge_local_settings_keys "$MERGE_DIR/staged.json" "$MERGE_DIR/live.json" | LC_ALL=C sort | tr '\n' ' ')"

merge_eq() {
    local label="$1" got="$2" want="$3"
    [ "$got" = "$want" ] || { echo "FAIL: $label (got '$got' want '$want')"; exit 1; }
}
merge_eq "repo description wins"       "$(jq -r .description "$MERGE_DIR/staged.json")" "repo profile"
merge_eq "repo language wins"          "$(jq -r .language "$MERGE_DIR/staged.json")" "korean"
merge_eq "repo permissions win"        "$(jq -c .permissions.allow "$MERGE_DIR/staged.json")" '["A"]'
merge_eq "repo hooks win"              "$(jq -r .hooks.PreToolUse[0].matcher "$MERGE_DIR/staged.json")" "Bash"
merge_eq "repo env value wins"         "$(jq -r .env.MAX_TEAMS "$MERGE_DIR/staged.json")" "4"
merge_eq "unknown key carried"         "$(jq -r .model "$MERGE_DIR/staged.json")" "opus"
merge_eq "unknown bool carried"        "$(jq -r .agentPushNotifEnabled "$MERGE_DIR/staged.json")" "true"
merge_eq "runtime key carried"         "$(jq -r .effortLevel "$MERGE_DIR/staged.json")" "xhigh"
merge_eq "live-only env key carried"   "$(jq -r .env.MY_LOCAL_VAR "$MERGE_DIR/staged.json")" "keep me"
merge_eq "carried names are reported"  "$merged_keys" "agentPushNotifEnabled effortLevel env.MY_LOCAL_VAR model "

# Fresh machine: no deployed settings.json at all. The staged profile must come
# through untouched, and nothing may be reported as carried.
cp "$MERGE_DIR/profile.json" "$MERGE_DIR/staged2.json"
fresh_keys="$(merge_local_settings_keys "$MERGE_DIR/staged2.json" "$MERGE_DIR/absent.json")"
merge_eq "absent live file carries nothing" "$fresh_keys" ""
diff -q "$MERGE_DIR/profile.json" "$MERGE_DIR/staged2.json" > /dev/null \
    || { echo "FAIL: absent live file altered the staged profile"; exit 1; }

# An unparseable live file must not abort the install: the publish that follows
# replaces it wholesale, which is the pre-#915 behaviour.
cp "$MERGE_DIR/profile.json" "$MERGE_DIR/staged3.json"
printf 'not json at all' > "$MERGE_DIR/broken.json"
bad_keys="$(merge_local_settings_keys "$MERGE_DIR/staged3.json" "$MERGE_DIR/broken.json")"
merge_eq "unparseable live file carries nothing" "$bad_keys" ""
diff -q "$MERGE_DIR/profile.json" "$MERGE_DIR/staged3.json" > /dev/null \
    || { echo "FAIL: unparseable live file altered the staged profile"; exit 1; }
echo "merge_local_settings_keys: PASS"

echo "All helper tests passed!"
exit 0
