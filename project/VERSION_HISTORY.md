# Project Guidelines Version History

## Changelog

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
