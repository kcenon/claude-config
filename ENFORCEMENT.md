# Enforcement Cheat Sheet

What gets blocked, by which layer, and how to unblock it. Read in five minutes. For the full hook catalog, see [HOOKS.md](HOOKS.md). For prerequisites, see [PREREQUISITES.md](PREREQUISITES.md).

Since #964 the Claude Code hooks guard destructive operations only: they **deny** an operation that is irreversible and reaches beyond the working tree or shared state, **ask** before one that is irreversible but local or that rewrites or deletes a shared ref, and **allow** everything recoverable. Policy rules (commit format, content language, attribution, branch naming, read-before-edit) are instructions in `global/CLAUDE.md` and `global/commit-settings.md`, or native controls; see the [Hook Policy](HOOKS.md#hook-policy) section of HOOKS.md.

## At-a-glance

| When you do this | Hook / Layer | What happens | How to fix |
|------------------|-------------|--------------|------------|
| `rm -rf /`, `rm -rf ~`, `rm -r /abs/path`, `curl ... \| sh`, `chmod 777`, `gh repo delete` | `dangerous-command-guard` (PreToolUse) | Denied: irreversible and reaches beyond the working tree | Use a smaller, scoped command |
| `git push origin main`, `git push origin develop`, or a bare `git push` whose upstream is `main`/`master`/`develop` | `dangerous-command-guard` (PreToolUse) + `hooks/pre-push` (git hook, terminal) | Denied: direct push to a protected branch | Open a PR from a work branch; squash-merge |
| `git reset --hard`, `git checkout -- <path>`, `git restore <path>` with uncommitted changes; `git clean -f`; `git stash drop` / `clear` | `dangerous-command-guard` (PreToolUse) | Permission prompt (`ask`) | Confirm, or commit / stash first |
| `git push --force` (not `--force-with-lease`), `git push --delete <ref>`, `git push origin :<ref>` | `dangerous-command-guard` (PreToolUse) | Permission prompt (`ask`) | Confirm, or use `--force-with-lease` |
| `rm -r` of `.`, `..`, `*`, `.git` or a path outside the repository; `find ... -delete` / `-exec rm` | `dangerous-command-guard` (PreToolUse) | Permission prompt (`ask`) | Confirm, or narrow the path |
| `gh release delete`, `gh issue delete`, any other `gh api -X DELETE` | `dangerous-command-guard` (PreToolUse) | Permission prompt (`ask`) | Confirm |
| `bash -c '<command>'`, `sh -c ...`, `eval '<command>'`, `$SHELL -c ...`, `"$BASH" -c ...` | `dangerous-command-guard` (payload scan) | The inner command gets the same decision; a payload that cannot be inspected is denied | Run the inner command directly |
| `$X -c '<command>'`, `$(which bash) -c ...`, `$(echo rm) -rf ~`: a command name that cannot be resolved | `dangerous-command-guard` (unresolved head) | Permission prompt (`ask`) when the arguments would be refused for `rm` or for a shell | Confirm, or spell out the command |
| `gh pr merge <N>` while any check is pending/failing | `merge-gate-guard` (PreToolUse) | Merge blocked until every `gh pr checks <N>` bucket is `pass` or `skipping` | Wait for CI; fix failures; never rationalize |
| Read, Edit or Write on `.env`, `.pem`, `.key`, `secrets/`, `credentials/`, SSH keys, AWS credentials under the working directory, or on `~/.aws/credentials` | `permissions.deny` `Read(...)` rules (a `Read` deny also blocks Edit/Write on the path) | Tool call denied | Do not exfiltrate secrets; reference variable names instead |
| `cat .env`, `grep AWS_ ~/.aws/credentials` via Bash | Bash sandbox read-deny of the same files (macOS, Linux; see [Secrets outside the working directory](#secrets-outside-the-working-directory)); `bash-sensitive-read-guard` in the Windows Bash dispatcher | Read denied | Use a non-secret config; if you really need it, ask the user out-of-band |
| `echo $API_KEY`, `printenv GITHUB_TOKEN` via Bash on Windows | `shell-env-secret-guard` in the Windows Bash dispatcher | Denied (a bare `env` dump only warns) | Reference the variable name, not its value |
| `Edit`/`Write` on a file you have not yet `Read` | Native Edit/Write tool contract | Tool error | Call `Read` on the exact path, then retry |
| Edit/Write under `~/.claude/memory-shared/memories/` | `memory-write-guard` (PreToolUse) | Denied when the structure, secret or owner check fails | Fix the memory file; see `docs/MEMORY_VALIDATION_SPEC.md` |
| `git commit -m "..."` in a repository with the git hooks installed | `commit-msg` git hook | Non-Conventional-Commits format, AI/Claude attribution, emojis | Rewrite to `type(scope): description`, drop attribution |
| `gh pr create --base main` (head is neither `develop` nor `release/*`) | `validate-pr-target.yml` (server-side) | PR auto-closed with a comment | Target `develop` instead |

## Not checked by a hook

Issue #964 removed the hooks that enforced these rules. They stay as instructions, and the layer in the right-hand column is what remains:

| Rule | Remaining layer |
|------|-----------------|
| Conventional Commits, no attribution, no emojis in commits | `commit-msg` git hook; `settings.json` `attribution: ""` |
| PR / issue / release text follows `CLAUDE_CONTENT_LANGUAGE` and carries no attribution | `global/commit-settings.md` instruction; the skills resolve the policy before they write |
| PRs into `main` come from `develop` or `release/*` | `validate-pr-target.yml` (server-side) |
| Merge method | Repository merge settings |
| No `git merge` / `rebase` / `pull` on a dirty tree or during another operation | git itself refuses most of these |
| Shell writes go through Edit/Write | Bash sandbox write allowlist (macOS, Linux); `global/CLAUDE.md` |
| No secret-bearing environment variable printed to the transcript (macOS, Linux) | None; the sandbox read-deny covers files, not the environment |
| Team and task limits | None; Claude Code allows one team per session |

## Secrets outside the working directory

The `**/` patterns in `permissions.deny` are relative to the working directory, and so is the Bash sandbox read-deny that Claude Code builds from them. They deny a matching file at any depth under the directory the session runs in, and nowhere else.

- `~/.aws/credentials` has its own home-anchored rule, `Read(~/.aws/credentials)` (#973), so it is denied from every working directory.
- **Known gap on macOS and Linux: SSH private keys in `~/.ssh`.** No rule denies them. From another project directory, the Read tool asks before it reads `~/.ssh/id_ed25519` (the file is outside the working directory), and the sandbox does not deny a Bash read of it. Before #964, `bash-sensitive-read-guard.sh` denied such reads anywhere.
- The gap is deliberate. The sandbox blocks the `ssh-agent` socket, so a sandboxed `git commit` signed with an SSH key, as [docs/SSH_COMMIT_SIGNING.md](docs/SSH_COMMIT_SIGNING.md) sets up, reads the private key file directly. A `Read(~/.ssh/...)` deny would make every sandboxed signed commit fail.
- On Windows, `bash-sensitive-read-guard.ps1` matches `.ssh/id_*` in the command wherever the file is, so the gap does not apply there.

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

- **Fail-closed**: `dangerous-command-guard` (unparseable input, or a `bash -c` / `eval` payload it cannot inspect), `pre-push`, and on Windows `bash-sensitive-read-guard` and `shell-env-secret-guard`.
- **Fail-open** (gate is best-effort; transient tooling failures should not block legit work): `merge-gate-guard` (on `gh` errors), `memory-write-guard` (on its own internal failure, #521).
- **Non-blocking** (informational / lifecycle): `cleanup`, `prune-permission-rules`, `memory-integrity-check`, `memory-access-logger`, `permission-denial-logger`, `worktree-remove`.

## Bypass

- No Claude Code hook denies `--no-verify` since #964. `git commit --no-verify` skips the `commit-msg` git hook and `git push --no-verify` skips `pre-push`; GitHub branch protection and CI remain the server-side gate.
- `dangerous-command-guard` still denies a direct push to `main`/`master`/`develop`, with or without `--no-verify`, whether the target is explicit or resolved from the upstream. `git push -n`/`--dry-run` is allowed; it performs no real push.

## See also

- [HOOKS.md › Auto-Generated Hook Catalog](HOOKS.md#auto-generated-hook-catalog) — full list, regenerated from script headers.
- [PREREQUISITES.md](PREREQUISITES.md) — install commands per OS.
- [docs/branching-strategy.md](docs/branching-strategy.md) — branch model and CI policy in detail.
- [global/commit-settings.md](global/commit-settings.md) — attribution and language policy.
