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
| Read, Edit or Write on `.env`, `.pem`, `.key`, `secrets/`, `credentials/`, SSH keys, AWS credentials under the working directory, or on a home credential file with [its own rule](#secrets-outside-the-working-directory) | `permissions.deny` `Read(...)` rules (a `Read` deny also blocks Edit/Write on the path) | Tool call denied | Do not exfiltrate secrets; reference variable names instead |
| `cat .env`, `grep AWS_ ~/.aws/credentials`, `cat ~/.netrc` via Bash | Bash sandbox read-deny of the same files (macOS, Linux; see [Secrets outside the working directory](#secrets-outside-the-working-directory)); `bash-sensitive-read-guard` in the Windows Bash dispatcher | Read denied | Use a non-secret config; if you really need it, ask the user out-of-band |
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

A credential file in the home directory therefore needs its own `Read(~/...)` rule, which denies it from every working directory. That rule also becomes a sandbox read-deny, and a sandbox deny stops the tool itself, not only a `cat` of the file. The `bash-sensitive-read-guard.sh` that #964 removed matched the command text, so it never had this cost. That is why each file has its own decision (#973, #982).

In the table, "Run" marks a cost observed with `sandbox-exec` on fake files under a temporary `HOME`. "Reasoned" marks one argued from how the tool works, because the tool was not installed on the macOS machine that checked these rules or the case cannot occur there.

| File | Decision | Cost |
|------|----------|------|
| `~/.aws/credentials`, `~/.aws/sso/cache/`, `~/.aws/cli/cache/` | Denied | None known: `sandbox.network.allowedDomains` lists no AWS endpoint, so a sandboxed `aws` has no working flow to lose. Reasoned. |
| `~/.netrc` | Denied | A sandboxed tool loses netrc authentication. Public access still works; private access fails with an auth error. Retry unsandboxed, or use a credential helper. Run. |
| `~/.pypirc` | Denied | Only upload tools read it; `pip install` does not. A sandboxed upload tool loses the stored credentials; retry it unsandboxed. Reasoned. |
| `~/.docker/config.json` | Denied | `docker *` is in `sandbox.excludedCommands`, so a `docker` alone in a call is unaffected. A sandboxed compound call still runs, with a warning that it cannot load the file. Run. |
| `~/.kube/config` | Denied | None known: no cluster endpoint is allow-listed, and no documented workflow uses the file. Reasoned. |
| `~/.gnupg/` | Denied | None known: this repository documents [SSH signing](docs/SSH_COMMIT_SIGNING.md) only. GnuPG 2.1+ does every secret-key operation in `gpg-agent` over a Unix socket, and the sandbox blocks agent sockets (verified for `ssh-agent`), so a sandboxed `gpg` cannot sign today. Reasoned: this is not a live test, because `gpg` was not installed. |
| `~/.config/gh/hosts.yml` | Denied | `gh *` is in `sandbox.excludedCommands`, so a `gh` alone in a call is unaffected. A `gh` in a compound call, or in a helper script such as `scripts/gh/*.sh`, stays sandboxed: on macOS it already fails on TLS ([gh Caveat](docs/SANDBOX_TLS.md#gh-caveat)), on Linux it now loses the token too. `git` with `gh auth setup-git` is in the same position. Both fail loudly and can be retried unsandboxed. Reasoned. |
| `~/.npmrc` | Readable on purpose | npm reads it for the registry and for auth. A deny makes npm silently use the public registry, so a private-registry user would resolve packages from the wrong source with no error. Run. Because sandboxed Bash can read the file, keep tokens out of it: `//registry.npmjs.org/:_authToken=${NPM_TOKEN}`. |
| `~/.ssh` private keys | Readable on purpose | The sandbox blocks the `ssh-agent` socket, so a sandboxed `git commit` signed with an SSH key, as [docs/SSH_COMMIT_SIGNING.md](docs/SSH_COMMIT_SIGNING.md) sets up, reads the private key file directly. A `Read(~/.ssh/...)` deny would make every sandboxed signed commit fail. |

For a file that is readable on purpose, from another project directory the Read tool asks before it reads the file (it is outside the working directory), and the sandbox does not deny a Bash read of it. Before #964, `bash-sensitive-read-guard.sh` denied such reads anywhere.

Windows has no OS sandbox. The `Read(~/...)` rules cover the Read tool, and the Bash channel relies on `bash-sensitive-read-guard.ps1`, which matches these files in the command text wherever they are, `.npmrc` and `.ssh/id_*` included. A text match does not stop a tool that reads its own config, so the costs above do not apply there. `gh` keeps its file in `%AppData%\GitHub CLI\hosts.yml` on Windows, outside the `~/` rule: the guard matches that path, and the Read tool asks before it reads the file.

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
