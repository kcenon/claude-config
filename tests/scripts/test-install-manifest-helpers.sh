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

echo "All helper tests passed!"
exit 0
