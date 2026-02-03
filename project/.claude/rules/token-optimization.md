# Token Optimization Rules

> **Purpose**: Minimize token usage through intelligent module loading
> **Token Savings**: 60-70% reduction in initial context loading

## Module Loading Priority

Load modules based on priority level:

| Level | When to Load | Examples |
|-------|--------------|----------|
| **0: Critical** | Always | `core/environment.md`, `core/communication.md` |
| **1: Essential** | On command detection | `workflow/git-commit-format.md`, `workflow/github-*.md` |
| **2: Contextual** | On intent analysis | `coding/*.md`, `security.md` |
| **3: Reference** | On explicit need | `workflow/reference/*.md` |
| **4: Archive** | Via `@load:` only | `operations/cleanup.md`, `documentation.md` |

## Cache Tiers

Modules are cached by access frequency:

| Tier | Criteria | Behavior |
|------|----------|----------|
| **HOT** | >80% access rate | Never evicted, always in memory |
| **WARM** | 20-80% access rate | LRU eviction, 1-hour TTL |
| **COLD** | <20% access rate | Load fresh each time |

### HOT Modules (Always Cached)

- `core/environment.md`
- `core/communication.md`
- `workflow/question-handling.md`
- `workflow/git-commit-format.md`

## Command-Specific Loading

| Command | Required Modules | Skip Modules |
|---------|------------------|--------------|
| `/commit` | git-commit-format, question-handling | coding/*, api/*, operations/* |
| `/issue-work` | github-issue-5w1h, github-pr-5w1h, git-commit-format | api/*, operations/monitoring |
| `/issue-create` | github-issue-5w1h | coding/*, api/*, github-pr-5w1h |
| `/pr-work` | github-pr-5w1h, git-commit-format | operations/*, api/* |
| `/release` | git-commit-format, build, testing | coding/*, cleanup |

## Keyword-Based Loading

| Keywords | Load Modules |
|----------|--------------|
| bug, fix, error | error-handling, quality, testing |
| feature, implement | general, quality, testing |
| optimize, performance | performance, monitoring, memory |
| security, auth, token | security, error-handling |
| thread, async, concurrent | concurrency, error-handling |

## User Overrides

```markdown
@load: security, performance    # Force load specific modules
@skip: documentation, build     # Exclude specific modules
@focus: memory-optimization     # Set focus area
```

## Design Documentation

For implementation details, algorithms, and architecture:
- See `docs/design/intelligent-prefetching.md`
- See `docs/design/module-caching.md`
- See `docs/design/module-priority.md`

---

*Concise rules extracted from detailed design documents*
