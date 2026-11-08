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

- Coverage gate: at least 80% code coverage, measured with the ecosystem's tool (lcov, pytest-cov, JaCoCo); CI fails the build when coverage drops below it. Critical business logic needs 100%.

> Full rules, read on demand when a task centres on testing (test levels, fixtures, what to cover, edge cases, naming, independence): `.claude/reference/project-management/testing.md`. Examples: `.claude/reference/project-management/testing-examples.md`.
