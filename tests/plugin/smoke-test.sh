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

  # Check referenced directories from manifest
  if [ -f "$manifest" ]; then
    local agents_ref skills_ref hooks_ref

    agents_ref="$(jq -r '.agents // empty' "$manifest")"
    skills_ref="$(jq -r '.skills // empty' "$manifest")"
    hooks_ref="$(jq -r '.hooks // empty' "$manifest")"

    if [ -n "$agents_ref" ]; then
      check_dir "$plugin_dir/$agents_ref" "$name/agents"
    fi
    if [ -n "$skills_ref" ]; then
      check_dir "$plugin_dir/$skills_ref" "$name/skills"
    fi
    if [ -n "$hooks_ref" ]; then
      local hooks_path="$plugin_dir/$hooks_ref"
      if [ -f "$hooks_path" ]; then
        pass "$name hooks file exists"
      else
        fail "$name hooks file missing: $hooks_path"
      fi
    fi
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
