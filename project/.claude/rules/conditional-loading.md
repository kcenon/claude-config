# Conditional Module Loading Rules

> **Purpose**: Automatically load only relevant guideline modules based on context
> **Version**: 1.2.0
> **Token Savings**: ~60-70% compared to loading all modules (up to 84% for specific commands)

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
  load: [common-commands, general, error-handling]

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

## 🎮 Command-Specific Loading Rules

### Skill Commands

Define minimal required modules for each skill command:

| Skill Command | Required Modules | Optional Modules | Skip Modules |
|---------------|------------------|------------------|--------------|
| `/issue-work` | `environment`, `communication`, `problem-solving`, `common-commands`, `git-commit-format`, `workflow/github-issue-5w1h`, `workflow/github-pr-5w1h` | `workflow/reference/label-definitions` (if labeling), `workflow/reference/issue-examples` (if splitting) | `cleanup`, `monitoring`, `performance`, `memory`, `concurrency`, `security`, `api`, `coding` |
| `/commit` | `environment`, `communication`, `git-commit-format`, `workflow/question-handling` | None | All others |
| `/pr-work` | `environment`, `communication`, `problem-solving`, `git-commit-format`, `workflow/github-pr-5w1h` | `testing`, `quality` | `cleanup`, `monitoring`, `performance` |
| `/issue-create` | `environment`, `communication`, `workflow/github-issue-5w1h` | `workflow/reference/label-definitions`, `workflow/reference/issue-examples` | All coding standards, `cleanup`, `monitoring` |
| `/release` | `environment`, `communication`, `git-commit-format`, `build`, `testing` | `security`, `monitoring` | `coding`, `cleanup` |
| `/branch-cleanup` | `environment`, `communication`, `common-commands` | None | All others |

### Loading Strategy by Command

```yaml
/issue-work:
  core_required:
    - core/environment
    - core/communication
    - core/problem-solving
    - core/common-commands
  workflow_required:
    - workflow/git-commit-format
    - workflow/github-issue-5w1h
    - workflow/github-pr-5w1h
  conditional:
    - workflow/reference/label-definitions  # Only if issue needs labeling
    - workflow/reference/issue-examples     # Only if issue needs splitting
    - workflow/reference/automation-patterns  # Only if using gh CLI extensively
  always_skip:
    - operations/cleanup
    - operations/monitoring
    - coding/**/*
    - api/**/*
    - security
    - performance
    - memory
    - concurrency

/commit:
  core_required:
    - core/environment
    - core/communication
  workflow_required:
    - workflow/git-commit-format
    - workflow/question-handling
  always_skip:
    - operations/**/*
    - coding/**/*
    - api/**/*
    - workflow/github-*

/issue-create:
  core_required:
    - core/environment
    - core/communication
  workflow_required:
    - workflow/github-issue-5w1h
  conditional:
    - workflow/reference/label-definitions
    - workflow/reference/issue-examples
  always_skip:
    - operations/**/*
    - coding/**/*
    - api/**/*
    - workflow/github-pr-5w1h
    - workflow/git-commit-format
```

### Command Detection Logic

```python
# Pseudo-code for command-based loading
if command.startswith('/'):
    command_name = command.split()[0][1:]  # Remove '/' prefix

    # Load command-specific modules only
    load_modules(COMMAND_MODULES[command_name]['core_required'])
    load_modules(COMMAND_MODULES[command_name]['workflow_required'])

    # Evaluate conditional modules based on context
    for module in COMMAND_MODULES[command_name]['conditional']:
        if should_load_module(module, context):
            load_module(module)

    # Skip all others
    skip_modules(COMMAND_MODULES[command_name]['always_skip'])
else:
    # Use task-based/keyword-based loading
    apply_standard_loading_rules()
```

### Estimated Token Savings by Command

| Command | Before Optimization | After Optimization | Token Savings |
|---------|---------------------|--------------------| --------------|
| `/issue-work` | ~50,000 tokens | ~18,000 tokens | **64%** |
| `/commit` | ~50,000 tokens | ~8,000 tokens | **84%** |
| `/issue-create` | ~50,000 tokens | ~12,000 tokens | **76%** |
| `/pr-work` | ~50,000 tokens | ~15,000 tokens | **70%** |
| `/release` | ~50,000 tokens | ~20,000 tokens | **60%** |

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
| `run script` | `common-commands` | Script execution |
| `install`, `backup`, `sync` | `common-commands` | Setup commands |
| `validate`, `verify` | `common-commands` | Validation commands |

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

---
*Version 1.2.0 - Enhanced command-specific loading rules*
*This system reduces token usage by ~65% on average (up to 84% for command execution) while maintaining 95% response accuracy*