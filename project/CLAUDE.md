# Universal Development Guidelines

Conventions for this repository. Works with `~/.claude/CLAUDE.md` (global).
Rules use YAML frontmatter for automatic loading. Defer to language-specific conventions (PEP 8, C++ Core Guidelines, etc.).

## On-Demand Rules (path-triggered)

Loaded when matching files are open:
- `coding/` -- standards, error-handling, performance, safety, cpp-specifics, implementation-standards
- `compliance/` -- per-standard rules (IEC 62304, ISO 13485, ISO 14971) for safety-regulated projects
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

Stored in `.claude/reference/` (`api/`, `coding/`, `project-management/`, `workflow/`,
and `security-examples.md` at its root), outside the auto-loaded
`.claude/rules/` tree so they are never injected by default. Load with `@load: reference/<name>`:
- `anti-patterns` -- Before/after examples for core principles
- `5w1h-examples` -- Issue/PR templates with full 5W1H
- `agent-teams` -- Multi-agent patterns and configuration
- `commit-hooks` -- Git hook scripts and CI verification
- `session-resume-templates` -- Resume file format templates
- `automation-patterns` -- GitHub Actions patterns
- `issue-examples` -- Issue splitting and examples
- `label-definitions` -- GitHub label taxonomy
- `api-design-examples`, `architecture-examples`, `observability-examples` -- Worked samples for the `api/` rules
- `performance-examples`, `error-handling-examples`, `safety-examples` -- Worked samples for the `coding/` rules
- `documentation-templates`, `build-examples`, `testing-examples` -- Templates and samples for the `project-management/` rules
- `security-examples` -- Worked samples for `security.md`

## Skills

> Presence is not availability: `skillOverrides` in `.claude/settings.local.json`
> disables individual skills, and a disabled skill fails silently. That file is
> machine-local -- no installer creates it, `.gitignore` excludes it -- so a
> directory listing of `.claude/skills/` does not tell you which skills are
> active. Absent the key, as in the shipped template, all are enabled.

## MCP

Use `.mcp.json` at project root for team-shared MCP server definitions (committed to Git).
See `.mcp.json.example` for transport examples. Never hardcode secrets -- use `${VAR}` in `.env`.
