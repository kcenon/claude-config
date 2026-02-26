# Commit Hook Scripts & CI Verification

> **Loading**: Excluded from default context via `.claudeignore`. Load with `@load: reference/commit-hooks`.

## Git Hook Setup

### macOS commit-msg hook

```bash
mkdir -p .git/hooks

cat > .git/hooks/commit-msg << 'EOF'
#!/bin/bash
# Remove Claude-related references and emojis from commit messages

COMMIT_MSG_FILE=$1

# Remove Claude Code attribution
sed -i '' '/🤖 Generated with \[Claude Code\]/d' "$COMMIT_MSG_FILE"
sed -i '' '/Generated with Claude Code/d' "$COMMIT_MSG_FILE"

# Remove Co-Authored-By: Claude
sed -i '' '/Co-Authored-By: Claude/d' "$COMMIT_MSG_FILE"

# Remove common AI assistant references
sed -i '' '/AI-assisted/d' "$COMMIT_MSG_FILE"
sed -i '' '/Anthropic Claude/d' "$COMMIT_MSG_FILE"
sed -i '' '/claude.ai/d' "$COMMIT_MSG_FILE"

# Remove all emojis (Unicode ranges for common emojis)
perl -i -pe 's/[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]|[\x{2700}-\x{27BF}]|[\x{1F1E0}-\x{1F1FF}]//g' "$COMMIT_MSG_FILE"

# Remove empty lines at the end
sed -i '' -e :a -e '/^\s*$/d;N;ba' "$COMMIT_MSG_FILE"
EOF

chmod +x .git/hooks/commit-msg
```

### Linux/WSL commit-msg hook

```bash
cat > .git/hooks/commit-msg << 'EOF'
#!/bin/bash
COMMIT_MSG_FILE=$1

sed -i '/🤖 Generated with \[Claude Code\]/d' "$COMMIT_MSG_FILE"
sed -i '/Generated with Claude Code/d' "$COMMIT_MSG_FILE"
sed -i '/Co-Authored-By: Claude/d' "$COMMIT_MSG_FILE"
sed -i '/AI-assisted/d' "$COMMIT_MSG_FILE"
sed -i '/Anthropic Claude/d' "$COMMIT_MSG_FILE"
sed -i '/claude.ai/d' "$COMMIT_MSG_FILE"

perl -i -pe 's/[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]|[\x{2700}-\x{27BF}]|[\x{1F1E0}-\x{1F1FF}]//g' "$COMMIT_MSG_FILE"

sed -i -e :a -e '/^\s*$/d;N;ba' "$COMMIT_MSG_FILE"
EOF

chmod +x .git/hooks/commit-msg
```

## CI/CD Verification

```yaml
# .github/workflows/commit-verification.yml
name: Verify Commit Messages

on: [push, pull_request]

jobs:
  verify-commits:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Check for Claude references and emojis
        run: |
          if git log -10 --pretty=format:"%B" | grep -i -E "(claude|anthropic|ai-assisted|co-authored-by: claude)"; then
            echo "ERROR: Found Claude references in commit messages"
            exit 1
          fi

          if git log -10 --pretty=format:"%B" | perl -ne 'exit 1 if /[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]|[\x{2700}-\x{27BF}]|[\x{1F1E0}-\x{1F1FF}]/'; then
            echo "ERROR: Found emojis in commit messages"
            exit 1
          fi

          echo "No Claude references or emojis found"
```

## Cross-Platform Hook Setup Script

```bash
#!/bin/bash
# scripts/setup-git-hooks.sh

HOOKS_DIR=".git/hooks"
COMMIT_MSG_HOOK="$HOOKS_DIR/commit-msg"

cat > "$COMMIT_MSG_HOOK" << 'HOOKEOF'
#!/bin/bash
COMMIT_MSG_FILE=$1

PATTERNS=(
    "🤖 Generated with \[Claude Code\]"
    "Generated with Claude Code"
    "Co-Authored-By: Claude"
    "AI-assisted"
    "Anthropic Claude"
    "claude.ai"
    "claude code"
)

for pattern in "${PATTERNS[@]}"; do
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "/$pattern/d" "$COMMIT_MSG_FILE"
    else
        sed -i "/$pattern/d" "$COMMIT_MSG_FILE"
    fi
done

perl -i -pe 's/[\x{1F300}-\x{1F9FF}]|[\x{2600}-\x{26FF}]|[\x{2700}-\x{27BF}]|[\x{1F1E0}-\x{1F1FF}]//g' "$COMMIT_MSG_FILE"

if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' -e :a -e '/^\s*$/d;N;ba' "$COMMIT_MSG_FILE"
else
    sed -i -e :a -e '/^\s*$/d;N;ba' "$COMMIT_MSG_FILE"
fi
HOOKEOF

chmod +x "$COMMIT_MSG_HOOK"
echo "Git hooks installed successfully"
```

## Verification Commands

```bash
# Check commit message format
git log --oneline -1

# Verify author
git log -1 --format='%an <%ae>'

# Verify no Claude references
git log -1 --pretty=format:"%B" | grep -i "claude\|anthropic\|ai-assisted"
# Should return nothing (exit code 1)
```
