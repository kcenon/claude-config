# Universal Development Guidelines

Conventions for this repository. Works with `~/.claude/CLAUDE.md` (global).
Rules use YAML frontmatter for automatic loading. Defer to language-specific conventions (PEP 8, C++ Core Guidelines, etc.).

## Auto-Loaded Rules

Loaded every session via `alwaysApply: true`:
- `core/principles.md` -- Think, Minimize, Surgical Precision, Verify
- `core/communication.md` -- English for code/docs, Korean for conversation
- `core/environment.md` -- KST timezone, Korean locale, platform notes
- `workflow/git-commit-format.md` -- Conventional Commits format
- `workflow/session-resume.md` -- Resume interrupted workflows
- `workflow/branching-strategy.md` -- Branch model, CI policy

## On-Demand Rules (path-triggered)

Loaded when matching files are open:
- `coding/` -- standards, error-handling, performance, safety, cpp-specifics, implementation-standards
- `api/` -- api-design, architecture, observability, rest-api
- `security.md` -- auth, input validation, secrets management
- `project-management/` -- build, documentation, testing
- `operations/ops.md` -- cleanup, monitoring scripts
- `workflow/build-verification.md` -- build checklists (CMake/Makefile)
- `workflow/ci-resilience.md` -- GitHub Actions resilience
- `workflow/git-conflict-resolution.md` -- merge strategy by file type
- `workflow/github-issue-5w1h.md` -- 5W1H issue framework
- `workflow/github-pr-5w1h.md` -- 5W1H PR framework
- `workflow/performance-analysis.md` -- analysis procedure
- `tools/gh-cli-scripts.md` -- GitHub CLI automation

## Reference Docs

Load with `@load: reference/<name>`:
- `anti-patterns` -- Before/after examples for core principles
- `5w1h-examples` -- Issue/PR templates with full 5W1H
- `agent-teams` -- Multi-agent patterns and configuration
- `commit-hooks` -- Git hook scripts and CI verification
- `session-resume-templates` -- Resume file format templates
- `automation-patterns` -- GitHub Actions patterns
- `issue-examples` -- Issue splitting and examples
- `label-definitions` -- GitHub label taxonomy

## Agents

`code-reviewer`, `codebase-analyzer`, `documentation-writer`, `qa-reviewer`, `refactor-assistant`, `structure-explorer`

## Skills

`api-design`, `ci-debugging`, `code-quality`, `coding-guidelines`, `doc-update`, `documentation`, `git-status`, `performance-review`, `pr-review`, `project-workflow`, `security-audit`

## MCP

Use `.mcp.json` at project root for team-shared MCP server definitions (committed to Git).
See `.mcp.json.example` for transport examples. Never hardcode secrets -- use `${VAR}` in `.env`.
