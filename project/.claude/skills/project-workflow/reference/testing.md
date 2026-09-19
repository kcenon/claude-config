---
alwaysApply: false
paths:
  - "**/*.test.ts"
  - "**/*.test.tsx"
  - "**/*.test.js"
  - "**/*.spec.ts"
  - "**/*.spec.js"
  - "**/test_*.py"
  - "**/*_test.py"
  - "**/*_test.go"
  - "**/tests/**"
  - "**/test/**"
  - "**/__tests__/**"
---

# Testing Strategy

## Layered Testing

Implement multiple levels of testing for comprehensive coverage (the testing pyramid):

- **Unit tests (many)**: fast, cheap, foundational; test individual functions or classes in isolation
- **Integration tests (some)**: medium speed/cost; test interactions between components (e.g. against a disposable test database)
- **End-to-end tests (few)**: slow, expensive, high confidence
- **Performance tests**: verify performance requirements with a benchmark harness (Google Benchmark, `timeit`, ...)

## Test Fixtures

Manage test setup and cleanup efficiently with the framework's fixture mechanism
(GoogleTest `SetUp`/`TearDown`, pytest fixtures, JUnit `@BeforeEach`/`@AfterEach`).

## Coverage Goals

### Target: 80% Code Coverage

Aim for at least **80% test coverage** across the codebase, measured with the
ecosystem's tool (lcov, pytest-cov, JaCoCo).

### What to Cover

Priority for test coverage:

1. **Critical business logic** - 100% coverage required
2. **Public APIs** - All public functions/methods
3. **Error handling paths** - Exception cases
4. **Edge cases** - Boundary conditions
5. **Integration points** - External dependencies

What **not** to test extensively:

- Trivial getters/setters
- Framework/library code
- Generated code
- Simple data classes (unless they have logic)

## Edge Cases and Failure Scenarios

- **Edge cases**: empty input, very long input, special characters, Unicode, embedded null characters
- **Failure scenarios**: missing files, insufficient permissions, disk full, network timeouts (use mocks to provoke them)
- **Parameterized tests**: drive one test body over a table of inputs instead of copy-pasting cases

## Test Organization

### File Structure

Keep tests under `tests/` split by level (`unit/`, `integration/`, `performance/`),
mirroring the source module names.

### Naming Conventions

- **Test files**: `test_<module>.cpp`, `<Module>Test.kt`, `test_<module>.py`
- **Test cases**: Descriptive names that explain what's being tested
  - Good: `TEST(UserManager, AddingDuplicateUserReturnsFalse)`
  - Bad: `TEST(UserManager, Test1)`

### Test Independence

Each test should be independent: no shared mutable global state, and no test may
depend on another test having run first.

## Continuous Integration

- Run the full test suite on every push and pull request
- **Quality gates**: fail the build when coverage drops below the 80% threshold

> Examples: see `.claude/reference/project-management/testing-examples.md`
