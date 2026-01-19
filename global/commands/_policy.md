# Global Command Policies

These policies apply to all commands in this directory.

## Output Language

| Context | Language | Example |
|---------|----------|---------|
| Git operations | English | commits, PR titles, branch names |
| GitHub content | English | issues, PR descriptions, comments |
| Changelog/Release notes | English | release notes, version descriptions |
| User communication | Follow global settings | (typically Korean) |

## Attribution

| Item | Rule |
|------|------|
| Claude/AI references | **Forbidden** in all outputs |
| Co-Authored-By | **Forbidden** in commit messages |
| Bot references | **Forbidden** in issues, PRs, comments |

**Rationale**: Maintain professional commit history and documentation.

## Formatting

| Context | Rule |
|---------|------|
| Emojis | Forbidden in commits, PR titles, issue titles |
| Markdown | Allowed in PR/issue descriptions and comments |
| Commit format | Conventional Commits (`type(scope): description`) |

## Issue Linking

| Keyword | Effect |
|---------|--------|
| `Closes #NUM` | Auto-closes issue when PR merges |
| `Fixes #NUM` | Auto-closes issue when PR merges |
| `Part of #NUM` | References without auto-close |

**Required**: Use closing keywords in PR descriptions when applicable.

## Build Verification

| Stage | Requirement |
|-------|-------------|
| Before PR | All builds must pass |
| Before merge | All CI checks must pass |
| Exception | Draft PRs for work-in-progress |
