---
paths:
  - "**/scripts/**"
  - "Makefile"
  - "**/CMakeLists.txt"
  - "**/monitoring/**"
  - "**/metrics/**"
  - "**/observability/**"
  - "**/*.prometheus.*"
  - "**/*.grafana.*"
alwaysApply: false
---

# Operations: Cleanup & Monitoring

- When code deviates from the guidelines, say why in a `// DEVIATION:` comment next to it, with a `TODO` that names what would remove the need:

  ```cpp
  // DEVIATION: Using raw pointer because legacy C library requires it.
  // TODO: Wrap in RAII class after migrating to library v2.0
  ```

> Full rules, read on demand when a task centres on cleanup or monitoring (temporary files, `.gitignore`, formatters and linters, pre-commit hooks, metric targets and samples): `.claude/reference/operations/ops.md`.
