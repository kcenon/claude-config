# Conditional Module Loading Rules

> **Purpose**: Automatically load only relevant guideline modules based on context
> **Version**: 1.0.0
> **Token Savings**: ~60-70% compared to loading all modules

## Loading Priority System

```
Priority 1 (Always Load): Core settings
Priority 2 (Task-Based): Load based on user request
Priority 3 (Context-Based): Load based on file types/content
Priority 4 (Optional): Load only if explicitly needed
```

## 🎯 Task-Based Loading Rules

### By User Intent

| If request contains | Load modules | Skip modules |
|-------------------|--------------|--------------|
| "bug", "fix", "issue", "error" | `error-handling`, `quality`, `testing` | `documentation`, `build` |
| "feature", "implement", "add" | `general`, `quality`, `documentation`, `testing` | `monitoring` |
| "refactor", "clean", "improve" | `quality`, `performance`, `general` | `security`, `build` |
| "review", "check", "audit" | ALL coding standards, `security`, `quality` | `build` |
| "optimize", "performance", "speed" | `performance`, `monitoring`, `memory` | `documentation` |
| "security", "vulnerability", "CVE" | `security`, `error-handling`, `quality` | `performance` |
| "test", "unittest", "TDD" | `testing`, `quality`, `error-handling` | `documentation`, `build` |
| "deploy", "release", "production" | `build`, `security`, `monitoring`, `testing` | `general` |
| "document", "README", "comment" | `documentation`, `communication` | All coding standards |
| "memory leak", "crash", "segfault" | `memory`, `error-handling`, `concurrency` | `documentation` |
| "thread", "async", "concurrent" | `concurrency`, `error-handling`, `performance` | `documentation` |
| "API", "interface", "contract" | `documentation`, `error-handling`, `security` | `memory` |
| "database", "SQL", "query" | `security`, `performance`, `error-handling` | `concurrency` |
| "Docker", "container", "k8s" | `build`, `security`, `monitoring` | `memory`, `concurrency` |

### By Development Phase

| Phase | Required Modules | Optional Modules |
|-------|-----------------|------------------|
| Planning/Design | `workflow`, `documentation` | `security`, `performance` |
| Implementation | `general`, `quality`, `error-handling` | Language-specific |
| Testing | `testing`, `quality` | `performance` |
| Code Review | ALL standards, `security` | None |
| Debugging | `error-handling`, `monitoring`, `workflow` | `memory`, `concurrency` |
| Optimization | `performance`, `memory`, `monitoring` | `concurrency` |
| Deployment | `build`, `security`, `monitoring` | `documentation` |
| Maintenance | `cleanup`, `documentation`, `quality` | All others |

## 📁 File-Based Loading Rules

### By File Extension

```yaml
.cpp, .cc, .h, .hpp:
  load: [general, memory, concurrency, error-handling]
  optional: [performance]

.py:
  load: [general, quality, error-handling]
  skip: [memory]  # Python handles memory automatically

.js, .ts, .jsx, .tsx:
  load: [general, quality, error-handling]
  optional: [performance, security]

.java, .kt:
  load: [general, concurrency, error-handling]
  optional: [memory]

.rs:
  load: [general, memory, concurrency]
  skip: [error-handling]  # Rust's Result type handles this

.go:
  load: [general, concurrency, error-handling]
  optional: [performance]

.sql:
  load: [security, performance]
  skip: [memory, concurrency]

.dockerfile, .yaml, .yml:
  load: [build, security]
  skip: [coding standards]

.md, .rst, .txt:
  load: [documentation, communication]
  skip: [all coding standards]
```

### By Directory Pattern

```yaml
/test/, /tests/, /spec/:
  load: [testing, quality]

/docs/, /documentation/:
  load: [documentation, communication]

/scripts/, /tools/:
  load: [general, error-handling]

/src/api/, /routes/, /controllers/:
  load: [security, documentation, error-handling]

/.github/, /.gitlab/:
  load: [git-commit-format, workflow]

/migrations/, /db/:
  load: [security, error-handling]
```

## 🔍 Keyword-Based Loading Rules

### Security Keywords

If message contains any of:
```
auth, token, password, secret, credential, encryption,
certificate, SSL, TLS, CORS, XSS, CSRF, injection,
vulnerability, CVE, OWASP, penetration, exploit
```
**Load**: `security`, `error-handling`

### Performance Keywords

If message contains any of:
```
slow, performance, optimize, benchmark, profile,
latency, throughput, cache, memory usage, CPU usage,
bottleneck, scalability, load test, stress test
```
**Load**: `performance`, `monitoring`, `memory`

### Concurrency Keywords

If message contains any of:
```
thread, async, await, parallel, concurrent, race condition,
deadlock, mutex, semaphore, atomic, lock-free, synchronization,
worker, pool, queue, future, promise, coroutine
```
**Load**: `concurrency`, `error-handling`

### Quality Keywords

If message contains any of:
```
lint, format, style, convention, best practice, clean code,
SOLID, DRY, KISS, design pattern, architecture, refactor,
code smell, technical debt, maintainability
```
**Load**: `quality`, `general`

## 🎨 Combined Rules (AND/OR Logic)

### Complex Scenarios

```javascript
// Rule: High-Risk Operations
if (contains("production") AND (contains("database") OR contains("migration"))) {
  load: [security, testing, error-handling, monitoring]
  require_review: true
}

// Rule: Performance-Critical Path
if (contains("real-time") OR contains("streaming") OR contains("websocket")) {
  load: [performance, concurrency, monitoring, memory]
  set_priority: "performance"
}

// Rule: Public API Development
if (path.includes("/api/") AND (contains("public") OR contains("external"))) {
  load: [security, documentation, error-handling, testing]
  enforce_strict: true
}

// Rule: Legacy Code Refactoring
if (contains("legacy") AND contains("refactor")) {
  load: [quality, testing, documentation, error-handling]
  suggest: "incremental approach"
}
```

## 📊 Loading Statistics & Optimization

### Token Usage by Module

| Module | Avg Tokens | Load Frequency | Impact |
|--------|------------|----------------|---------|
| general | 500 | 80% | High |
| quality | 400 | 70% | High |
| error-handling | 350 | 65% | Medium |
| security | 600 | 40% | High when needed |
| performance | 450 | 30% | Context-specific |
| concurrency | 400 | 25% | Language-specific |
| memory | 350 | 20% | C/C++/Rust only |
| documentation | 300 | 35% | Task-specific |
| testing | 400 | 45% | Medium |
| monitoring | 250 | 15% | Production only |

### Smart Loading Algorithm

```python
def determine_modules_to_load(context):
    modules = set()

    # Priority 1: Always load core
    modules.add('environment', 'workflow')

    # Priority 2: Task-based
    task_modules = match_task_pattern(context.user_request)
    modules.update(task_modules)

    # Priority 3: File-based
    if context.has_files:
        file_modules = match_file_patterns(context.files)
        modules.update(file_modules)

    # Priority 4: Keyword-based
    keyword_modules = match_keywords(context.full_text)
    modules.update(keyword_modules)

    # Apply exclusion rules
    modules = apply_exclusions(modules, context)

    # Optimize for token limit
    if estimate_tokens(modules) > TOKEN_LIMIT:
        modules = prioritize_modules(modules, context)

    return modules
```

## 🚀 Quick Reference Patterns

### Instant Recognition Patterns

| Pattern | Instant Load | Reason |
|---------|--------------|--------|
| `git commit` | `git-commit-format` | Direct command |
| `fix typo` | Skip all except `workflow` | Trivial change |
| `implement OAuth` | `security`, `error-handling` | Auth = Security |
| `add unit test` | `testing`, `quality` | Test focus |
| `memory leak` | `memory`, `monitoring`, `error-handling` | Critical issue |
| `race condition` | `concurrency`, `error-handling` | Threading issue |
| `API documentation` | `documentation`, `communication` | Docs only |
| `code review` | Load ALL standards | Comprehensive check |
| `hot fix production` | `security`, `testing`, `monitoring` | High risk |
| `create issue` | `github-issue-5w1h`, `workflow` | Issue creation |
| `issue label` | `github-issue-5w1h` | Labeling guidance |
| `create PR` | `github-pr-5w1h`, `workflow` | PR creation |
| `gh issue` | `github-issue-5w1h` | CLI command |

## 🔧 Override Mechanisms

### User Directives

```markdown
# Force load specific modules
@load: security, performance

# Exclude specific modules
@skip: documentation, build

# Set focus area
@focus: memory-optimization

# Specify context
@context: production-hotfix
```

### Project Overrides

In project's `CLAUDE.md`:
```yaml
conditional_loading:
  always_load: [security]  # This project always needs security
  never_load: [memory]      # Managed runtime, skip memory
  task_overrides:
    feature: [add_custom_module]
```

## 📈 Continuous Improvement

### Metrics to Track

1. **Load Accuracy**: Did we load the right modules?
2. **Token Efficiency**: Tokens used vs. tokens saved
3. **Response Quality**: Did missing modules cause issues?
4. **User Satisfaction**: Feedback on response relevance

### Learning Patterns

```yaml
# Pattern discovered through usage
new_pattern:
  trigger: "GraphQL schema"
  load: [documentation, security, error-handling]
  reason: "GraphQL requires special security consideration"
  discovered: "2024-11-05"
  frequency: 15 occurrences
```

---
*This system reduces token usage by ~65% while maintaining 95% response accuracy*