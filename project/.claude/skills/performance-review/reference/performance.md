---
paths: ["**/*.cpp", "**/*.cc", "**/*.h", "**/*.hpp", "**/*.py", "**/*.js", "**/*.ts", "**/*.java", "**/*.kt", "**/*.go", "**/*.rs"]
alwaysApply: false
---

# Performance Optimization

## Profile Before Optimizing

**Never optimize without profiling first.** Premature optimization wastes time and often makes code harder to maintain.

### The Optimization Workflow

1. **Write correct code first** - Get it working
2. **Measure performance** - Identify actual bottlenecks
3. **Optimize hot paths** - Focus on measured problems
4. **Verify improvement** - Measure again to confirm
5. **Ensure correctness** - Run tests to verify no regressions

### Profiling Tools

- **C++**: `perf` (Linux), Instruments (macOS), Valgrind callgrind
- **Python**: `cProfile` + `pstats`, `line_profiler`
- **Kotlin/Java**: JFR (Java Flight Recorder), JProfiler, YourKit, VisualVM

## Identify Bottlenecks

### Common Performance Issues

1. **Algorithmic complexity** - O(n²) where O(n log n) possible
2. **Excessive allocations** - Creating temporary objects in loops
3. **Cache misses** - Poor data locality
4. **I/O bottlenecks** - Unbuffered or synchronous I/O
5. **Lock contention** - Over-synchronization in concurrent code
6. **Database queries** - N+1 query problem, missing indexes

### Performance Hotspots

Focus on code that:
- Appears high in profiler output
- Runs frequently (inner loops)
- Processes large amounts of data
- Performs I/O operations

## Reduce Overhead

- **Minimize allocations**: pre-allocate (`reserve`) or transform in place instead of growing containers inside loops
- **Avoid unnecessary copies**: pass large objects by `const&`, return by move, transfer ownership with `std::unique_ptr`
- **Efficient algorithms**: replace nested-loop O(n²) scans with hash-based O(n) lookups

### Efficient Data Structures

Choose the right data structure for the access pattern:

| Operation | Vector/Array | List | Hash Map | Tree Map |
|-----------|--------------|------|----------|----------|
| Random access | O(1) | O(n) | O(1) avg | O(log n) |
| Insert at end | O(1) amortized | O(1) | O(1) avg | O(log n) |
| Insert at beginning | O(n) | O(1) | N/A | N/A |
| Search | O(n) | O(n) | O(1) avg | O(log n) |
| Ordered iteration | ✓ | ✓ | ✗ | ✓ |

## Cache Optimization

- **Data locality**: prefer contiguous arrays of objects over arrays of pointers for sequential processing
- **Structure packing**: order struct members from largest to smallest alignment to minimize padding

## I/O Optimization

- **Buffered I/O**: batch many small writes into one
- **Asynchronous I/O**: overlap I/O with other work (`std::async`, async/await)

## Compiler Optimizations

- Build releases with `-O3 -DNDEBUG`; consider `-flto` and `-march=native` where the deployment target allows
- Help the compiler: `inline` small hot functions, mark non-throwing functions `noexcept`, use `const`, add branch hints on hot paths

## Performance Testing

- **Benchmarking**: Google Benchmark (C++), `timeit` (Python)
- **Regression tests**: assert that critical operations finish within a fixed time budget so slowdowns fail CI

> Examples: see `.claude/reference/coding/performance-examples.md`
