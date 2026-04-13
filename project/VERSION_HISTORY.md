# Project Guidelines Version History

## Changelog

- **1.8.0** (2026-04-13): Add branching strategy rule
  - Added `workflow/branching-strategy.md` with branch model, workflow, and CI policy (`alwaysApply: true`)
  - Updated `CLAUDE.md` Auto-Loaded Rules to reference new branching-strategy rule

- **1.7.0** (2026-04-08): Sync behavioral guardrails and platform fixes from global v1.7.0
  - Added behavioral guardrails to core/principles.md (focus, 3-failure escape hatch, bias toward execution)
  - Added platform notes to core/environment.md (UTF-8 BOM for PowerShell, Mermaid preference)
  - Added batch error fixing and failure escape hatch to workflow/build-verification.md
  - Added post-task CI verification, CI failure policy, and multi-repo parallel strategy to workflow/ci-resilience.md
  - Migrated agent config files from `allowed-tools` to `tools` format (7 files)

- **1.6.0** (2026-03-21): Skills expansion, rule restructuring, Agent Teams reference
  - Added new project skills: ci-debugging, code-quality (user-invocable), git-status (user-invocable), pr-review (user-invocable)
  - Restructured coding/ rules: standards.md, implementation-standards.md, safety.md, cpp-specifics.md
  - Restructured core/ rules: principles.md (replaced problem-solving.md, common-commands.md)
  - Restructured operations/ rules: ops.md (replaced monitoring.md, cleanup.md)
  - Added tools/ rules: gh-cli-scripts.md
  - Added workflow rules: build-verification.md, ci-resilience.md, performance-analysis.md, session-resume.md
  - Added Agent Teams reference documentation (workflow/reference/agent-teams.md)
  - Added claude-guidelines/ standalone guidelines directory
  - Added .mcp.json.example for MCP configuration reference

- **1.5.0** (2026-01-22): Simplified CLAUDE.md following official best practices
  - Reduced project/CLAUDE.md from 97 to 67 lines
  - Moved version history to separate file

- **1.4.0** (2026-01-22): Adopted Import syntax (`@path/to/file`) for modular references
  - Replaced markdown links with Import syntax for better token efficiency

- **1.3.0** (2026-01-15): Split github-issue-5w1h.md with reference/ directory

- **1.2.0** (2026-01-15): Simplified CLAUDE.md (212 to ~85 lines) for token efficiency

- **1.1.0** (2025-12-03): Refactored workflow.md into 5 focused sub-modules

- **1.0.0** (2025-12-03): Initial unified release with full guidelines
