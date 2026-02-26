---
paths:
  - ".git/**"
  - "**/*"
alwaysApply: true
---

# Git Commit Message Format

Use **Conventional Commits**: `type(scope): description`

## Types

feat, fix, docs, style, refactor, perf, test, build, ci, chore

## Rules

- **Scope**: Optional but recommended, lowercase (e.g., `auth`, `network`, `ui`)
- **Description**: English, imperative mood, lowercase start, no period, ≤50 chars
- **Body**: Optional. Explain what/why, wrap at 72 chars, blank line after description
- **Footer**: `BREAKING CHANGE: ...` or `Closes #123`

## Attribution Policy

No AI/Claude attribution or emojis in commit messages. See global `commit-settings.md`.

> For hook scripts and CI verification, see `reference/commit-hooks.md`.
