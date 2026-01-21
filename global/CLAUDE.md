# Claude Code Global Configuration

This is the global configuration for all Claude Code sessions. These settings apply across all projects unless overridden by project-specific `CLAUDE.md` files.

## Configuration Modules (Import Syntax)

The configuration is organized into focused modules using `@path/to/file` Import syntax:

### Core Settings
@token-management.md
@conversation-language.md
@git-identity.md
@commit-settings.md

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

## Version History

- **1.3.0** (2026-01-22): Adopted Import syntax (`@path/to/file`) for modular references
  - Replaced markdown links with Import syntax
  - Supports recursive imports up to 5 levels deep
- **1.2.0** (2026-01-15): CLAUDE.md optimization for official best practices compliance
  - Simplified project/CLAUDE.md (212 → ~85 lines)
  - Added emphasis expressions for key rules
  - Created common-commands.md
  - Optimized conditional-loading.md
  - Split github-issue-5w1h.md with Progressive Disclosure
- **1.1.0** (2026-01-15): Added rules, commands, agents, MCP configuration
- **1.0.0** (2025-12-03): Initial release with Skills system

---

*Last updated: 2026-01-22*
*Version: 1.3.0*