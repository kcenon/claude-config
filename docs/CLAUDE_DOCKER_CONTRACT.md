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
│   ├── lib/
│   └── known-issues.json
├── scripts/
│   └── *.{sh,ps1}            (also paired)
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
- **Supported by passthrough**: command is already bash-native (`bash <path>.sh`, `~/.claude/hooks/<name>.sh`)
- **Not supported (silent failure)**: heredoc / multi-line `-Command`, `$env:VAR` expansion, quoted paths with spaces, `Join-Path` outside the `statusLine` slot

If a new hook needs syntax outside the supported subset, the corresponding bash variant MUST do the equivalent work via shell-native means. The rewriter is best-effort, not a backstop.

### 3. Dual-Variant Pairing

Every script in `~/.claude/hooks/` and `~/.claude/scripts/` MUST exist as a `.sh` + `.ps1` pair with semantically equivalent behavior. The container ignores `.ps1`; PowerShell sessions ignore `.sh`. But the rewriter at `entrypoint.sh:50-61` translates `<name>.ps1` → `<name>.sh` in hook commands, so an orphan `.ps1` becomes a "hook references missing script" warning at container start (`entrypoint.sh:199-208`) and the hook never fires.

`install.sh` and `install.ps1` perform a pairing audit at install time and warn about orphans. Hooks added by hand without going through the installer MUST also be added in pairs.

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
