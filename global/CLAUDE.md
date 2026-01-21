# Claude Code Global Configuration

Global settings for all Claude Code sessions. Project-specific `CLAUDE.md` files override these.

## Core Settings (Import Syntax)

@token-management.md
@conversation-language.md
@git-identity.md
@commit-settings.md

## Priority Rules

1. **Project overrides global** - Project `CLAUDE.md` takes precedence
2. **Intelligent loading** - Auto-selects modules via `conditional-loading.md`
3. **Token optimization** - Reduces usage by ~60-70%

## Quick Reference

| Setting | Value | Override |
|---------|-------|----------|
| Response language | Korean | Project `communication.md` |
| Git identity | System config | Not overridable |
| Claude attribution | Disabled | Not overridable |
| Token display | Always | Not overridable |

## Configuration Updates

1. Edit module files (e.g., `token-management.md`)
2. Restart session to apply changes

---

*Version: 1.4.0 | Last updated: 2026-01-22*
