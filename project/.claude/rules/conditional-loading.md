---
alwaysApply: true
---

# Conditional Module Loading

Rules in `.claude/rules/` use YAML frontmatter for automatic path-specific loading.

## How It Works

Each rule file specifies when it should apply using YAML frontmatter:

### Path-Based Loading

```yaml
---
paths:
  - "src/api/**/*.ts"
  - "**/*.controller.ts"
---
```

Rules with `paths` are automatically loaded when editing matching files.

### Always Apply

```yaml
---
alwaysApply: true
---
```

Rules with `alwaysApply: true` are loaded for every conversation.

### Optional Loading

```yaml
---
paths: ["**/*.cpp", "**/*.rs"]
alwaysApply: false
---
```

Rules with `alwaysApply: false` only load when paths match.

## Supported Glob Patterns

| Pattern | Matches |
|---------|---------|
| `**/*.ts` | All TypeScript files |
| `src/**/*` | All files under src/ |
| `*.md` | Markdown files in root |
| `**/*.{ts,tsx}` | Multiple extensions |
| `**/test/**` | Files in any test directory |

## Rule Loading by Category

| Category | Loading Behavior |
|----------|------------------|
| `core/*` | Always apply (essential settings) |
| `workflow/*` | Always apply (basic workflow) |
| `coding/*` | Path-based (source code files) |
| `api/*` | Path-based (API-related files) |
| `operations/*` | Path-based (scripts, build files) |
| `workflow/reference/*` | Path-based (.github files) |

## Manual Override

Use `@load:` directive to force load specific modules:

```markdown
@load: security, performance
@skip: documentation, build
```

---

*For detailed loading algorithms, see `docs/design/`*
