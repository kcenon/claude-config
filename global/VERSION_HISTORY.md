# Global Configuration Version History

## Changelog

- **1.5.0** (2026-03-21): Skills migration, Agent Teams, Windows support, new hooks
  - Migrated global commands to Skills format (context isolation, model override)
  - Added new global skills: doc-review, implement-all-levels
  - Added Agent Teams experimental framework with TeamCreate/TaskList coordination
  - Added Windows PowerShell support (install.ps1, .ps1 hook variants, settings.windows.json)
  - Added 8 new hook types: github-api-preflight, markdown-anchor-validator, prompt-validator,
    tool-failure-logger, subagent-logger, task-completed-logger, config-change-logger, pre-compact-snapshot
  - Added worktree lifecycle hooks (worktree-create, worktree-remove)
  - Added tmux auto-logging configuration (tmux.conf)
  - Added status line configuration (ccstatusline/)
  - Added GitHub CLI helper scripts (scripts/gh/)
  - Reduced always-on context by 77% via SSOT refactoring

- **1.4.0** (2026-01-22): Simplified CLAUDE.md following official best practices
  - Reduced global/CLAUDE.md from 67 to 34 lines
  - Moved version history to separate file
  - Focused on essential information only

- **1.3.0** (2026-01-22): Adopted Import syntax (`@path/to/file`) for modular references
  - Replaced markdown links with Import syntax
  - Supports recursive imports up to 5 levels deep

- **1.2.0** (2026-01-15): CLAUDE.md optimization for official best practices compliance

- **1.1.0** (2026-01-15): Added rules, commands, agents, MCP configuration

- **1.0.0** (2025-12-03): Initial release with Skills system
