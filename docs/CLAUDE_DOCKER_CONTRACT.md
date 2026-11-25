# Claude-Docker Integration Contract

This document formalizes the contract between **claude-config** (the producer of `~/.claude/` configuration) and **claude-docker** (a consumer that bind-mounts that tree into Linux containers). Both projects depend on this contract; either side breaking an invariant without a coordinated update produces silent runtime failures.

## Scope

- claude-config writes to `~/.claude/` on the host via its installer or bootstrap script.
- claude-docker mounts `~/.claude/` read-only at `/home/node/.claude-host/` inside each container and creates per-account symlinks/copies under `/home/node/.claude/`.
- This document describes the state as of claude-config v1.10. Claude-docker is expected to track the same major version line.

## Invariants

### 1. Directory Structure Spec

After a full install (`scripts/install.{sh,ps1}` with the global or all profile, or `bootstrap.{sh,ps1}`), the following subtree under `~/.claude/` is guaranteed to exist:

```
~/.claude/
├── CLAUDE.md
├── commit-settings.md
├── .claudeignore
├── .full-suite-active        (optional probe — see invariant #4)
├── settings.json
├── hooks/
│   ├── *.sh                  (paired with .ps1 — see invariant #3)
│   ├── *.ps1
│   └── lib/
├── scripts/
│   ├── *.{sh,ps1}            (also paired)
│   ├── memory-sync.sh        (Unix installers only, unpaired — see invariant #3)
│   ├── memory-status.sh      (Unix installers only, unpaired)
│   ├── memory-notify.sh      (Unix installers only, unpaired)
│   └── memory/
│       └── *.sh              (memory validators; Unix installers only, unpaired)
├── skills/
│   ├── _internal/
│   ├── _shared/              (optional)
│   └── _policy.md
├── commands/
│   └── _policy.md
└── ccstatusline/
    └── settings.json
```

claude-docker's entrypoint mirrors this exact layout into the container. Adding a new top-level entry under `~/.claude/` on the claude-config side without a coordinated entrypoint update will **not** be visible inside the container.

### 2. Hook Command Grammar

`settings.json` hook commands MUST conform to one of these patterns to survive the container's pwsh-to-bash rewrite (`claude-docker/scripts/entrypoint.sh:50-61`):

- **Supported (rewrites cleanly)**: `pwsh.exe -NoProfile [-ExecutionPolicy <X>] -File <path>.ps1 [args...]`
- **Supported by passthrough**: command is already bash-native (`bash <path>.sh`, `~/.claude/hooks/<name>.sh`, `. ~/.claude/hooks/<name>.sh`)
- **Not supported (silent failure)**: heredoc / multi-line `-Command`, `$env:VAR` expansion, quoted paths with spaces, `Join-Path` outside the `statusLine` slot

If a new hook needs syntax outside the supported subset, the corresponding bash variant MUST do the equivalent work via shell-native means. The rewriter is best-effort, not a backstop.

### 3. Dual-Variant Pairing

Every script in `~/.claude/hooks/` and `~/.claude/scripts/` MUST exist as a `.sh` + `.ps1` pair with semantically equivalent behavior, except the Unix-only memory sync scripts described at the end of this section. The container ignores `.ps1`; PowerShell sessions ignore `.sh`. But the rewriter at `entrypoint.sh:50-61` translates `<name>.ps1` → `<name>.sh` in hook commands, so an orphan `.ps1` becomes a "hook references missing script" warning at container start (`entrypoint.sh:199-208`) and the hook never fires.

`install.sh` and `install.ps1` perform a pairing audit at install time and warn about orphans. Hooks added by hand without going through the installer MUST also be added in pairs.

**Exception — memory sync scripts (Unix-only).** `scripts/install.sh` and `bootstrap.sh` deploy `memory-sync.sh`, `memory-status.sh` and `memory-notify.sh` to `~/.claude/scripts/`, and the memory validators (`scripts/memory/*.sh`) to `~/.claude/scripts/memory/`, on every global install (claude-config issue #958). Memory sync is Unix-only (claude-config issue #795), so these files have no `.ps1` counterpart and the PowerShell installers do not deploy them. The exception does not reach the rewriter: no hook command in `global/settings.json` or `global/settings.windows.json` references them. They are run by the launchd / systemd scheduler, by the user, and by `memory-write-guard.sh`, which calls the validators by path from inside the hook rather than through a hook command.

**Exception — Windows-only Bash guards.** Since claude-config issue #964, `bash-sensitive-read-guard.ps1` and `shell-env-secret-guard.ps1` have no `.sh` counterpart: macOS and Linux cover secret reads through the shell with the Bash sandbox read-deny (for files under the working directory and the home credential files with their own rule; see [ENFORCEMENT.md](../ENFORCEMENT.md#secrets-outside-the-working-directory)), and Windows has no OS sandbox. No hook command names them; `bash-guard-dispatcher.ps1` invokes them from inside the dispatcher, so the rewriter never sees them.

**Exception — the two stages of the Bash dispatcher.** `bash-guard-dispatcher.sh` and `bash-guard-dispatcher.ps1` share a name and are not equivalents (claude-config issue #1041). The Windows hook command is bash-native, `. ~/.claude/hooks/bash-guard-dispatcher.sh`, so the rewriter passes it through. On Windows the `.sh` answers the calls no guard rule can match and hands the rest to the `.ps1`. In a container there is no `pwsh`: the `.sh` then runs `dangerous-command-guard.sh`, and `merge-gate-guard.sh` for a call that can be a merge, as `global/settings.json` registers them, and merges their decisions. The shell that runs the hook command need not be bash: sourced by another shell, the `.sh` first re-executes `~/.claude/hooks/bash-guard-dispatcher.sh` under bash, with the payload still on standard input (claude-config issue #1054). That needs a `bash` on `PATH`. Before #1041 the rewritten command named a `bash-guard-dispatcher.sh` that did not exist, so a container on a Windows configuration reported a missing hook script and ran no Bash guard.

The path was run in a Linux container (claude-config issue #1049): `ubuntu:24.04`, with `runtime_bootstrap` of `scripts/lib/bootstrap-claude.sh` at claude-docker `57088ad` on a staged Windows `~/.claude`, and the generated hook command then run with a payload on standard input. It was not the claude-docker image, and Claude Code was not started in it.

- The rewriter leaves the command as it is, the syntax check accepts it, and the missing-script check does not name it.
- After the bootstrap's copy the files the path needs are there, executable and without a CR: the two guards, `lib/tokenize-shell.sh` and `lib/timeout-wrapper.sh`.
- Run by `bash -c`, the command gives the decisions of a POSIX install: `ls -la` allow, `rm -rf /` deny, `git stash clear` ask, `git push origin main` deny, `gh pr merge` deny with a failing check and allow with passing ones.
- Run by `sh -c` where `/bin/sh` is dash, every call ended with a syntax error at the stage's first bash-only line and printed no decision, so the call went ahead unguarded (claude-config issue #1054). The hooks reference says a hook command is passed to `sh -c` on Linux, and the claude-docker image is Debian-based, where `/bin/sh` is dash.

Since #1054 the stage hands over to bash when another shell sources it. That was checked with the dash of macOS, not in the container: with the registered command run by `dash -c` against a home whose hooks directory is the checkout's, and `pwsh` hidden, `ls -la` gives allow, `rm -rf /` deny, `git stash clear` ask and `git push origin main` deny, where the same command stopped at the syntax error before the change. The container check above has not been repeated with `sh -c`, and Claude Code was not run on Linux, so which shell it uses for a hook command there is still taken from the reference.

`tests/hooks/test-bash-guard-dispatcher.sh` runs the stage with `pwsh` hidden, under bash and, where there is a `dash`, sourced by `dash`.

### 4. Probe Contract

| Field     | Value                                                                  |
|-----------|------------------------------------------------------------------------|
| Path      | `~/.claude/.full-suite-active`                                         |
| Format    | Single-line JSON, UTF-8, no BOM                                        |
| Writer    | `scripts/install.sh` / `scripts/install.ps1`, full-install path only   |
| Reader    | `plugin/hooks/hooks.json` inline `PreToolUse` guards; container-side hooks |
| Semantics | Presence ⇒ host has the full suite installed. Absence ⇒ lite/plugin only. |

The probe MUST be forwarded into the container's account state so reader hooks see the same answer they would on the host. Forwarding is implemented in `claude-docker/scripts/entrypoint.sh` alongside `CLAUDE.md` / `commit-settings.md` / `.claudeignore`. Removing the probe forwarding on one side without the other re-introduces the silent misclassification bug this probe was added to fix (claude-config issue #423).

### 5. CRLF Normalization Guarantee

claude-config installers write `.sh` files with **LF line endings, UTF-8, no BOM**:

- `install.sh` produces native LF on Linux/macOS.
- `install.ps1` writes via `[IO.File]::WriteAllText` with explicit `UTF8NoBomEncoding` — never `Set-Content` (which appends CRLF + BOM on Windows by default).

Consumers MAY assume `.sh` files in `~/.claude/` are LF-clean immediately after install.

However, on Windows hosts the bind mount may later surface CRLF artifacts if a third party (an editor save, a `git checkout` with `core.autocrlf=true`, a manual `cp` from a CRLF source) wrote into the tree after install. claude-docker's entrypoint compensates by re-running `sed 's/\r$//'` at container start:

- `entrypoint.sh:69-70` — in-place when `CLAUDE_CONFIG_SOURCE` is writable.
- `entrypoint.sh:82-110` — copy-with-normalization when the host mount is read-only.

This is defense-in-depth, **not** a substitute for invariant compliance: claude-config does not promise to detect or repair externally introduced CRLF.

## Breaking-Change Process

If claude-config needs to break any invariant above:

1. Open an issue in claude-config tagged `docker-contract` describing the change and the rationale.
2. Open a paired PR in claude-docker updating `entrypoint.sh` / README to match.
3. Reference the contract version bump in both PRs.
4. Both PRs land in the same release window; neither merges alone.

## Out of Scope

- Plugin distribution (`plugin/`, `plugin-lite/`) is not currently mounted into containers. If that changes, this document needs an additional invariant.
- Per-account state (`~/.claude-state/account-*/`) is owned by claude-docker exclusively. claude-config never writes there.
- Project-level configuration (`<project>/CLAUDE.md`, `<project>/.claude/`) is mounted via the project bind mount, independent of this contract.

---
*Version 1.0 (2026-04-27). Update with claude-config minor releases when invariants change.*
