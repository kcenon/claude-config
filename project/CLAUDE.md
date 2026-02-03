# Universal Development Guidelines

Universal conventions for this repository. Works with global settings in `~/.claude/CLAUDE.md`.

## Rule Loading Behavior

Rules use **YAML frontmatter** for path-specific automatic loading, following the official Claude Code memory documentation.

### YAML Frontmatter

Each rule file specifies when it should apply:

```yaml
---
paths:
  - "src/api/**/*.ts"    # Load when editing API files
  - "**/*.controller.ts" # Load when editing controllers
alwaysApply: false       # Only load when paths match
---
```

- **`alwaysApply: true`**: Rule loads for every conversation (core rules)
- **`paths`**: Rule loads when editing matching files (context-specific rules)

### Token Optimization

Rules are loaded selectively based on file paths being edited:
- Core rules (`core/*`, `workflow/*`) use `alwaysApply: true`
- Coding rules load only when editing source files
- API rules load only when editing API-related files

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

Rules load automatically based on YAML frontmatter:
- **`alwaysApply: true`**: Always loaded (core settings)
- **`paths` patterns**: Loaded when editing matching files

See `.claude/rules/conditional-loading.md` for glob pattern reference.

### Manual Override

```markdown
@load: security, performance    # Force load specific modules
@skip: documentation, build     # Exclude specific modules
@focus: memory-optimization     # Set focus area
```

### Reference and Design Documents

**Reference documents** (excluded by default via .claudeignore):
- `rules/workflow/reference/` - Label definitions, automation patterns, issue examples
- `rules/coding/reference/` - Detailed coding guidelines and examples
- `rules/api/reference/` - API design patterns and examples

**Design documents** (moved from rules/ to reduce token usage):
- `docs/design/intelligent-prefetching.md` - Prediction algorithms
- `docs/design/module-caching.md` - Cache implementation
- `docs/design/module-priority.md` - Loading strategy details

This optimization reduces initial token usage by **60-70%**.

To load reference documents when needed:
```markdown
@load: reference/label-definitions
Can you review rules/workflow/reference/label-definitions.md?
```

See [docs/TOKEN_OPTIMIZATION.md](../docs/TOKEN_OPTIMIZATION.md) for details.

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

*Version: 2.2.0 | Last updated: 2026-02-03*
