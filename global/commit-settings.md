# Commit, Issue, and PR Settings

## Claude Attribution Policy

**Do NOT include Claude-related information** in commits, issues, and pull requests.

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

**All GitHub Issues and Pull Requests MUST be written in English.**

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
1. This configuration file (instruction to Claude Code)
2. Optional git hooks (see `git-commit-format.md` for hook setup)

---

*Version: 1.0.0*
