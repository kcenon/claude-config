# Global Configuration Version History

## Changelog

- **1.8.0** (2026-04-13): Pre-push hook for protected branch enforcement
  - Added `hooks/pre-push` (bash) and `hooks/pre-push.ps1` (PowerShell) to block direct pushes to `main` and `develop`
  - Updated `hooks/install-hooks.sh` and `hooks/install-hooks.ps1` to install the pre-push hook
  - Protected branches require pull request workflow; bypass via `--no-verify` is forbidden by policy

- **1.7.0** (2026-04-08): Usage-report-driven behavioral guardrails, agent migration, and platform fixes
  - Migrated agent config files from `allowed-tools` to `tools` format (7 files across project and plugin)
  - Added behavioral rules to CLAUDE.md: bias toward execution, CI verification, multi-repo parallel agents
  - Created `/doc-update` project skill for execution-first document updates (project skills: 10 → 11)
  - Synced global v1.7.0 changes to project rules (principles, environment, build-verification, ci-resilience)
  - Added "Working Principles" section to CLAUDE.md (behavioral guardrails: challenge, minimize, surgical, verify)
  - Added "Platform Notes" section to CLAUDE.md (UTF-8 BOM encoding, Mermaid preference)
  - Enhanced "Build & Test" with batch error fixing and 3-failure escape hatch
  - Fixed settings.windows.json missing TeamCreate/team-limit-guard hook
  - Fixed settings.json (base) missing attribution.issue and autoUpdatesChannel
  - Bumped settings.json to v1.12.0, CLAUDE.md to v2.5.0

- **1.6.0** (2026-04-03): Harness skill, QA agent, batch processing, version-check hook
  - Added harness meta-skill for agent team and skill architecture design
  - Added qa-reviewer agent for integration coherence verification
  - Added version-check SessionStart hook for known cache bug warnings
  - Added batch processing mode to issue-work and pr-work skills
  - Extended CI skill validation with description quality and global skills checks
  - Enhanced skill descriptions for better trigger accuracy
  - Added reference docs: orchestrator patterns, skill testing guide, agent design patterns
  - Added THIRD_PARTY_NOTICES.md for harness content attribution (Apache 2.0)

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
