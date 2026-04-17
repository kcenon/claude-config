#!/usr/bin/env bash
# Plugin smoke test — validates plugin directory structure
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASSED=0
FAILED=0

pass() {
  echo "  PASS: $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

check_json() {
  local file="$1"
  if [ -f "$file" ] && jq empty "$file" 2>/dev/null; then
    pass "$file is valid JSON"
  else
    fail "$file missing or invalid JSON"
  fi
}

check_dir() {
  local dir="$1" label="$2"
  if [ -d "$dir" ]; then
    pass "$label directory exists"
  else
    fail "$label directory missing: $dir"
  fi
}

check_frontmatter() {
  local file="$1" field="$2"
  if head -20 "$file" | grep -q "^${field}:"; then
    pass "$(basename "$file") has '$field' in frontmatter"
  else
    fail "$(basename "$file") missing '$field' in frontmatter"
  fi
}

validate_plugin() {
  local plugin_dir="$1"
  local name
  name="$(basename "$plugin_dir")"

  echo ""
  echo "=== Validating $name ==="

  local manifest="$plugin_dir/.claude-plugin/plugin.json"
  check_json "$manifest"

  # Validate components at their default locations. Claude Code auto-discovers
  # agents/, skills/, hooks/hooks.json at the plugin root — no manifest path
  # fields are required (see issue #331).
  local agents_dir="$plugin_dir/agents"
  local skills_dir="$plugin_dir/skills"
  local hooks_json="$plugin_dir/hooks/hooks.json"

  if [ -d "$agents_dir" ]; then
    check_dir "$agents_dir" "$name/agents"
  fi
  if [ -d "$skills_dir" ]; then
    check_dir "$skills_dir" "$name/skills"
  fi
  if [ -f "$hooks_json" ]; then
    check_json "$hooks_json"
  fi

  # Validate SKILL.md frontmatter
  while IFS= read -r -d '' skill_file; do
    check_frontmatter "$skill_file" "name"
    check_frontmatter "$skill_file" "description"
  done < <(find "$plugin_dir" -name "SKILL.md" -print0 2>/dev/null)

  # Validate agent .md frontmatter
  local agents_dir="$plugin_dir/agents"
  if [ -d "$agents_dir" ]; then
    while IFS= read -r -d '' agent_file; do
      check_frontmatter "$agent_file" "name"
      check_frontmatter "$agent_file" "description"
    done < <(find "$agents_dir" -name "*.md" -print0 2>/dev/null)
  fi
}

# Run validation for each plugin
for plugin_dir in "$REPO_ROOT/plugin" "$REPO_ROOT/plugin-lite"; do
  if [ -d "$plugin_dir" ]; then
    validate_plugin "$plugin_dir"
  else
    echo ""
    echo "=== Skipping $(basename "$plugin_dir") (not found) ==="
  fi
done

# Summary
echo ""
echo "================================"
echo "Summary: $PASSED passed, $FAILED failed"
echo "================================"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
