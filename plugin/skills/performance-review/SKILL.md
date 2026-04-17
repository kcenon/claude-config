---
name: performance-review
description: "Performance optimization analysis: CPU/memory profiling, caching strategies, database query optimization, connection pooling, concurrency patterns, memory leak detection, and throughput improvement. Use when code is slow, memory usage is high, latency needs reduction, or conducting performance reviews before release."
allowed-tools: Read, Grep, Glob
model: sonnet
context: fork
agent: Explore
argument-hint: "<file-or-directory>"
---

# Performance Review Skill

## When to Use

- Code performance optimization
- Memory leak fixes
- Throughput improvements
- Performance review requests
- Bottleneck analysis

## Performance Analysis Workflow

```
Profiling → Identify bottlenecks → Optimize → Verify
```

## Checklist

### Algorithm & Data Structures

- [ ] Time complexity analysis (Big-O)
- [ ] Appropriate data structure selection
- [ ] Remove unnecessary operations

### Memory

- [ ] Minimize memory allocation
- [ ] Object reuse (pooling)
- [ ] Cache-friendly access patterns

### Concurrency

- [ ] Minimize lock contention
- [ ] Leverage async I/O
- [ ] Thread pool optimization

### Caching

- [ ] Appropriate cache strategy
- [ ] Cache invalidation policy
- [ ] Cache hit rate monitoring

## Reference Documents (Import Syntax)
@./reference/performance.md
@./reference/memory.md
@./reference/concurrency.md
@./reference/monitoring.md

## Caution

> "Premature optimization is the root of all evil" - Donald Knuth
>
> Always confirm bottlenecks through profiling before optimizing.

## Output

This skill runs in a forked context (`context: fork`) using the read-only `Explore` agent. It does not have access to the calling conversation's history — operate entirely from the supplied `<file-or-directory>` argument.

Return a structured report at the end of analysis:

```markdown
## Performance Review Report

| Category | Findings |
|----------|----------|
| Critical (clear regression) | N items |
| High (measured hotspot) | N items |
| Medium (suspected hotspot) | N items |
| Low (style/maintainability) | N items |

### Critical Findings
1. `file.ext:line` — finding + recommended optimization + expected gain
2. ...

### Hotspot Map
- Algorithm/data-structure issues: N
- Memory issues: N
- Concurrency issues: N
- Caching opportunities: N

### Coverage
- Files inspected: N
- Profiling data referenced: yes/no
- Categories not evaluated (need runtime data): ...
```
