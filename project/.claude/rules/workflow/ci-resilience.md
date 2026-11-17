---
paths:
  - "**/.github/workflows/*.yml"
  - "**/.github/workflows/*.yaml"
  - "**/Makefile"
  - "**/CMakeLists.txt"
  - "**/go.mod"
  - "**/Cargo.toml"
  - "**/package.json"
alwaysApply: false
---

# CI Resilience Patterns

- Do NOT merge while any check is `queued` or `in_progress`, even if the completed checks passed. Wait as `~/.claude/skills/_internal/pr-work/reference/build-verification.md` describes: one `gh pr checks <n> --repo <owner/repo> --watch --interval 30 --fail-fast` call, never a loop or `sleep`. If CI is still running 10 minutes after the push, report the status and let the user decide.
- Investigate and fix every CI failure, timeouts included, before merging; never treat a failing check as flaky, unrelated or ignorable. Diagnose before retrying, at most 3 attempts.
- Do NOT install a missing toolchain without asking: skip that local check, rely on CI, and report what was verified locally and what only CI verifies.

> Full rules, read on demand when a task centres on CI friction (TLS and sandbox errors, congested runners, toolchain checks, first-run failures, waiting for CI): `.claude/reference/workflow/ci-resilience.md`.
