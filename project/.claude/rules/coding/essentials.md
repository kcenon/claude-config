---
alwaysApply: false
paths: ["**/*.cpp", "**/*.cc", "**/*.h", "**/*.hpp", "**/*.py", "**/*.js", "**/*.ts", "**/*.tsx", "**/*.jsx", "**/*.java", "**/*.kt", "**/*.go", "**/*.rs", "**/*.c", "**/auth/**", "**/security/**"]
---

# Coding Essentials

Short form of the coding, error-handling, performance, safety and security rules. Follow the project's established patterns and the language's official style guide.

## Code Quality

- Names state purpose: nouns for classes, verbs for functions, meaningful names for variables and constants, in the language's usual casing.
- File order: imports, constants and types, main implementation, helpers.
- One responsibility per class or function; a name that needs "and" means split it. Functions typically run 20-50 lines.
- Reduce nesting with early returns; extract helpers for compound conditions. Name constants instead of magic numbers.
- Prefer immutable data (`const`, `val`, `Final`).
- Document public APIs: purpose, parameters, return value, errors. Comments explain why, not what, and stay current.
- Readability first; use the language's formatter.

## Complete Implementation

- List every tier, variant and enum value before coding, then implement all of them. Partial implementations are not acceptable.
- No `TODO`, `FIXME`, `NotImplementedError`, or empty or placeholder returns in production code.
- Use exhaustive switches or matches, or a complete handler map that rejects unknown keys.
- Handle each tier's edge cases and give every tier dedicated, passing tests.

## Errors and Validation

- Use the language's mechanism: exceptions for exceptional cases, optional or result types for expected ones, error codes where performance or C compatibility requires.
- Release every resource (files, connections, memory) through RAII, `with` or `use {}`; wrappers for custom resources are movable, not copyable.
- Validate all external input at the system boundary before processing: type, range, format, size, business rules.
- Catch the most specific exception first. Never leave a catch block empty: log, then retry, fall back or re-throw. A catch-all only logs and fails safely.
- Wrap errors with context (what was processed, with which input) before re-throwing, and log caught errors with that context.
- Recover with bounded retries and exponential backoff for transient errors, a fallback when a primary source fails, and a circuit breaker for a dependency that keeps failing.

## Performance

- Never optimize without profiling: write correct code, measure, optimize the measured hot path, measure again, run the tests.
- Look first at algorithmic complexity, allocations in loops, data locality, unbuffered or synchronous I/O, lock contention, and N+1 queries or missing indexes.
- Pre-allocate, avoid needless copies, pick data structures for the access pattern, and buffer or batch I/O.
- Benchmark critical operations and give them time-budget tests so slowdowns fail CI.

## Memory and Concurrency

- Own resources through RAII and smart pointers (`unique_ptr`, `shared_ptr`, `weak_ptr`), not raw pointers; borrow with references. Prefer the stack, and document non-obvious lifetimes so no reference outlives its object.
- Guard shared mutable state with a mutex, or atomics for simple counters, so no data race occurs.
- Choose the model by workload: threads for CPU-bound shared-memory work, coroutines or async/await for I/O-bound work, processes for isolation or true parallelism.
- Prevent deadlocks: one lock order everywhere, timed or try-locks, lock hierarchies.
- Test concurrent code with stress tests and race detectors; check native memory with sanitizers.

## Security

- Never trust external input: validate type, length, format and range on the server with allowlists, and sanitize before use.
- Parameterized queries only; no shell execution with user input; escape HTML output and never put user input in `innerHTML`; keep resolved paths inside the intended base directory.
- Use established authentication libraries, proper session management and multi-factor support. Hash passwords with a per-user salt and a slow KDF (argon2, bcrypt); compare hashes, never plaintext.
- Least privilege: drop elevated privileges early, check authorization at every layer (RBAC), and never expose internal IDs without validation.
- Never hard-code credentials; load them from the environment or an untracked config file. Never log secrets; mask sensitive fields.
- Encrypt data at rest and in transit with proper key management. Use anti-CSRF tokens, SameSite cookies, Origin checks and CSP headers.
- Secure defaults (insecure options are explicit opt-in) and rate limiting on external endpoints.
- Pin dependency versions, commit lock files, and scan dependencies regularly and in CI.

> Full rules, read on demand when a task centres on one topic: `.claude/reference/coding/standards.md`, `implementation-standards.md`, `error-handling.md`, `performance.md` and `safety.md` in the same folder, and `.claude/reference/security.md`. Examples: `.claude/reference/coding/*-examples.md` and `.claude/reference/security-examples.md`.
