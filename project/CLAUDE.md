# Universal Development Guidelines

Universal conventions for this repository. Works with global settings in `~/.claude/CLAUDE.md`.

## Rule Loading Behavior

**CRITICAL DISCOVERY**: Claude Code automatically scans `.claude/rules/` directory regardless of CLAUDE.md or .claudeignore settings. The only reliable way to reduce token usage is to restructure the directory itself.

### Actual Loading Mechanism

1. **Directory Scanning**: Claude Code scans all `.md` files in `.claude/rules/` automatically
2. **.claudeignore**: Partially effective but has lower priority than directory scanning
3. **CLAUDE.md directives**: Cannot prevent automatic directory scanning
4. **Only solution**: Minimize files in `.claude/rules/` directory or restructure into separate locations

### Token Optimization Strategy

The `.claudeignore` file excludes certain paths, but for maximum optimization:
- Keep only 9 essential files in `.claude/rules/` (see APPLIED_SOLUTION.md for details)
- Move others to backup directory
- Load additional modules via explicit `@load:` directives when needed

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

*Version: 2.1.0 | Last updated: 2026-02-03*
