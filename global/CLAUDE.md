# Claude Code Global Configuration

Global settings applied every session. Routing index only — procedural detail lives in the linked files. Project `CLAUDE.md` overrides this file; project rules auto-load via YAML frontmatter (`alwaysApply`, `paths`).

## Core Settings

@./commit-settings.md
@./conversation-language.md

## Always-on Invariants

- 3-fail rule: stop and propose alternatives after 3 identical failures
- CI gate: task is NOT complete while any `gh pr checks` entry is failing, pending, or incomplete
- Protected branches: never direct-push to `main` or `develop`; PR + squash merge only
- Read-before-Edit: Read any file before Edit/Write
- Conflicts: never auto-resolve source code; `git merge --abort` if intractable

## Routing

- **Sandbox, TLS, `gh` caveat**: `docs/SANDBOX_TLS.md`
- **Branching strategy**: `docs/branching-strategy.md`
- **Lifecycle skills**: `global/skills/issue-work`, `pr-work`, `release`, `branch-cleanup`
- **Build verification**: `global/skills/pr-work/reference/build-verification.md`
- **Skill authoring**: `global/skills/_policy.md`, `global/skills/_shared/invariants.md`

## Updating

Edit the linked files and restart the session.

---

*Version: 3.2.0 | Last updated: 2026-04-23*
