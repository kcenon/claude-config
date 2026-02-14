# Claude Code Global Configuration

Global settings for all Claude Code sessions. Project-specific `CLAUDE.md` files override these.

## Core Settings (Import Syntax)

@./token-management.md
@./conversation-language.md
@./git-identity.md
@./commit-settings.md

## Priority Rules

**IMPORTANT**: Understand these priority rules to resolve conflicts correctly.

1. **Project overrides global** - Project `CLAUDE.md` takes precedence
2. **YAML frontmatter loading** - Rules load based on `alwaysApply` and `paths` in frontmatter
3. **Token optimization** - `.claudeignore` and selective rule loading reduce context size

## Quick Reference

| Setting | Source | Value | Override |
|---------|--------|-------|----------|
| Response language | `settings.json` | Korean | Project `settings.json` |
| Git identity | System git config | User's config | Not overridable |
| Claude attribution | `settings.json` | Disabled | Not overridable |
| Output style | `settings.json` | Explanatory | Project `settings.json` |

## Official Settings (settings.json)

Key behaviors are now configured via official `settings.json` options:

| Setting | Value | Purpose |
|---------|-------|---------|
| `language` | `"korean"` | Default response language |
| `attribution.commit` | `""` | No Claude attribution in commits |
| `attribution.pr` | `""` | No Claude attribution in PRs |
| `outputStyle` | `"Explanatory"` | Detailed explanations |
| `showTurnDuration` | `true` | Display turn timing |

See `settings.json` for the complete configuration.

## Token Optimization

Token usage is reduced through two mechanisms:

1. **`.claudeignore`** excludes unnecessary files from context:
   - Plugin marketplace, session memory, command/skill definitions, caches

2. **YAML frontmatter** controls selective rule loading:
   - `alwaysApply: true` — Core rules loaded every session
   - `paths` patterns — Rules loaded only when editing matching files

See `token-optimization.md` in project rules for details.

## Configuration Updates

1. Edit module files (e.g., `token-management.md`)
2. Restart session to apply changes

---

*Version: 1.5.0 | Last updated: 2026-02-03*
