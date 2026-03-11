# Claude Code Global Configuration

Global settings for all Claude Code sessions. Project-specific `CLAUDE.md` files override these.

## Core Settings

@./commit-settings.md

## Priority Rules

1. **Project overrides global** — Project `CLAUDE.md` takes precedence
2. **YAML frontmatter** — Rules load based on `alwaysApply` and `paths`

## GitHub / CI

- When `gh` CLI fails with TLS certificate errors in sandbox mode, retry with `dangerouslyDisableSandbox`. Do not assume authentication failure — TLS errors and auth errors are different.
- After creating a PR, monitor CI until **all** checks reach `completed` status. Do NOT merge while any check is `queued` or `in_progress`.
- Poll CI status at 30-second intervals. Max 10 minutes per run. Never use `gh run watch`.
- If the 10-minute polling limit is reached with CI still running: stop polling, report current status to the user, and **do NOT merge**. The user decides next steps.

## Build & Test

- When a required toolchain (Go, Rust, CMake, npm) is not installed locally, skip local build verification and rely on CI. Do not attempt to install toolchains without asking the user first.
- Validate incrementally: build and test after each logical change, not after all changes are complete. This catches errors early and reduces first-CI-run failures.

## Standard Workflows

- **Issue-to-PR lifecycle**: implement → local build/test → create PR → monitor CI → squash merge → close issue → close epic if all sub-issues done.
- Skip lengthy planning phases. Start implementation immediately, analyzing code as you go.
- After merging, check if parent epic should be closed.

## Session Management

- When a multi-step workflow is interrupted, write progress state to `.claude/resume.md` in the project directory so the next session can resume seamlessly.
- At session start, check for `.claude/resume.md` and offer to resume if it exists.

## Configuration Updates

Edit module files, then restart session to apply changes.

---

*Version: 2.2.0 | Last updated: 2026-03-11*
