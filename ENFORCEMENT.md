# Enforcement Cheat Sheet

What gets blocked, by which layer, and how to unblock it. Read in five minutes. For the full hook catalog, see [HOOKS.md](HOOKS.md). For prerequisites, see [PREREQUISITES.md](PREREQUISITES.md).

## At-a-glance

| When you do this | Hook / Layer | What gets blocked | How to fix |
|------------------|-------------|-------------------|------------|
| `git commit -m "..."` | `commit-message-guard` (PreToolUse) + `commit-msg` git hook | Non-Conventional-Commits format, AI/Claude attribution, emojis | Rewrite to `type(scope): description`, drop attribution |
| `git push origin main` or `git push origin develop` | `hooks/pre-push` (git hook, terminal) | Direct push to protected branch | Open a PR instead; squash-merge |
| `git merge`, `git rebase`, `git cherry-pick`, `git pull` on dirty tree | `conflict-guard` (PreToolUse) | Operation blocked when working tree is dirty or another op is in progress | `git stash` or commit first |
| `gh pr create --base main` (head ≠ develop) | `pr-target-guard` (PreToolUse) + `validate-pr-target.yml` | PR blocked from non-develop branch to main | Target `develop` instead |
| `gh pr create --title "한글…"` (or any non-ASCII PR/issue text) | `pr-language-guard` (PreToolUse) | Non-English title/body in `gh pr|issue|release` | Rewrite in English |
| `gh pr create --body "Co-Authored-By: Claude"` (or `🤖 Claude`, "Generated with Claude") | `attribution-guard` (PreToolUse) | AI/Claude attribution in PR/issue/release artifacts | Remove the trailer/marker; write the change in your own voice |
| `gh pr merge <N>` while any check is pending/failing | `merge-gate-guard` (PreToolUse) | Merge blocked until every `gh pr checks <N>` bucket is `pass` or `skipping` | Wait for CI; fix failures; never rationalize |
| `gh pr merge` without `--squash` (where allowed) | `merge-gate-guard` + `gh-write-verb-guard` | Merge style enforcement | Use `--squash` |
| `gh api -X POST|PATCH|PUT|DELETE` to non-allowlisted endpoint, or GraphQL `mutation` | `gh-write-verb-guard` (PreToolUse) | Write-verb gh-api call without scoped allowlist | Use a smaller, scoped command; or open an issue to extend the allowlist |
| `cat .env`, `grep AWS_ ~/.aws/credentials` via Bash | `bash-sensitive-read-guard` (PreToolUse) | Read of `.env`, `.pem`, `.key`, `secrets/*`, `credentials/*` via Bash channel | Use a non-secret config; if you really need it, ask the user out-of-band |
| `cat > foo.py`, `tee`, `sed -i`, `python -c "open(...,'w')"` | `bash-write-guard` (PreToolUse) | Write to existing file via Bash channel | Use the `Edit` or `Write` tool |
| `Edit`/`Write` on a file you have not yet `Read` | `pre-edit-read-guard` (PreToolUse) | Edit denied with a "Read first" message | Call `Read` on the exact path, then retry |
| `TaskCreate` with a 10-character description and no checkbox | `task-created-validator` (TaskCreated) | Task creation blocked | Description ≥ 20 chars and at least one `- [ ]` |
| `TeamCreate` when `~/.claude/teams/` already has `MAX_TEAMS` (default 3) | `team-limit-guard` (PreToolUse) | Team creation blocked | Shut down an idle team first |
| `rm -rf /`, `chmod 777`, `curl … \| sh` | `dangerous-command-guard` (PreToolUse) | Catastrophic command blocked | Use a smaller, scoped command |
| Edit/Write/Read on `.env`, `.pem`, `.key`, `secrets/`, `credentials/` | `sensitive-file-guard` (PreToolUse) + `permissions.deny` | Tool call blocked | Do not exfiltrate secrets; reference variable names instead |
| Bumping `harness_policies.p4_strict_schema` before the P4 observation window | `p4-timeline-guard` (PreToolUse) | Setting flip blocked | Wait for the window; or set `CLAUDE_P4_OVERRIDE=1` with a documented reason |
| Auto-compaction discards core principles | `pre-compact-snapshot` + `post-compact-restore` (PreCompact / PostCompact) | Not blocking — re-injects principles into post-compact context | No action |
| Instruction load (CLAUDE.md ingest) | `instructions-loaded-reinforcer` (InstructionsLoaded) | Not blocking — re-asserts commit / branching / language policy | No action |
| Task or Agent tool returns dirty working tree | `post-task-checkpoint` (PostToolUse, async) | Not blocking — auto-commits `wip(agent): ...` checkpoint | No action; squash at PR merge |

## CI gates (server-side)

These run on GitHub Actions and gate the PR independently of the local hooks above:

| Workflow | What it checks | Blocking? |
|----------|----------------|-----------|
| `validate-hooks.yml` | `tests/hooks/test-runner.sh`, shellcheck on `global/hooks/*.sh` | Yes — fails the PR |
| `validate-hooks-doc.yml` | `HOOKS.md` matches `bash scripts/gen-hooks-md.sh --check` | Yes — fails the PR if hook headers and HOOKS.md drift |
| `validate-pr-target.yml` | Auto-closes PRs targeting `main` from non-`develop` branches | Yes — server-side close |
| `validate-skills.yml` | SKILL.md schema and frontmatter | Yes |
| `batch-drift-regression.yml` | Drift-benchmark regression for batch workflows | Yes |
| `post-release-develop-reset.yml` | Recreates `develop` from `main` after a release merge | Informational |

## Fail-policy quick reference

- **Fail-closed**: `pr-target-guard`, `commit-message-guard`, `pre-push`, `dangerous-command-guard`, `bash-sensitive-read-guard`, `bash-write-guard`, `pre-edit-read-guard`, `attribution-guard` (on extracted bodies).
- **Fail-open** (gate is best-effort; transient tooling failures should not block legit work): `merge-gate-guard`, `pr-language-guard` (on heredoc/file-based bodies), `task-created-validator` (on missing parser), `conflict-guard` (when `git` is missing).
- **Non-blocking** (informational / lifecycle): `session-logger`, `cleanup`, `version-check`, `subagent-logger`, `tool-failure-logger`, `pre-compact-snapshot`, `post-compact-restore`, `instructions-loaded-reinforcer`, `post-task-checkpoint`.

## Bypass

- `git commit --no-verify` bypasses the `commit-msg` git hook only — the `commit-message-guard` PreToolUse hook still gates Claude's tool calls.
- `git push --no-verify` bypasses `pre-push` — forbidden by project policy.
- `CLAUDE_P4_OVERRIDE=1` bypasses `p4-timeline-guard` — requires a documented reason.
- `GH_WRITE_VERB_GUARD_AUDIT_ONLY=1` downgrades all `deny` decisions to `allow` (telemetry-only mode for rollout).

## See also

- [HOOKS.md › Auto-Generated Hook Catalog](HOOKS.md#auto-generated-hook-catalog) — full list, regenerated from script headers.
- [PREREQUISITES.md](PREREQUISITES.md) — install commands per OS.
- [docs/branching-strategy.md](docs/branching-strategy.md) — branch model and CI policy in detail.
- [global/commit-settings.md](global/commit-settings.md) — attribution and language policy.
