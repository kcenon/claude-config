# Global Configuration Version History

## Changelog

- **Unreleased**: Add official-spec linter for SKILL.md, plugin.json, and settings.json (Issue #334, Epic #328)
  - Added `scripts/spec_lint.py` (Python core), `scripts/spec_lint.sh` (bash wrapper), and `scripts/spec_lint.ps1` (PowerShell wrapper). All three validate against canonical Claude Code 2026 schemas under `scripts/schemas/`: `skill-md.schema.json` (14 official fields, `additionalProperties: false`), `plugin-json.schema.json` (semver-validated `version`, declared `author`/`repository`/`compatibility` shapes), and `settings-json.schema.json` (declared `attribution`/`permissions`/`hooks`/`sandbox` plus enums on `teammateMode`, `effortLevel`, `defaultMode`, while keeping `additionalProperties: true` for forward-compat). Unknown SKILL.md fields surface a closest-match "did you mean" suggestion via `difflib`. Three exit codes (`0` clean, `1` violations, `2` setup error or `--strict` violations) plus `--warn-only` for soft rollout. Wired into `scripts/sync.sh --lint` (fast-path forward) and `scripts/validate_skills.sh` (warn-only advisory step). CI integration in `.github/workflows/validate-skills.yml` runs `--strict` on every PR targeting `main`, plus the regression suite at `tests/scripts/test-spec-lint.{sh,ps1}` (12 cases including a full-repo lint-clean guard). Documented in `docs/CUSTOM_EXTENSIONS.md` (Spec Linter section).

- **Unreleased**: Adopt InstructionsLoaded, PostCompact, and TaskCreated hook events (Issue #333)
  - Subscribed three new harness events in `global/settings.json` and `global/settings.windows.json`. `InstructionsLoaded` runs `instructions-loaded-reinforcer` to re-inject `commit-settings.md`, branching policy, and Conventional Commits rules immediately after `CLAUDE.md` and `.claude/rules/*.md` are ingested, eliminating policy drift in long sessions. `PostCompact` runs `post-compact-restore` to re-assert `core/principles.md` after every automatic compaction, pairing with the existing `pre-compact-snapshot` (PreCompact) hook and writing a correlated record to `~/.claude/logs/compact-snapshots.log`. `TaskCreated` runs `task-created-validator` as a synchronous blocking gate that rejects task descriptions shorter than 20 characters or missing a `- [ ]` acceptance-criteria checkbox, mirroring the `commit-message-guard` enforcement model. All three hooks ship with bash and PowerShell variants and fail-open on missing dependencies. Documentation added to `HOOKS.md` sections 16-18 and the Quick Navigation table.

- **Unreleased**: Modernize SKILL.md frontmatter (Issue #332)
  - Added `disable-model-invocation: true` to global workflow skills (`branch-cleanup`, `doc-index`, `doc-review`, `harness`, `implement-all-levels`, `issue-create`, `issue-work`, `pr-work`, `release`, `research`) so they only fire when the user explicitly invokes the slash command, eliminating spurious model-driven activation.
  - Added `allowed-tools` to global workflow skills (`branch-cleanup`, `issue-create`, `issue-work`, `pr-work`, `release`) declaring the tools each skill needs up front, so harness pre-approval skips per-tool prompts at runtime.
  - Added `paths` globs to plugin and project knowledge skills (`api-design`, `ci-debugging`, `coding-guidelines`, `documentation`) so they auto-load only when matching files are open.
  - Added `when_to_use` to plugin and project mirror skills (`api-design`, `ci-debugging`, `coding-guidelines`) to give Claude a clear trigger guideline distinct from the user-facing description.
  - Extended workflow frontmatter to `doc-review`, `git-status`, and `doc-update` so the same fields apply consistently across the global and project skill catalogs.
  - Touched files: 22 SKILL.md files across `global/skills/`, `plugin/skills/`, and `project/.claude/skills/`. No behavioral change to skill bodies.

- **1.9.2** (2026-04-13): Release flow — recreate develop from main after squash merge
  - Changed release procedure: delete and recreate `develop` from `main` after each release
  - Prevents history divergence caused by squash merge producing different commit SHAs
  - Updated: `docs/branching-strategy.md`, `global/skills/release/SKILL.md`, `global/CLAUDE.md`, branching-strategy rule

- **1.9.1** (2026-04-13): Documentation completeness fixes
  - Fixed `docs/branching-strategy.md`: corrected CI policy table (develop PRs do not trigger CI)
  - Added branch protection configuration table and path-filter explanation
  - Updated `README.md` directory structure: added commit-msg hook, lib/, validate-hooks.yml, branching-strategy.md
  - Updated `README.ko.md` directory structure: added pre-push, commit-msg, lib/, .github/workflows, branching-strategy.md

- **1.9.0** (2026-04-13): Simplified git-flow branching strategy (Epic #258)
  - Added `project/.claude/rules/workflow/branching-strategy.md` with branch model, workflow, and CI policy
  - Updated `global/CLAUDE.md` Standard Workflows with branching strategy and protected branch rules
  - Updated `project/CLAUDE.md` Auto-Loaded Rules to reference new branching-strategy rule
  - Restricted CI triggers to main-targeting PRs only (`validate-skills.yml`, `validate-hooks.yml`)
  - Updated skills for develop-based workflow: `/issue-work`, `/release`, `/branch-cleanup`
  - Created `docs/branching-strategy.md` contributor reference document
  - Bumped CLAUDE.md version from 3.0.0 to 3.1.0

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
