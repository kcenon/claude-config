# Claude Code Global Configuration

Global settings applied every session. Routing index only — procedural detail lives in the linked files. Project `CLAUDE.md` overrides this file; project rules auto-load via YAML frontmatter (`alwaysApply`, `paths`).

## Core Settings

@./commit-settings.md
@./conversation-language.md

## Always-on Invariants

- 3-fail rule: stop and propose alternatives after 3 identical failures
- CI gate: task is NOT complete while any `gh pr checks` entry is failing, pending, or incomplete
- Protected branches: never direct-push to `main` or `develop`; PR + squash merge only
- Conflicts: never auto-resolve source code; `git merge --abort` if intractable
- Command length: keep each Bash/PowerShell call short enough to parse (target <~900 bytes); extract longer logic to a `.ps1`/`.sh` file and invoke by path
- `gh` calls: `gh` runs outside the sandbox through `sandbox.excludedCommands`, which matches only when the whole call is `gh`; keep one `gh` command per Bash call (shape output with `--jq`, pass `--repo owner/name` literally, wait with `gh pr checks --watch` or `gh run watch`), never pipe, chain, or loop it, and never set `dangerouslyDisableSandbox` for it

## Routing

- **Build verification**: `~/.claude/skills/_internal/pr-work/reference/build-verification.md`
- **Skill authoring**: `~/.claude/skills/_policy.md`, `~/.claude/skills/_internal/_shared/invariants.md`
- **Repository documents** (in the claude-config repository, not installed):
  - Sandbox, TLS, `gh` caveat: `docs/SANDBOX_TLS.md`
  - Branching strategy: `docs/branching-strategy.md`
  - SSH commit signing (claude-memory): `docs/SSH_COMMIT_SIGNING.md`
  - Memory sync: `docs/MEMORY_SYNC.md` (operations), `docs/THREAT_MODEL.md`, `docs/MEMORY_MIGRATION.md` (migration)

## Skill Aliases

When the user types one of the keywords below as a leading command (with or without arguments, with or without a leading `/`), treat it as an explicit invocation of `~/.claude/skills/_internal/<keyword>/SKILL.md`. Read the SKILL.md, parse arguments per its `argument-hint`, and execute its body honoring `halt_conditions` and `max_iterations`. Do not ask for confirmation; the keyword is the invocation. This preserves `disable-model-invocation: true` semantics because the user's keyword is an explicit user invocation, not autonomous model triggering.

- Keywords: `issue-work`, `pr-work`, `release`, `branch-cleanup`, `ci-fix`, `sonar-fix`, `harness`, `research`, `doc-review`, `doc-index`, `preflight`, `issue-create`, `implement-all-levels`, `fleet-orchestrator`, `traceability`, `evidence-pack`, `risk-control`, `soup-inventory`, `memory-review`

Ambiguity rule: if a keyword appears mid-sentence (not as a leading command) or inside quotes, ask whether the user meant the skill or a literal mention before invoking.

---

*Version: 3.3.0 | Last updated: 2026-04-27*
