# Universal Development Guidelines

Universal conventions for this repository. Works with global settings in `~/.claude/CLAUDE.md`.

## Rule Loading

Rules use **YAML frontmatter** for automatic loading:
- `alwaysApply: true` → Loaded every session (core rules)
- `paths` patterns → Loaded when editing matching files

## Rule Categories

| Category | Location |
|----------|----------|
| Core | `.claude/rules/core/` — Principles, environment, communication |
| Workflow | `.claude/rules/workflow/` — Commit format, 5W1H guidelines, performance analysis |
| Coding | `.claude/rules/coding/` — Standards, safety, error handling, performance |
| API | `.claude/rules/api/` — Design, observability, architecture |
| Operations | `.claude/rules/operations/` — Cleanup, monitoring |
| Project Mgmt | `.claude/rules/project-management/` — Build, testing, documentation |
| Security | `.claude/rules/security.md` |
| Tools | `.claude/rules/tools/` — GitHub CLI script wrappers |

Reference documents (excluded via `.claudeignore`, load with `@load:`):
- `rules/workflow/reference/` — Label definitions, automation patterns, commit hooks
- `rules/coding/reference/` — Anti-patterns and examples

## Settings Priority

Project settings override global when conflicts occur.

## Usage Notes

- Defer to language-specific conventions (PEP 8, C++ Core Guidelines, etc.)
- For large files: split across turns or use Edit tool incrementally

---

*Version: 4.0.0 | Last updated: 2026-02-26*
