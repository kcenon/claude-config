---
alwaysApply: false
paths: ["**/*.cpp", "**/*.cc", "**/*.h", "**/*.hpp", "**/*.py", "**/*.js", "**/*.ts", "**/*.tsx", "**/*.jsx", "**/*.java", "**/*.kt", "**/*.go"]
---

# Exception and Error Handling

**YOU MUST** apply these principles consistently, supplementing them with language-specific error handling patterns.

## General Principles

### Anticipate and Handle Errors

Use appropriate mechanisms to signal and handle errors:

- **Exceptions**: For exceptional, recoverable errors (C++, Java, Python, Kotlin)
- **Result types**: For expected error conditions (Rust, modern C++)
- **Error codes**: For performance-critical or C-compatible code
- **Null safety**: Language built-in null handling (Kotlin, TypeScript)

### Language-Specific Patterns

- **C++**: exceptions for exceptional cases, `std::optional` for expected "no value", `std::expected` (C++23) for expected errors
- **Kotlin**: exceptions for exceptional cases, nullable types for "no value", `Result` for expected errors
- **Python**: exceptions (the idiomatic approach), `Optional` for "no value"

## Resource Management

### Ensure Cleanup

**YOU MUST** release resources (files, connections, memory) when no longer needed:
RAII in C++, context managers (`with`) in Python, `use {}` in Kotlin.

### Custom Resource Management

Create RAII wrappers or context managers for custom resources; delete copying and
allow moving so ownership stays unique.

## Input Validation

> **Scope**: Validation as part of error handling flow.
> For comprehensive security-focused validation (injection prevention, XSS, path traversal), see [`security.md`](../security.md).

### Validate Early

**ALWAYS** validate all external input at the boundary of your system, before any processing.

### Validation Checklist

- [ ] **Type checking**: Verify data types match expectations
- [ ] **Range checking**: Ensure numeric values are within valid ranges
- [ ] **Format validation**: Check strings match expected patterns (email, URL, etc.)
- [ ] **Size limits**: Enforce maximum sizes for collections and strings
- [ ] **Business rules**: Validate domain-specific constraints

### Security Implications

Proper input validation prevents:

- **Injection attacks**: SQL injection, command injection, XSS
- **Buffer overflows**: In languages like C/C++
- **Resource exhaustion**: Via excessively large inputs
- **Logic errors**: From unexpected data formats

## Error Handling Patterns

### Try-Catch Best Practices

Catch the most specific exception first and recover from it; log unexpected
exceptions with their type and message; keep a last-resort catch-all only to log
and fail safely.

### Don't Swallow Exceptions

**NEVER** use empty catch blocks. Silent failures are prohibited. Log, then retry,
fall back, or re-throw.

### Error Context Propagation

> **Scope**: Error wrapping and re-throw patterns.
> For structured logging standards (JSON, correlation IDs), see [`api/observability.md`](../api/observability.md).

**IMPORTANT**: Include sufficient context when propagating errors (what was being
processed, with which input) by wrapping the original error before re-throwing.

## Error Recovery Strategies

- **Retry with backoff**: for transient errors, retry a bounded number of times with exponential delay, then give up
- **Fallback mechanisms**: provide alternative functionality (e.g. a cache) when the primary source fails
- **Circuit breaker**: after a threshold of consecutive failures, stop calling the failing dependency to prevent cascading failures

> Examples: see `.claude/reference/coding/error-handling-examples.md`
