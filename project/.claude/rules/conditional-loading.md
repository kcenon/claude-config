# Conditional Module Loading Rules

> **Purpose**: Automatically load only relevant guideline modules based on context
> **Token Savings**: ~60-70% compared to loading all modules

## Loading Priority System

```
Priority 1 (Always Load): Core settings
Priority 2 (Task-Based): Load based on user request
Priority 3 (Context-Based): Load based on file types/content
Priority 4 (Optional): Load only if explicitly needed
```

## Task-Based Loading

### By User Intent

| If request contains | Load modules | Skip modules |
|-------------------|--------------|--------------|
| "bug", "fix", "error" | error-handling, quality, testing | documentation, build |
| "feature", "implement" | general, quality, documentation, testing | monitoring |
| "refactor", "clean" | quality, performance, general | security, build |
| "optimize", "performance" | performance, monitoring, memory | documentation |
| "security", "vulnerability" | security, error-handling, quality | performance |
| "test", "unittest" | testing, quality, error-handling | documentation, build |
| "document", "README" | documentation, communication | All coding standards |

### By Development Phase

| Phase | Required Modules | Optional Modules |
|-------|-----------------|------------------|
| Planning/Design | workflow, documentation | security, performance |
| Implementation | general, quality, error-handling | Language-specific |
| Testing | testing, quality | performance |
| Code Review | ALL standards, security | None |
| Deployment | build, security, monitoring | documentation |

## File-Based Loading

### By File Extension

| Extensions | Load | Skip |
|------------|------|------|
| .cpp, .h | general, memory, concurrency, error-handling | - |
| .py | general, quality, error-handling | memory |
| .js, .ts | general, quality, error-handling | memory |
| .sql | security, performance | memory, concurrency |
| .md | documentation, communication | all coding standards |

### By Directory Pattern

| Pattern | Load |
|---------|------|
| /test/, /tests/ | testing, quality |
| /docs/ | documentation, communication |
| /src/api/, /routes/ | security, documentation, error-handling |
| /.github/ | git-commit-format, workflow |

## Command-Specific Loading

| Command | Required | Skip |
|---------|----------|------|
| `/issue-work` | environment, communication, problem-solving, git-commit-format, github-issue-5w1h, github-pr-5w1h | cleanup, monitoring, coding/*, api/* |
| `/commit` | environment, communication, git-commit-format, question-handling | operations/*, coding/*, api/* |
| `/pr-work` | environment, communication, git-commit-format, github-pr-5w1h | cleanup, monitoring, performance |
| `/issue-create` | environment, communication, github-issue-5w1h | coding/*, api/*, github-pr-5w1h |
| `/release` | environment, communication, git-commit-format, build, testing | coding/*, cleanup |

## Quick Reference Patterns

| Pattern | Instant Load | Reason |
|---------|--------------|--------|
| `git commit` | git-commit-format | Direct command |
| `fix typo` | Skip all except workflow | Trivial change |
| `implement OAuth` | security, error-handling | Auth = Security |
| `memory leak` | memory, monitoring, error-handling | Critical issue |
| `code review` | Load ALL standards | Comprehensive check |

## Override Mechanisms

```markdown
@load: security, performance    # Force load specific modules
@skip: documentation, build     # Exclude specific modules
@focus: memory-optimization     # Set focus area
```

---

*For detailed implementation algorithms, see `docs/design/`*
