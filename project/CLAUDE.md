# Universal Development Guidelines

Universal conventions for this repository. Works with global settings in `~/.claude/CLAUDE.md`.

## Core Guidelines (Import Syntax)

**YOU MUST** check environment settings first for timezone and locale.

### Environment & Workflow
@claude-guidelines/environment.md
@claude-guidelines/workflow.md
@claude-guidelines/problem-solving.md
@claude-guidelines/communication.md
@claude-guidelines/git-commit-format.md
@claude-guidelines/common-commands.md

### Code Standards
@claude-guidelines/coding-standards/general.md
@claude-guidelines/coding-standards/quality.md
@claude-guidelines/coding-standards/error-handling.md
@claude-guidelines/operations/cleanup.md

### Technical
@claude-guidelines/coding-standards/concurrency.md
@claude-guidelines/coding-standards/memory.md
@claude-guidelines/coding-standards/performance.md

### Project Management
@claude-guidelines/project-management/build.md
@claude-guidelines/project-management/testing.md
@claude-guidelines/project-management/documentation.md

### Security & Operations
@claude-guidelines/security.md
@claude-guidelines/operations/monitoring.md

### API & Architecture
@claude-guidelines/api-architecture/api-design.md
@claude-guidelines/api-architecture/logging.md
@claude-guidelines/api-architecture/observability.md
@claude-guidelines/api-architecture/architecture.md

## Module Loading

Auto-loaded via conditional loading based on task keywords and file types.
@claude-guidelines/conditional-loading.md

**NOTE**: Manual override available: `@load: security, performance` | `@skip: documentation` | `@focus: memory`

## Settings Priority

| Scope | Controls |
|-------|----------|
| **Global** | Token display, conversation language, git identity |
| **Project** | Code standards, commit format, testing requirements |

**IMPORTANT**: Project settings override global when conflicts occur.

## Usage Notes

- Defer to language-specific conventions (PEP 8, C++ Core Guidelines, etc.)
- Guidelines include collapsible example sections
- For large files: split across turns or use Edit tool incrementally

---

*Version: 1.5.0 | Last updated: 2026-01-22*
