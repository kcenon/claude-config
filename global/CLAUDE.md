# Claude Code Global Configuration

Global settings for all Claude Code sessions. Project-specific `CLAUDE.md` files override these.

## Core Settings

@./commit-settings.md

## Priority Rules

1. **Project overrides global** — Project `CLAUDE.md` takes precedence
2. **YAML frontmatter** — Rules load based on `alwaysApply` and `paths`

> Core principles, environment, and communication rules load automatically via project rule frontmatter (`alwaysApply: true`).

## GitHub / CI

- When `gh` CLI fails with TLS certificate errors in sandbox mode, retry with `dangerouslyDisableSandbox`. Do not assume authentication failure — TLS errors and auth errors are different.
- After creating a PR, monitor CI until **all** checks reach `completed` status. Do NOT merge while any check is `queued` or `in_progress`.
- Poll CI status at 30-second intervals. Max 10 minutes per run. Never use `gh run watch`.
- If the 10-minute polling limit is reached with CI still running: stop polling, report current status to the user, and **do NOT merge**. The user decides next steps.
- **Before merge, always use `gh pr checks <PR_NUMBER>` to verify ALL individual check statuses.** Do NOT rely on `gh run list` alone — it shows workflow-level status which can report "success" while individual sub-checks (e.g., platform-specific test jobs) are still failing.
- **Any CI failure — including test timeouts — must be investigated and fixed before merging.** Never treat a failing check as "flaky" or ignorable. If a test times out, adjust the test workload, increase the timeout, or fix the underlying performance issue before proceeding with merge.
- When creating GitHub issues, verify labels exist on the target repository before using them. Run `gh label list -R <repo>` first to avoid creation failures from invalid labels.
- After completing issue work or PR creation, always verify CI status before considering the task done. If CI is still pending, note it explicitly in the task summary rather than marking the task as completed.

## Build & Test

- When a required toolchain (Go, Rust, CMake, npm) is not installed locally, skip local build verification and rely on CI. Do not attempt to install toolchains without asking the user first.
- Validate incrementally: build and test after each logical change, not after all changes are complete. This catches errors early and reduces first-CI-run failures.
- After large refactoring or migration, run a full build, collect ALL errors, and fix them in one batch before rebuilding. Do not fix one error at a time.
- If the same approach fails 3 consecutive times, stop and propose alternative strategies to the user.

## Standard Workflows

- **Issue-to-PR lifecycle**: implement → local build/test → create PR → monitor CI → squash merge → close issue → close epic if all sub-issues done.
- Skip lengthy planning phases. Start implementation immediately, analyzing code as you go.
- After merging, check if parent epic should be closed.
- When using multi-agent teams, always commit work-in-progress before switching contexts or spawning new agents that modify the working directory. This prevents data loss from agent overwrites.
- When working on multi-repo tasks, use parallel agents (one per repo) rather than processing sequentially. Each agent should independently implement, test, and create PRs.
- When `git merge` or `git rebase` produces conflicts, never auto-resolve source code files. Present conflicting hunks to the user. Auto-generated files (lockfiles, build manifests) may be resolved by re-running generators (`npm install`, `go mod tidy`).
- After resolving conflicts, verify no conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) remain before committing.
- If a merge conflict appears intractable, prefer `git merge --abort` and ask the user for direction rather than producing a broken merge.

## Configuration Updates

Edit module files, then restart session to apply changes.

---

*Version: 3.0.0 | Last updated: 2026-04-10*
