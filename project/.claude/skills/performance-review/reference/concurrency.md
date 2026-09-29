---
paths: ["**/*.cpp", "**/*.cc", "**/*.h", "**/*.hpp", "**/*.c", "**/*.rs", "**/*.java", "**/*.kt", "**/*.go", "**/*.py"]
alwaysApply: false
---

# Memory & Concurrency Safety

> Merged from: `memory.md` + `concurrency.md`

## Memory Management

### Smart Pointers (C++)

Always prefer smart pointers over raw pointers for ownership: `std::unique_ptr` for
unique ownership, `std::shared_ptr` for shared ownership, `std::weak_ptr` for
non-owning references.

### RAII Prevents Leaks

Acquire resources in constructors and release them in destructors so early returns
and exceptions cannot leak.

### Ownership Semantics

Make ownership explicit: transfer with `std::unique_ptr` (by value / `std::move`),
borrow with a raw pointer or reference.

### Lifetime Guidelines

1. Prefer stack allocation over heap when possible
2. Use smart pointers instead of raw pointers for ownership
3. Document lifetime in comments when non-obvious
4. Avoid dangling references by ensuring objects outlive references

### Memory Safety Tools

AddressSanitizer (`-fsanitize=address`), MemorySanitizer (`-fsanitize=memory`),
Valgrind (`--leak-check=full --track-origins=yes`).

---

## Concurrency

### Avoiding Data Races

Data races occur when multiple threads access the same memory, at least one writes,
and there's no synchronization. Guard shared state with a mutex (`std::lock_guard`)
or use `std::atomic` for simple counters.

### Choosing Concurrency Model

| Model | Use When | Languages |
|-------|----------|-----------|
| **Threading** | CPU-bound parallel work, shared memory | C++, Java, Kotlin |
| **Coroutines** | I/O-bound, lightweight concurrency | Kotlin, Python |
| **Async/Await** | I/O-bound, responsive UIs | TypeScript, Python |
| **Process-based** | True CPU parallelism, isolation | Python (GIL bypass) |

### Common Patterns

- **Producer-consumer**: a mutex-protected queue with a condition variable
- **Read-write lock**: `std::shared_mutex` with `shared_lock` for readers and `unique_lock` for writers

### Deadlock Prevention

1. **Lock Ordering**: Always acquire locks in the same order
2. **Timeout**: Use timed locks and retry on timeout
3. **Try-Lock**: Use non-blocking lock attempts
4. **Lock Hierarchy**: Assign levels and only acquire higher levels

### Testing Concurrent Code

- **Stress testing**: Run many threads doing concurrent operations, verify final state
- **ThreadSanitizer**: `g++ -fsanitize=thread` detects race conditions at runtime
- **Deterministic testing**: Use controlled scheduling where possible

> Examples: see `.claude/reference/coding/safety-examples.md`
