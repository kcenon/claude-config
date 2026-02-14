# Universal Development Guidelines

Universal conventions for this repository. Works with global settings in `~/.claude/CLAUDE.md`.

> **Note**: This configuration includes both official Claude Code features and custom extensions.
> See [docs/CUSTOM_EXTENSIONS.md](../docs/CUSTOM_EXTENSIONS.md) for portability information.

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
| **Core** | `.claude/rules/core/` | Principles, environment, communication |
| **Workflow** | `.claude/rules/workflow/` | Git commit format, GitHub issue/PR guidelines (5W1H), performance analysis |
| **Coding** | `.claude/rules/coding/` | Standards, safety, error handling, performance, C++ specifics, implementation |
| **API** | `.claude/rules/api/` | API design, observability, architecture, REST |
| **Operations** | `.claude/rules/operations/` | Ops (cleanup + monitoring) |
| **Project Mgmt** | `.claude/rules/project-management/` | Build, testing, documentation standards |
| **Security** | `.claude/rules/` | Security guidelines |
| **Tools** | `.claude/rules/tools/` | GitHub CLI script wrappers (`scripts/gh/`) |

### Conditional Loading

Rules load automatically based on YAML frontmatter:
- **`alwaysApply: true`**: Always loaded (core settings)
- **`paths` patterns**: Loaded when editing matching files

Glob pattern examples: `**/*.ts` (all TS files), `src/**/*` (files under src/), `**/*.{ts,tsx}` (multiple extensions).

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

**Design documents** (conceptual architecture, not implemented by Claude Code):
- `docs/design/intelligent-prefetching.md` - Predictive loading concept
- `docs/design/module-caching.md` - Cache tier concept
- `docs/design/module-priority.md` - Priority loading concept

Selective rule loading via YAML frontmatter and `.claudeignore` reduces initial token usage.

To load reference documents when needed:
```markdown
@load: reference/label-definitions
Can you review rules/workflow/reference/label-definitions.md?
```

Token optimization is achieved through selective rule loading and `.claudeignore`.

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

*Version: 3.0.0 | Last updated: 2026-02-15*
