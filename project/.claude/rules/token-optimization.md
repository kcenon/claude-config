# Token Optimization

> **Purpose**: Minimize token usage through selective rule loading
> **Mechanism**: YAML frontmatter (`alwaysApply` and `paths`) in each rule file

## How Rule Loading Works

Claude Code loads rules from `.claude/rules/` based on **YAML frontmatter** in each file:

### Always Loaded (`alwaysApply: true`)

Rules that load every session:

- `core/environment.md` — Timezone, locale, current info
- `core/communication.md` — Code/documentation language standards
- `core/problem-solving.md` — Systematic problem resolution
- `core/behavioral-guardrails.md` — LLM anti-patterns
- `core/common-commands.md` — Frequently used commands
- `workflow/workflow.md` — Master workflow index
- `workflow/question-handling.md` — Question processing procedure
- `workflow/problem-solving.md` — Problem-solving principles
- `workflow/git-commit-format.md` — Commit message standards
- `workflow/github-issue-5w1h.md` — Issue creation guidelines
- `workflow/github-pr-5w1h.md` — PR creation guidelines
- `tools/gh-cli-scripts.md` — GitHub CLI script reference
- `conditional-loading.md` — Loading rules documentation
- `token-optimization.md` — This file

### Path-Based Loading (`paths` patterns)

Rules that load only when editing matching files:

| Category | Loaded When Editing | Examples |
|----------|-------------------|----------|
| `coding/*.md` | Source code files | `**/*.ts`, `**/*.py`, `**/*.cpp` |
| `api/*.md` | API-related files | `src/api/**/*`, `**/*.controller.ts` |
| `operations/*.md` | Scripts, build files | `scripts/**/*`, `Makefile`, `*.yml` |

### Excluded by Default

Files in `.claudeignore` are excluded from context to save tokens:

- Reference documents (`rules/*/reference/`) — Load with `@load:` directive
- Design documents (`docs/design/`) — Conceptual architecture, not implemented
- Commands/skills definitions — Load when invoked
- Session memory, plugin cache, backups

## Optimization Strategies

- Set `alwaysApply: false` for specialized rules
- Use specific `paths` patterns to minimize unnecessary loading
- Keep rule files concise
- Move detailed reference material to `reference/` subdirectories
- Use `.claudeignore` to exclude large or rarely-needed files

## Design Documents

The following are **conceptual design documents** describing aspirational architectures.
They are **not implemented** by Claude Code:

- `docs/design/intelligent-prefetching.md` — Predictive loading concept
- `docs/design/module-caching.md` — Cache tier concept
- `docs/design/module-priority.md` — Priority loading concept

---

*Accurate documentation of Claude Code's YAML frontmatter-based rule loading*
