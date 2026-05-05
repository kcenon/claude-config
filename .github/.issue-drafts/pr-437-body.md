Closes #437

## What

Rewrite `global/CLAUDE.md` as a routing-only index with a small always-on invariants block. Body shrinks from 70 lines to 27 (excluding version footer); duplicated procedural content now lives only in its existing dedicated file.

## Verification table (removed paragraph -> target)

| Removed section | Where the content already lives |
|-----------------|--------------------------------|
| Environment Workarounds: sandbox TLS, `gh` macOS caveat, dangerouslyDisableSandbox fallback | `docs/SANDBOX_TLS.md` (full matrix and platform fallback ladder) |
| `gh CLI Sandbox Policy` (entire section) | `docs/SANDBOX_TLS.md` §gh Caveat |
| `GitHub / CI`: CI polling, merge-gate, label pre-check, completion definition | `global/skills/pr-work/SKILL.md` §9 (Monitor CI), §10 (Squash Merge), `global/skills/issue-create/SKILL.md` |
| `Build & Test`: toolchain policy, incremental validation, batch error collection | `global/skills/pr-work/reference/build-verification.md` |
| `Standard Workflows`: issue-to-PR lifecycle, branching strategy, epic closure, multi-agent WIP commit, multi-repo parallel, auto-restart | `global/skills/issue-work`, `global/skills/pr-work`, `global/skills/release`, `global/skills/branch-cleanup`, `global/skills/issue-work/reference/batch-mode.md`, `docs/branching-strategy.md` |
| Merge-conflict procedure (3 bullets) | Compressed into a one-line always-on invariant ("Conflicts: never auto-resolve source code; `git merge --abort` if intractable") — no dedicated global target exists; the full procedure is kept in `project/.claude/rules/workflow/git-conflict-resolution.md` for deployed projects |
| "Read-before-Edit" tool-contract note | Kept as an always-on invariant (governs every Edit/Write) |
| `Configuration Updates` (3 lines) | Replaced with the single-line `## Updating` section |

## Acceptance criteria

- [x] Body ≤ 30 lines (measured: 27 lines excluding `---` and version footer)
- [x] Always-on invariants block ≤ 12 lines (measured: 7 lines including heading and blank line)
- [x] Every removed paragraph has a verified equivalent elsewhere (table above)
- [x] No dropped information: merge conflicts become a one-line invariant, the rest points to existing files

## Token impact

- File size: 7,230 -> 1,087 bytes (-85%)
- Line count: 70 -> 31 (-56%)
- Every session pays this cost on startup, so the saving is per-session.

## Non-goals verified

- `project/CLAUDE.md` (55 lines, already routing-only) untouched
- `enterprise/CLAUDE.md` (5 lines) untouched
- No rule file moved or renamed; only the index entry points were trimmed

## Related

- Part of #439 (harness-optimization epic)
- Companion phase-2 work tracked in #438
