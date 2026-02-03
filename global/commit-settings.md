# Commit, Issue, and PR Settings

## Official Attribution Setting

Attribution is now disabled via official `settings.json`:

```json
{
  "attribution": {
    "commit": "",
    "pr": ""
  }
}
```

This setting removes Claude attribution from all commits and PRs automatically.

## Claude Attribution Policy

**NEVER** include Claude-related information in commits, issues, and pull requests.

### Commit Messages

When creating git commits, **exclude** the following:

```
❌ 🤖 Generated with [Claude Code](https://claude.com/claude-code)
❌ Co-Authored-By: Claude <noreply@anthropic.com>
❌ Generated with Claude Code
❌ AI-assisted
❌ Any AI/Claude attribution
```

### GitHub Issues

When creating issues, **exclude** the following:

```
❌ 🤖 Generated with Claude Code
❌ Created with AI assistance
❌ Any mention of Claude or AI tools
```

### Pull Request Descriptions

When creating pull requests, **exclude** the following:

```
❌ 🤖 Generated with [Claude Code](https://claude.com/claude-code)
❌ Any mention of Claude or AI assistance
❌ AI-related footers or attributions
```

## Language Policy

**YOU MUST** write all GitHub Issues and Pull Requests in English.

This ensures:
- Global accessibility and collaboration
- Consistency with codebase standards
- Integration with automated tools

## Correct Commit Format

Use clean, professional commit messages:

```bash
# Good
git commit -m "feat(auth): add JWT token refresh mechanism"

# Bad
git commit -m "feat(auth): add JWT token refresh mechanism

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## Correct PR Format

```markdown
## Summary
- Added JWT token refresh mechanism
- Improved session management

## Test Plan
- [ ] Unit tests pass
- [ ] Integration tests pass
```

**Do NOT include** AI attribution footer in PR descriptions.

## Implementation

This policy is enforced through:
1. Official `settings.json` attribution setting (primary)
2. This configuration file (backup instruction to Claude Code)
3. Optional git hooks (see `git-commit-format.md` for hook setup)

---

*Version: 1.1.0*
