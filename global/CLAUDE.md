# Claude Code Global Configuration

This is the global configuration for all Claude Code sessions. These settings apply across all projects unless overridden by project-specific `CLAUDE.md` files.

## Configuration Modules

The configuration is organized into focused modules for better token efficiency:

### Core Settings

- **[Token Management](token-management.md)** - Token usage display, cost tracking, and optimization strategies
- **[Conversation Language](conversation-language.md)** - Input/output language preferences and translation policies
- **[Git Identity](git-identity.md)** - User information for git commits
- **[Commit Settings](commit-settings.md)** - Commit and PR attribution policy (no Claude references)

## Priority Rules

**IMPORTANT:** These rules determine which settings take effect:

1. **Project settings override global settings** - When a project has its own `CLAUDE.md`, those rules take precedence
2. **Intelligent loading** - Claude Code uses conditional loading rules to automatically select relevant modules (see project's `conditional-loading.md`)
3. **Explicit conflicts** - If project and global settings conflict, the project setting wins
4. **Token optimization** - Automatic module selection reduces token usage by ~60-70%

## Quick Reference

| Aspect | Global Setting | Override Location |
|--------|---------------|-------------------|
| Response language | Korean | Project `communication.md` |
| Git user info | (See git-identity.md) | Cannot override (personal identity) |
| Commit message format | (Not specified) | Project `git-commit-format.md` |
| Claude attribution | Disabled | (Not overridable) |
| Code documentation language | (Not specified) | Project `documentation.md` |
| Token display | Always show | (Not overridable) |

## Usage Notes

- These global settings emphasize **how** Claude Code interacts with you
- Project-specific settings define **what** standards to follow for code and documentation
- Both layers work together to provide consistent, personalized assistance

## Updating Configuration

To modify these settings:

1. Edit the relevant module file (e.g., `token-management.md`)
2. Changes take effect in new Claude Code sessions
3. Existing sessions may need restart to apply updates

---

*Last updated: 2025-12-03*
*Version: 1.0.0*