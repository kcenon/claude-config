# Universal Development Guidelines

Universal conventions for this repository. Works with global settings in `~/.claude/CLAUDE.md`.

## Rule Auto-Loading

**Rules are automatically loaded** from `.claude/rules/` based on YAML frontmatter paths and conditional loading logic. No explicit imports needed.

### Available Rule Categories

| Category | Location | Contents |
|----------|----------|----------|
| **Core** | `.claude/rules/core/` | Environment, communication, problem-solving, common commands |
| **Workflow** | `.claude/rules/workflow/` | Git commit format, GitHub issue/PR guidelines (5W1H), question handling |
| **Coding** | `.claude/rules/coding/` | General standards, quality, error handling, concurrency, memory, performance |
| **API** | `.claude/rules/api/` | API design, logging, observability, architecture patterns |
| **Operations** | `.claude/rules/operations/` | Cleanup, monitoring |
| **Project Mgmt** | `.claude/rules/project-management/` | Build, testing, documentation standards |
| **Security** | `.claude/rules/` | Security guidelines |

### Conditional Loading

Rules load automatically based on:
- **Task keywords**: "bug", "feature", "security", etc.
- **File extensions**: `.cpp`, `.py`, `.ts`, etc.
- **Directory patterns**: `/tests/`, `/api/`, etc.

See `.claude/rules/conditional-loading.md` for complete loading rules.

### Manual Override

```markdown
@load: security, performance    # Force load specific modules
@skip: documentation, build     # Exclude specific modules
@focus: memory-optimization     # Set focus area
```

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

*Version: 2.0.0 | Last updated: 2026-01-22*
