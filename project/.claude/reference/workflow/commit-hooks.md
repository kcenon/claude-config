---
alwaysApply: false
---

# Commit Hook Scripts & CI Verification

> **Loading**: Lives in `.claude/reference/`, outside the auto-loaded `.claude/rules/` tree, so it is never injected automatically. Load with `@load: reference/commit-hooks`.

## Git Hook Setup

The canonical `commit-msg` hook script lives at `hooks/commit-msg` and is installed by `hooks/install-hooks.sh` on macOS/Linux or `hooks/install-hooks.ps1` on Windows. It sources shared validation logic from `hooks/lib/validate-commit-message.sh`. There is no PreToolUse commit-message hook since #964; the `commit-msg` git hook is the only gate.

To install:

```bash
./hooks/install-hooks.sh
```

Do not copy inline scripts from prior versions of this document — they are deprecated and drift from the canonical validator.

### Enforcement Layers

| Layer | Artifact | Role | Bypassable? |
|-------|----------|------|-------------|
| Attribution config | `settings.json` `attribution: ""` | Prevents Claude from adding attribution | N/A |
| git `commit-msg` hook | `hooks/commit-msg` | Terminal gate — git itself rejects the commit | Only via `--no-verify` |

All enforcement layers share rules from `hooks/lib/validate-commit-message.sh` to prevent drift.

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
