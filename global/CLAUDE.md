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
- **Lifecycle skills**: `global/skills/_internal/issue-work`, `pr-work`, `release`, `branch-cleanup`
- **Build verification**: `global/skills/_internal/pr-work/reference/build-verification.md`
- **Skill authoring**: `global/skills/_policy.md`, `global/skills/_internal/_shared/invariants.md`
- **Skill aliases**: see "Skill Aliases" section below

## Skill Aliases (post-D2 relocation, see #491, #492)

When the user types one of the keywords below as a leading command (with or without arguments, with or without a leading `/`), treat it as an explicit invocation of the corresponding `SKILL.md` under `~/.claude/skills/_internal/`. Read the SKILL.md, parse arguments per its `argument-hint`, and execute its body honoring `halt_conditions` and `max_iterations`. Do not ask for confirmation; the keyword is the invocation. This preserves `disable-model-invocation: true` semantics because the user's keyword is an explicit user invocation, not autonomous model triggering.

| Keyword                | Skill path                                                  |
|------------------------|-------------------------------------------------------------|
| `issue-work`           | `~/.claude/skills/_internal/issue-work/SKILL.md`            |
| `pr-work`              | `~/.claude/skills/_internal/pr-work/SKILL.md`               |
| `release`              | `~/.claude/skills/_internal/release/SKILL.md`               |
| `branch-cleanup`       | `~/.claude/skills/_internal/branch-cleanup/SKILL.md`        |
| `ci-fix`               | `~/.claude/skills/_internal/ci-fix/SKILL.md`                |
| `harness`              | `~/.claude/skills/_internal/harness/SKILL.md`               |
| `research`             | `~/.claude/skills/_internal/research/SKILL.md`              |
| `doc-review`           | `~/.claude/skills/_internal/doc-review/SKILL.md`            |
| `doc-index`            | `~/.claude/skills/_internal/doc-index/SKILL.md`             |
| `preflight`            | `~/.claude/skills/_internal/preflight/SKILL.md`             |
| `issue-create`         | `~/.claude/skills/_internal/issue-create/SKILL.md`          |
| `implement-all-levels` | `~/.claude/skills/_internal/implement-all-levels/SKILL.md`  |
| `fleet-orchestrator`   | `~/.claude/skills/_internal/fleet-orchestrator/SKILL.md`    |

Ambiguity rule: if a keyword appears mid-sentence (not as a leading command) or inside quotes, ask whether the user meant the skill or a literal mention before invoking.

## Updating

Edit the linked files and restart the session.

---

*Version: 3.3.0 | Last updated: 2026-04-27*
