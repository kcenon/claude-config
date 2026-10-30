# Claude Code Hook Configuration Guide

This document describes the Hook settings included in claude-config.

> **Authoritative inventory**: the [Auto-Generated Hook Catalog](#auto-generated-hook-catalog) at the bottom of this document is the single source of truth for the list of hooks shipped under `global/hooks/`. It is regenerated from the leading comment block of each hook script by `scripts/gen-hooks-md.sh` and verified in CI by `.github/workflows/validate-hooks-doc.yml`. The narrative sections that follow provide additional context for the most-used hooks but defer to that catalog for the canonical list.

## Overview

Hooks are user-defined commands that automatically execute during specific Claude Code events.

## Hook Policy

Since #964 claude-config registers hooks only for destructive, irreversible operations and for a few functional contracts. Style, workflow and policy rules are not hooks: they are instructions in `global/CLAUDE.md` and `global/commit-settings.md`, or native controls: the tool contracts, `permissions.deny`, the Bash sandbox, the git hooks and the server-side workflows.

A guard decides by this rule:

1. **Deny** an operation when it is irreversible **and** it reaches beyond the working tree or affects shared state.
2. **Ask** (`permissionDecision: "ask"`) when it is irreversible but scoped to the working tree, or when it rewrites or deletes a shared ref.
3. **Allow** everything recoverable through the reflog, the remote or VCS history.

### Registered hooks

`global/settings.json` registers 10 hook entries:

| Event / matcher | Hook | Role |
|-----------------|------|------|
| PreToolUse `Bash` | `dangerous-command-guard` | Deny and ask tiers for destructive shell, `git` and `gh` operations |
| PreToolUse `Bash` | `merge-gate-guard` | Deny `gh pr merge` while any check is not green |
| PreToolUse `Edit\|Write` | `memory-write-guard` | Validate writes to the shared memory repository; allow everything else |
| SessionStart | `memory-integrity-check` | Memory-sync health summary; silent without memory sync |
| PostToolUse `Read` | `memory-access-logger` | Log reads of shared-memory files (path only) |
| SessionEnd | `cleanup`, `prune-permission-rules` | Temp file cleanup; prune `permissions.allow` entries that can never match again |
| WorktreeCreate / WorktreeRemove | `worktree-create`, `worktree-remove` | Worktree contract |
| PermissionDenied | `permission-denial-logger` | Redacted audit record of denied tool calls |

A Bash call starts two hook processes and an Edit or Write call one; a Read starts only the async memory-access logger. `global/settings.windows.json` registers the same events. On Windows the `Bash` matcher goes through [`bash-guard-dispatcher.ps1`](#bash-guard-dispatcher-windows), which also runs the Windows-only `bash-sensitive-read-guard` and `shell-env-secret-guard`, because Windows has no OS sandbox.

### Where the removed rules live now

Issue #964 removed the other 32 registrations. A reinstall prunes their script files from `~/.claude/hooks/` and keeps any you edited locally.

| Removed hook(s) | Replaced by |
|-----------------|-------------|
| `pre-edit-read-guard` (PreToolUse and PostToolUse) | The native Edit/Write contract; the `global/CLAUDE.md` invariant stays |
| `sensitive-file-guard` | `permissions.deny` `Read(...)` rules, which also block Edit and Write on the path (Claude Code 2.1.228+) |
| `bash-write-guard` | The Bash sandbox write allowlist (macOS, Linux); `global/CLAUDE.md` |
| `bash-sensitive-read-guard`, `shell-env-secret-guard` (`.sh`) | The Bash sandbox read-deny covers secret files under the working directory on macOS and Linux, plus `~/.aws/credentials`; SSH keys in `~/.ssh` are a [known gap](ENFORCEMENT.md#secrets-outside-the-working-directory). Nothing there replaces the check on printing a secret-bearing environment variable. The `.ps1` guards stay on Windows |
| `gh-write-verb-guard`, `github-api-preflight` | The destructive `gh` arms of `dangerous-command-guard`; no `additionalContext` injection |
| `commit-message-guard`, `attribution-guard` | The `commit-msg` git hook; `settings.json` `attribution: ""` |
| `pr-language-guard`, `traceability-guard` | The `commit-settings.md` instruction; the `pre-push` git hook and the skills check traceability |
| `conflict-guard` | git refuses most operations during a merge or rebase |
| `pr-target-guard`, `push-target-guard` | `validate-pr-target.yml` (server-side); the protected-branch push arm moved into `dangerous-command-guard` |
| `team-limit-guard` | Nothing; creating a team is not destructive |
| `markdown-anchor-validator` (project layer) | Nothing |
| `session-logger`, `subagent-logger`, `tool-failure-logger`, `task-completed-logger`, `config-change-logger`, `cwd-change-logger`, `pre-compact-snapshot`, `post-compact-restore`, `instructions-loaded-reinforcer`, `post-task-checkpoint`, `prompt-validator`, `task-created-validator`, `version-check` | Nothing; Claude Code's own transcripts and debug logs cover diagnostics |

## Quick Navigation

| I want to... | See |
|--------------|-----|
| Know which hooks run and why | [Hook Policy](#hook-policy) |
| Protect sensitive files from being read | [Sensitive File Protection](#1-sensitive-file-protection-permissionsdeny) |
| Deny or confirm destructive commands | [Destructive Command Guard](#2-destructive-command-guard-pretooluse) |
| Block gh pr merge when any check is non-passing | [Merge Gate Guard](#3-merge-gate-guard-pretooluse) |
| Guard and observe the shared memory repository | [Memory Hooks](#4-memory-hooks) |
| Clean up temp files and dead permission rules | [Session-End Housekeeping](#5-session-end-housekeeping-sessionend) |
| Auto-format code after edits | [Auto Formatting](#1-auto-formatting-posttooluse) |
| Block direct pushes to protected branches | [Pre-push Protected Branch Guard](#git-hooks-pre-push-protected-branch-guard) |
| Understand how Bash guards are dispatched on Windows | [Bash Guard Dispatcher](#bash-guard-dispatcher-windows) |
| Understand how Edit/Write guards are dispatched on Windows | [Edit Guard Dispatcher](#edit-guard-dispatcher-windows) |
| Add my own custom hook | [Adding New Hooks](#adding-new-hooks) |
| Set up hooks on Windows | [Windows Support](#windows-support-powershell) |

## Configuration File Locations

| File | Purpose | Scope |
|------|---------|-------|
| `global/settings.json` | Global Hook settings | All projects |
| `project/.claude/settings.json` | Project Hook settings | Current project only |

## Global Hooks (global/settings.json)

> **Registration differs by platform for the `Bash` and `Edit|Write`
> matchers.** On POSIX, `global/settings.json` registers each guard as its own
> hook, so the per-guard `Timeout:` values in the sections below are the values
> in force. On Windows, `global/settings.windows.json` registers exactly one hook
> on each of those matchers — [`bash-guard-dispatcher.ps1`](#bash-guard-dispatcher-windows)
> and [`edit-guard-dispatcher.ps1`](#edit-guard-dispatcher-windows) — which front
> their guards: the guards share the dispatcher's 25 s internal budget rather
> than carrying their own. Sections 2 and 3 describe the Bash-matcher guards;
> `memory-write-guard` (section 4) is the `Edit|Write` one.

### 1. Sensitive File Protection (permissions.deny)

*Prevents accidental exposure of secrets — Claude will never read your .env or credentials, even if asked directly.*

**Mechanism**: no hook since #964. `permissions.deny` in `global/settings.json` and `global/settings.windows.json` lists a `Read(...)` rule for each pattern below, and a `Read` deny also blocks Edit and Write on the same path (Claude Code 2.1.228+). See [Permission Settings](#permission-settings).

**Denied targets**:
- Filename patterns: `.env` (incl. `.envrc`, `.env.*`, and the `*.env` suffix form such as `production.env`), `.pem`, `.key`, `.p12`, `.pfx`, `*password*`, and SSH key basenames `id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa` (incl. suffixed variants)
- Path patterns: `secrets/`, `credentials/`, `passwords/`, plus `credentials` and `config` under `.aws/`. The plugin-only fallback shares the filename set but additionally blocks `private/`; it stands down when the full suite is active (see [Plugin vs Global](docs/plugin-vs-global.md#retained-divergences)).
- Home-anchored: `~/.aws/credentials` (#973). The patterns above start with `**/` and are relative to the working directory, so they match only under it.

**Shell channel**: on macOS and Linux the Bash sandbox read-deny covers `cat .env` and similar reads of files under the working directory, plus `~/.aws/credentials`. SSH private keys in `~/.ssh` are deliberately not denied, because sandboxed SSH commit signing reads the key file; see [Secrets outside the working directory](ENFORCEMENT.md#secrets-outside-the-working-directory). Windows has no OS sandbox, so `bash-sensitive-read-guard.ps1` runs in the [Bash dispatcher](#bash-guard-dispatcher-windows) there.

### 2. Destructive Command Guard (PreToolUse)

*Stops irreversible mistakes before they happen, and asks before destructive ones.*

**Files**: `global/hooks/dangerous-command-guard.sh`, `global/hooks/dangerous-command-guard.ps1`. The file name predates #964 and is kept: installed plugins read it as a probe key, and the decision log and the Windows dispatcher entry use it.

**Deny** (irreversible and reaching beyond the working tree or shared state):
- recursive `rm` of `/`, an absolute path, `~` or `$HOME`
- a download piped to an interpreter (`curl ... | sh`)
- `chmod 777` and setuid changes; IFS obfuscation
- a direct `git push` to `main`, `master` or `develop`, including a refspec-less push whose upstream is one of them
- `gh repo delete`, and `gh api -X DELETE repos/<owner>/<repo>`

**Ask** (irreversible but local, or rewriting or deleting a shared ref):
- `git reset --hard`, `git checkout -- <path>` / `.` / `-f`, `git switch -f` / `--force` / `--discard-changes`, and `git restore` without `--staged`, only when the work tree has changes
- `git clean -f`, `git stash drop` / `clear`
- `git push --force` / `-f` / `+<ref>` (not `--force-with-lease`), `git push --delete` / `-d`, `git push <remote> :<ref>`
- recursive `rm` of `.`, `..`, `*`, `.*`, `.git` or a path outside the repository; `find ... -delete` / `-exec rm`
- `gh <group> delete` / `delete-asset` and every other `gh api -X DELETE`

**Allow**: everything else, for example `rm -rf build`, `git reset --soft`, `git push --force-with-lease` to a work branch and `git branch -D`.

**Payload scanning**: the payload of `bash|sh|zsh|dash|ksh|fish -c '...'` and of `eval ...` is tokenized and checked with the same rules, up to three nested levels. A payload that cannot be inspected (unbalanced quotes, a bare variable expansion, deeper nesting) is denied. `source <file>` and `. <file>` are allowed; `eval "$(curl ...)"` is still remote execution.

**Variable command heads**: outside a payload, a command head that is a variable (`$X`, `${X}`) is replaced by the value of an earlier `X=value` or `export X=value` in the same command, so `X=rm; $X -rf ~` is denied like `rm -rf ~`. When the value is unknown, the arguments are checked as if the command were `rm`, and the guard asks if `rm` would be denied or asked; `$EDITOR notes.md` and `"$PYTHON" x.py` stay allowed.

**Over-budget input**: a command longer than `DCG_TOKENIZER_MAX_BYTES` (16384 bytes) is not tokenized. A line-based regex scan denies the deny-tier shapes (recursive `rm` of `/`, an absolute path, `~` or `$HOME`; a fetch piped to an interpreter; `chmod 777`; a push to `main`, `master` or `develop`; `gh repo delete`; `gh api -X DELETE repos/<owner>/<repo>`) and asks when the text contains a keyword of any ask arm. Anything else, such as a long `echo` chain, is allowed with a coarse-scan note.

**Logging**: one JSON line per `deny` or `ask` decision in `~/.claude/logs/dangerous-command-guard.log` (`CLAUDE_LOG_DIR` overrides the directory). Allow decisions are not logged.

**Behavior**:
- Returns JSON with `permissionDecision` `deny` or `ask` and a reason; a plain allow emits the minimal allow JSON
- Fail-closed: unparseable hook input is denied
- The work tree checks run `git status` / `git rev-parse` only after a command has matched an arm
- Timeout: 5 seconds on POSIX; on Windows, shared with the other Bash guards inside the [dispatcher](#bash-guard-dispatcher-windows)

### 3. Merge Gate Guard (PreToolUse)

*Hard-blocks `gh pr merge` when any PR check is failing, pending, or cancelled — eliminates the rule drift that lets failing CI rationalizations slip through in long-running batch workflows.*

**Purpose**: Enforces the "ABSOLUTE CI GATE" rule from `global/CLAUDE.md` at the Bash tool boundary: a deterministic hook gate that catches drift where the model occasionally rationalizes failing checks as "unrelated", "infrastructure", or "pre-existing". The merge method (`--squash`, `--merge`, `--rebase`) is not checked since #964; the repository's merge settings decide it.

**Trigger**: `Bash` tool calls matching `gh pr merge`.

**Files**: `global/hooks/merge-gate-guard.sh`, `global/hooks/merge-gate-guard.ps1`

**Logic**:
1. Scope gate: only process `gh pr merge` commands (all others pass through).
2. Extract PR number from positional integer, URL form (`https://github.com/owner/repo/pull/N`), or anywhere after `gh pr merge`. Allow if no PR number is found (interactive mode).
3. Extract `--repo` / `-R` value if present.
4. Invoke `gh pr checks <PR> --json bucket,name,state` (with `-R` if specified).
5. Parse the JSON array. Allowed buckets: `pass` and `skipping`. Anything in `fail`, `pending`, `cancel`, or unknown buckets blocks the merge.
6. Deny reason includes every non-passing check name with its bucket and state, plus a reminder not to rationalize failures.

**Allow policy**: A check qualifies as passing if its `bucket` is `pass` or `skipping`. The `skipping` bucket covers checks intentionally skipped (e.g. `paths-ignore` matches) and is treated as neutral, the same way GitHub itself does for branch protection rules.

**Fail policy**: **Fail-OPEN** on `gh` CLI errors. Unlike `dangerous-command-guard`, this hook allows the merge when:
- `gh` CLI is not installed
- `gh pr checks` returns a non-zero exit code (e.g. transient network error, auth failure, unresolvable PR)
- The JSON response cannot be parsed
- The PR has no checks configured at all

A diagnostic is written to stderr in each fail-open case so the user can see why the gate did not run. The rationale is that this hook is a "best-effort gate", not a "hard fail on tool unavailability" — server-side branch protection rules remain as the authoritative gate, so a transient failure here should not permanently block user work.

**Behavior**:
- Returns JSON with `permissionDecision: "deny"` listing every non-passing check
- Fail-open on any gh CLI error; diagnostics written to stderr
- Timeout: 30 seconds on POSIX, longer than `dangerous-command-guard` because it makes an external API call. On Windows it has no budget of its own: it runs inside the [dispatcher](#bash-guard-dispatcher-windows) and gets whatever remains of the shared 25 s after the guards ahead of it
- Cross-platform: `merge-gate-guard.sh` and `merge-gate-guard.ps1`

**Configuration**:
```json
{
  "type": "command",
  "command": "~/.claude/hooks/merge-gate-guard.sh",
  "timeout": 30
}
```

**Example deny response**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Merge blocked by ABSOLUTE CI GATE: PR #100 has non-passing checks: Build Linux [fail/FAILURE], Build Windows [pending/IN_PROGRESS]. Wait for all checks to pass before merging — never rationalize a failure as unrelated, infrastructure, or pre-existing."
  }
}
```

### 4. Memory Hooks

*Gate and observe the shared memory repository; every hook here is silent when memory sync is not set up.*

| Hook | Event | Behavior |
|------|-------|----------|
| `memory-write-guard` | PreToolUse `Edit\|Write` | Validates an Edit or Write under `~/.claude/memory-shared/memories/` before it reaches disk: a structure, secret or owner-configuration failure denies, an injection finding only warns. Allows every other path. Timeout 30 s. |
| `memory-integrity-check` | SessionStart | Prints a short `[memory]` health summary from local metadata, with no network call |
| `memory-access-logger` | PostToolUse `Read` (async) | Logs the path of each read under the shared memory tree |

See [docs/MEMORY_SYNC.md](docs/MEMORY_SYNC.md) for operations and [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) for why these stay.

### 5. Session-End Housekeeping (SessionEnd)

*Keeps your temp directory and your project permission rules clean without manual intervention.*

**`cleanup`** deletes old temporary files on session end:
- `$TMPDIR/claude_*` (older than 60 minutes)
- `$TMPDIR/tmp.*` (owned by the current user, older than 60 minutes)

It does not rotate or delete the logs that the loggers removed in #964 left behind in `~/.claude/logs/`.

**`prune-permission-rules`** removes `permissions.allow` entries that can never match again from the project's `settings.local.json` (#923). It fails open: any parse, classification or IO error leaves the file byte-identical.

### 6. Worktree and Permission-Denial Hooks

| Hook | Event | Behavior |
|------|-------|----------|
| `worktree-create` | WorktreeCreate (synchronous) | Creates an isolated worktree directory when isolation is requested outside a git repository and prints its absolute path; a non-zero exit fails the creation |
| `worktree-remove` | WorktreeRemove (async) | Logs the removal; cannot block it |
| `permission-denial-logger` | PermissionDenied (async) | Appends a redacted JSONL record of each denied tool call to `~/.claude/logs/permission-denials.jsonl`; `CLAUDE_PERMISSION_LOGGER=0` disables it |

### Hook Response Format

All PreToolUse hooks must output JSON to stdout and exit with code 0:

**Allow response**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
```

**Deny response**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Reason for blocking"
  }
}
```

**Ask response** (Claude Code prompts the user and shows the reason):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Reason for confirming"
  }
}
```

**Input**: Hooks receive tool input as JSON via stdin. Use `jq` to extract fields:
```bash
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
```

**Exit codes**: Always exit 0 when returning JSON. The decision (allow/ask/deny) is conveyed
through the `permissionDecision` field, not through the exit code.

## Project Hooks (project/.claude/settings.json)

`project/.claude/settings.json` registers one hook: a SessionStart entry that
exports `TZ=Asia/Seoul`. The formatter below is owned by the plugin
(`plugin/hooks/hooks.json`); see [docs/hooks-ownership.md](docs/hooks-ownership.md).

### 1. Auto Formatting (PostToolUse)

*Never worry about code style — every edit is automatically formatted in your language's standard style.*

**Purpose**: Automatically run language-specific formatters after file modifications

**Supported languages and tools**:

| Extension | Formatter | Installation |
|-----------|-----------|--------------|
| `.py` | black + isort | `pip install black isort` |
| `.ts`, `.tsx`, `.js`, `.jsx`, `.json`, `.md` | prettier | `npm install prettier` |
| `.cpp`, `.cc`, `.h`, `.hpp` | clang-format | `brew install clang-format` |
| `.kt`, `.kts` | ktlint | `brew install ktlint` |
| `.go` | gofmt | Included with Go installation |
| `.rs` | rustfmt | Included with Rust installation |

**Behavior**:
- Skips if tool is not installed (no error)
- Timeout: 30 seconds

## Permission Settings

Deny rules defined in `global/settings.json` and `global/settings.windows.json`
block direct tool access to sensitive files:

```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(.env.*)",
      "Read(**/.env)",
      "Read(**/secrets/**)",
      "Read(**/credentials/**)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      ...
    ]
  }
}
```

Since #964 these `Read(...)` rules are the whole file-channel sensitive-file
control: a `Read` deny also blocks Edit and Write on the same path (Claude Code
2.1.228+), and the rules feed the Bash sandbox read-deny on macOS and Linux.
Both are relative to the working directory for `**/` patterns; see
[Secrets outside the working directory](ENFORCEMENT.md#secrets-outside-the-working-directory).

The Windows profile also carries a narrow `permissions.allow` list for native
`PowerShell(...)` read-only discovery commands. It covers common inspection
verbs such as `Get-ChildItem`, `Test-Path`, `Select-Object`, `Select-String`,
and `Write-Output`, plus read-only `git` and `gh` commands. The allowlist is
intended to reduce repeated confirmation prompts for routine local inspection;
it is not a general bypass profile.

The Windows profile intentionally keeps these guardrails:

- `permissions.defaultMode` remains `default`.
- `disableBypassPermissionsMode` and `disableAutoMode` remain `disable`.
- No broad `PowerShell(*)` rule is allowed.
- Direct content reads such as `Get-Content`, file mutation cmdlets, remote
  execution cmdlets, and state-changing `gh` commands are not allowlisted.
- Sensitive-file deny rules stay in place.

`tests/scripts/test-windows-settings-parity.sh` gates this contract in CI. It
fails on unexpected drift in top-level settings keys, shared `env` values,
`permissions.deny`, or the Bash `permissions.allow` surface, while keeping the
Windows-only PowerShell allowlist and POSIX-only CA-bundle environment variables
as explicit platform exceptions.

`skipDangerousModePermissionPrompt` only suppresses the extra dangerous-mode
launch warning. It does not widen `permissions.allow`, and it does not override
the installed profile's bypass/auto-mode disable settings.

### Over-length commands and the parse limit

A single Bash/PowerShell command that exceeds the harness command-parser limit
(observed at ~965 bytes; harness-internal and not configurable here) cannot be
parsed, so it cannot match any `permissions.allow` rule and falls back to a
manual prompt. This is distinct from the hooks' own 16384-byte tokenizer budget
(`DCG_TOKENIZER_MAX_BYTES`), which is a downstream performance guard, not the
cause of the prompt.

Decisions for this repo:

- **Do not widen the allow-list to escape the prompt.** A rule like
  `Bash(pwsh -File:*)` would auto-approve execution of *any* script file — the
  allow-list grammar cannot scope by path
  (`scripts/schemas/settings-json.schema.json`) — which would defeat the narrow
  Windows profile above. Accept a one-time prompt for the wrapper invocation
  instead.
- **No hook mitigation.** The parse limit is upstream of the hook layer; a hook
  cannot pre-empt or override the harness fallback, so this is out of scope.
- **Prevention is the lever.** Keep single commands short and extract long logic
  to a script — see `project/.claude/rules/core/environment.md`
  (Command Construction).

## Windows Support (PowerShell)

### Overview

Every hook has a PowerShell (`.ps1`) equivalent for native Windows support without Git Bash. Windows also runs two guards that have no `.sh` twin, `bash-sensitive-read-guard.ps1` and `shell-env-secret-guard.ps1`, because macOS and Linux cover those reads with the Bash sandbox and Windows has no OS sandbox.

| Configuration | File |
|---------------|------|
| **macOS/Linux** | `global/settings.json` (runs `.sh` hooks via bash) |
| **Windows** | `global/settings.windows.json` (runs `.ps1` hooks via `pwsh`) |

### How It Works

The `install.ps1` script automatically:
1. Copies `settings.windows.json` as `~/.claude/settings.json`
2. Installs all `.ps1` hook scripts to `~/.claude/hooks/`

Hook commands use `pwsh -NoProfile -File` for fast, profile-independent execution:
```json
{
  "type": "command",
  "command": "pwsh -NoProfile -File ~/.claude/hooks/memory-integrity-check.ps1",
  "timeout": 5
}
```

### Bash Guard Dispatcher (Windows)

*Single entry point for every Bash guard on Windows, in place of one hook registration per guard.*

**Purpose**: Each registered hook is its own `pwsh -NoProfile` process. Before
the dispatcher (#895), one Bash tool call started 15 of them, one per guard.
Process start dominates the cost (~350 ms each, measured) while the guard logic
itself costs ~13 ms. The dispatcher pays the process cost once, reads stdin
once, imports `CommonHelpers` once, and invokes only the guards whose command
family is present in the tool input. Since #964 it fronts four guards.

**Registration**: `global/settings.windows.json` registers
`bash-guard-dispatcher.ps1` as the only hook on the `Bash` matcher, with
`timeout: 30`. POSIX registers its two `.sh` guards individually, because a
`bash` process is cheap to start and there is nothing to consolidate. This is
also why there is no `bash-guard-dispatcher.sh`: the `.sh`/`.ps1` parity audit
in `.github/workflows/validate-hooks-doc.yml` exempts `*-dispatcher.*`, since a
`.sh` twin would be exactly the dormant unwired file that audit exists to catch.

**Routing table**: the prefilter is deliberately *coarser* than each guard's own
filter. It skips a guard only when its command family is definitely absent, and
every guard then re-applies its own precise filter. Too narrow would silently
disable a guard; too wide costs a few milliseconds.

| Routed when | Guards | Fail policy |
|-------------|--------|-------------|
| always | `dangerous-command-guard`, `bash-sensitive-read-guard` (Windows-only), `shell-env-secret-guard` (Windows-only) | closed |
| command contains `gh` | `merge-gate-guard` | open |

**Fail policy**: `closed` means a crash in that guard **denies** the call, because
a security gate must never fail silently open. `open` means a crash warns
through `additionalContext` and allows, and is reserved for a gate whose
authoritative check lives elsewhere: for `merge-gate-guard`, server-side branch
protection. Unparseable hook input is fail-closed for the dispatcher as a whole,
matching `dangerous-command-guard`, the strictest guard it fronts.

**Decision merge**: `deny` > `ask` > `allow`, the precedence Claude Code itself
applies across PreToolUse hooks. Any deny wins; otherwise every `ask` is merged
into one `ask` whose reason lists each guard's reason.

**Time budget**: 25 s internally, inside the harness's 30 s `timeout`. When the
internal budget runs out the dispatcher does not truncate silently: it names
every guard it skipped in `additionalContext`. The individually-registered POSIX
guards have no equivalent internal budget, where a harness timeout is fail-open
and therefore invisible (see [Timeout occurring](#timeout-occurring)). The
`Edit|Write` matcher has the same internal budget in
[its own dispatcher](#edit-guard-dispatcher-windows).

### Edit Guard Dispatcher (Windows)

*Single entry point for the `Edit|Write` guards on Windows.*

**Purpose**: the same process-cost problem as the Bash dispatcher, on the matcher
that fired most often. Before #964 one file operation started three
`pwsh -NoProfile` processes. Measured then on this profile, 5 runs each with the
same payload: the three-process chain p50 1,068 ms (spread 21 ms) against the
dispatcher's p50 410 ms (spread 36 ms), a 62% reduction (#920).

**Registration**: `global/settings.windows.json` registers
`edit-guard-dispatcher.ps1` as the only hook on the `Edit|Write` matcher, with
`timeout: 30`. POSIX registers `memory-write-guard.sh` directly, and there is
likewise no `edit-guard-dispatcher.sh`, which the `*-dispatcher.*` exemption in
`.github/workflows/validate-hooks-doc.yml` allows. The dispatcher stays although
it routes a single guard since #964, so a later file-channel guard needs no new
registration.

**Routing table**:

| Routed when | Guard | Fail policy |
|-------------|-------|-------------|
| `Edit`/`Write` and path contains `memory-shared` | `memory-write-guard` | open |

**Prefilter**: `memory-write-guard` shells out to `validate.sh`,
`secret-check.sh` and `injection-check.sh`, and its own gate accepts nothing
outside `$HOME/.claude/memory-shared/memories/*.md`. The prefilter matches the
coarse `memory-shared` substring instead, keeping every path the guard could act
on while skipping the subprocess cost for ordinary edits.

**Ordering**: the routing table also supports a `shortCircuit` flag, so that a
deny from one guard can hide the target from the guards after it. The harness
runs later hooks even after a denial, so only a dispatcher can enforce an order
(#424, #521, #920). No guard uses it since #964.

**Fail policy**: unparseable hook input is fail-open with a diagnostic for the
dispatcher as a whole, matching `memory-write-guard`, which must not block
legitimate work because of its own failure (#521). The fail-closed policy it
replaced existed for the sensitive-file guard that #964 removed.

**Time budget**: 25 s internally, inside the harness's 30 s `timeout`, with the
same no-silent-truncation rule as the Bash dispatcher.

**Payload delivery**: as with the Bash dispatcher, the payload reaches each guard
through the process-lifetime cache in `Read-HookInput`
(`global/hooks/lib/CommonHelpers.psm1`), not through a parameter — no guard
declares a `param()` block, so the `-HookInput` argument lands in `$args` and is
ignored. `tests/hooks/test-edit-guard-dispatcher.ps1` asserts the deny *reason*,
not just the decision, because a broken cache would still produce a deny.

**Standalone contract**: every guard still accepts an optional `-HookInput`
parameter carrying the already-parsed payload and falls back to reading stdin
when it is absent, so each guard runs standalone and its own test suite is
unaffected. Guards are invoked with `&`, never dot-sourced, so a guard's `exit`
terminates only that guard.

**Coverage guard**: `tests/scripts/test-windows-hooks-parity.sh` expands the
dispatcher registration into its routed guard names before diffing against the
POSIX registrations, so a guard dropped from the routing table fails CI. Its
`WIN_ONLY_ALLOW` set lists the two Windows-only guards, `bash-sensitive-read-guard`
and `shell-env-secret-guard`.

**Measured effect** (before #964, when the Bash matcher carried 15 guards): an
accidental revert produced an A-B-A-B sequence, so the payoff of the Bash
dispatcher can be read off real sessions rather than a bench. `PreToolUse:Bash`
hook durations from all local transcripts:

| Phase | Dates | Bash configuration | n | median | p90 | p99 | vs P0 |
|-------|-------|--------------------|--:|-------:|----:|----:|------:|
| P0 | .. 2026-07-26 | 15 individual hooks | 9,072 | 828 ms | 951 ms | 1,462 ms | - |
| P1 | 07-28 .. 07-31 | dispatcher prototype | 2,991 | 424 ms | 1,067 ms | 1,972 ms | **-48.8%** |
| P2 | 08-01 .. 08-05 | 15 individual hooks | 37,061 | 908 ms | 1,272 ms | 3,089 ms | +9.7% |
| P3 | 2026-08-06 .. | dispatcher (shipped) | 12,656 | 534 ms | 1,117 ms | 1,564 ms | **-35.5%** |

The `Edit|Write|Read` matcher of that time is the control. No transition touched
it and it stays flat across all four: 415 / 437 / 448 / 426 ms over 34,625 runs.
Session load or machine state would have moved both channels together, so the
Bash channel's two-fold swings are attributable to hook topology.

Two cautions for anyone re-running this. **Segment by phase.** A naive
before-and-after split at 2026-07-27 reports roughly no improvement, because P2
lands in the "after" bucket. **P1 was never in this repository**: the dispatcher
first shipped here on 2026-08-06 (#895). P1 is a local prototype whose guard-side
half had been reverted by 2026-08-01, leaving the dispatcher unwireable until
#895 replaced that approach; see the `Read-HookInput` entry in `CHANGELOG.md`.
A measurement taken from an unshipped local prototype has to be re-confirmed
after the change actually lands.

### PowerShell Hook Scripts

| Hook | File | Description |
|------|------|-------------|
| Bash Guard Dispatcher | `bash-guard-dispatcher.ps1` | Runs the Bash guards in one process |
| Edit Guard Dispatcher | `edit-guard-dispatcher.ps1` | Runs the `Edit\|Write` guards in one process |
| Dangerous Command Guard | `dangerous-command-guard.ps1` | Denies irreversible operations and asks before destructive ones |
| Merge Gate Guard | `merge-gate-guard.ps1` | Blocks `gh pr merge` while any check is not green |
| Bash Sensitive Read Guard | `bash-sensitive-read-guard.ps1` | Windows-only: blocks secret reads through the shell (`cat .env`) |
| Shell Env Secret Guard | `shell-env-secret-guard.ps1` | Windows-only: blocks printing secret-bearing environment variables |
| Memory Write Guard | `memory-write-guard.ps1` | Validates writes to the shared memory repository |
| Memory Integrity Check | `memory-integrity-check.ps1` | Memory-sync health summary at session start |
| Memory Access Logger | `memory-access-logger.ps1` | Logs reads of shared-memory files |
| Cleanup | `cleanup.ps1` | Removes old temp files from `$env:TEMP` |
| Prune Permission Rules | `prune-permission-rules.ps1` | Prunes dead `permissions.allow` entries on session end |
| Worktree Create | `worktree-create.ps1` | Creates isolated worktree directory |
| Worktree Remove | `worktree-remove.ps1` | Logs worktree removal events |
| Permission Denial Logger | `permission-denial-logger.ps1` | Logs denied tool calls (redacted) |

### Key Differences from Bash Hooks

| Feature | Bash (`.sh`) | PowerShell (`.ps1`) |
|---------|-------------|---------------------|
| JSON parsing | `jq` (external dependency) | `ConvertFrom-Json` (built-in) |
| Temp file cleanup | `find /tmp -mmin +60` | `Get-ChildItem $env:TEMP` |
| Pattern matching | `grep -qE` | `-match` operator |
| HTTP requests | `curl` | `Invoke-WebRequest` |
| Timestamps | `date +"%Y-%m-%d"` | `Get-Date -Format` |

### Prerequisites

- **PowerShell 7+** (`pwsh`): Recommended for full compatibility
  ```powershell
  winget install Microsoft.PowerShell
  ```
- **Execution Policy**: Must allow running local scripts
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

### Troubleshooting (Windows)

#### "File cannot be loaded because running scripts is disabled"
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### Hooks not executing
1. Verify `pwsh` is installed: `pwsh --version`
2. Verify JSON syntax: `Get-Content ~/.claude/settings.json | ConvertFrom-Json`
3. Check hook files exist: `Get-ChildItem ~/.claude/hooks/*.ps1`
4. Restart Claude Code

#### "pwsh is not recognized"
Install PowerShell 7+: `winget install Microsoft.PowerShell`

---

## Customization

### Disabling Hooks

To disable a specific hook, remove or comment out the corresponding entry.

### Adding New Hooks

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "type": "command",
        "command": "your-command-here",
        "timeout": 30
      }
    ]
  }
}
```

### Matcher Patterns

| Pattern | Description |
|---------|-------------|
| `*` | All tools |
| `Bash` | Bash tool only |
| `Edit\|Write` | Edit or Write tools |
| `Read` | Read tool only |

## Troubleshooting

### Hook is not executing

1. Verify JSON syntax: `cat settings.json | python3 -m json.tool`
2. Check file location: `~/.claude/settings.json` or `.claude/settings.json`
3. Restart Claude Code

### Timeout occurring

Increase the `timeout` value (unit: seconds, max: 300).

**A PreToolUse timeout is fail-open.** When a hook exceeds its budget the
harness cancels it and the tool call proceeds; the hook never gets to deny. An
under-budgeted *security* guard is therefore silently skipped rather than
enforced, which is the opposite of what the guard exists to do. Budget
generously and read a timeout as a coverage gap, not as noise.

Timeouts appear in the session transcript as a `hook_cancelled` attachment
carrying `timedOut: true` next to `timeoutMs` and the actual `durationMs`. A
user-pressed Esc also produces `hook_cancelled` but without those two fields,
so the two causes are distinguishable.

Contention, not guard logic, produces the tail, and it takes out a whole
matcher at once: before #964, when `Edit|Write|Read` carried three guards, every
timeout observed locally on it arrived in a burst of three with near-identical
durations, meaning all three guards of a single tool call were killed at the
same deadline and that call ran unguarded. Budget for the matcher's worst case,
not its median.

| Matcher | Registered | Timeout | Why |
|---------|-----------|---------|-----|
| `Edit\|Write` | `memory-write-guard` on POSIX; `edit-guard-dispatcher.ps1` on Windows | 30 s | Fail-open makes a skipped guard worse than a slow one. Measured before #964 with three guards on `Edit\|Write\|Read`: median 429 ms and p99 1,020 ms over 35,276 local runs, worst case 11,141 ms (#897). |
| `Bash` | `dangerous-command-guard` (5 s) and `merge-gate-guard` (30 s) on POSIX; `bash-guard-dispatcher.ps1` on Windows | 5 s / 30 s; 30 s | `merge-gate-guard` makes a network call. The Windows dispatcher has a 25 s internal guard budget plus process-start slack, and names any guard it had to skip instead of truncating silently. |

### Formatter not working

Verify the formatter is installed:
```bash
which black
which prettier
which clang-format
```

## Git Hooks: Pre-push Protected Branch Guard

*Prevent invalid commits and accidental pushes to main or develop — requires pull request workflow for protected branches.*

> **Note**: These are standard git hooks under `.git/hooks/`, not Claude Code event hooks. They run from git itself, regardless of whether Claude Code is active.

**Install**: `./hooks/install-hooks.sh` (or `.\hooks\install-hooks.ps1` on Windows)

**Installed inventory**:

| Hook | Source | Purpose |
|------|--------|---------|
| `pre-commit` | `hooks/pre-commit` | Runs `scripts/validate_skills.sh` when staged `SKILL.md` files change |
| `commit-msg` | `hooks/commit-msg` | Validates Conventional Commits format, attribution bans, and emoji bans through `hooks/lib/validate-commit-message.sh` |
| `pre-push` | `hooks/pre-push` | Blocks protected-branch direct pushes and optional preflight/traceability checks |

**Purpose**: Block direct pushes to protected branches (`main`, `develop`)

**Protected branches**: `main`, `develop`

**How it works**:
1. Git invokes the hook before pushing, passing remote info via stdin
2. The hook extracts the target branch from each ref being pushed
3. If the target branch matches a protected branch, the push is blocked with an error message
4. The error message guides the user to use the feature-branch + pull request workflow

**Behavior**:
- Exits with code 1 to block the push when targeting a protected branch
- Exits with code 0 to allow the push for non-protected branches
- Bypass: `git push --no-verify` skips this hook, and no Claude Code hook denies `--no-verify` since #964. A Claude-driven push to a protected branch is still denied by `dangerous-command-guard`, with or without the flag; GitHub branch protection is the server-side gate.

**Cross-platform**:

| File | Runtime | Install behavior |
|------|---------|------------------|
| `hooks/pre-push` | bash / Git Bash | Installed as `.git/hooks/pre-push` by both installers |
| `hooks/pre-push.ps1` | PowerShell 7+ | PowerShell parity implementation; not copied directly into `.git/hooks/pre-push` |

---

## References

- [Claude Code Hooks Official Documentation](https://code.claude.com/docs/en/hooks)
- [Settings Official Documentation](https://code.claude.com/docs/en/settings)

<!-- BEGIN AUTO-GENERATED HOOKS -->

<!-- This section is regenerated by scripts/gen-hooks-md.sh.
     Do not edit by hand — your changes will be overwritten.
     To update: edit the leading comment block of the
     relevant `global/hooks/*.sh` script and re-run the
     generator. -->

## Auto-Generated Hook Catalog

The catalog below is built from the leading comment block
of each hook script under `global/hooks/`. It is the
authoritative listing — the hand-written sections elsewhere
in this document provide narrative context but defer to
this catalog for the canonical hook inventory.

### Index

| Hook | Hook Type | PowerShell |
|---|---|---|
| [`cleanup.sh`](#cleanup) | SessionEnd | yes |
| [`dangerous-command-guard.sh`](#dangerous-command-guard) | PreToolUse (Bash) | yes |
| [`memory-access-logger.sh`](#memory-access-logger) | PostToolUse (Read) | yes |
| [`memory-integrity-check.sh`](#memory-integrity-check) | SessionStart (sync) | yes |
| [`memory-write-guard.sh`](#memory-write-guard) | PreToolUse (Edit|Write) | yes |
| [`merge-gate-guard.sh`](#merge-gate-guard) | PreToolUse (Bash) | yes |
| [`permission-denial-logger.sh`](#permission-denial-logger) | PermissionDenied | yes |
| [`prune-permission-rules.sh`](#prune-permission-rules) | SessionEnd | yes |
| [`worktree-create.sh`](#worktree-create) | WorktreeCreate (synchronous, type: command only) | yes |
| [`worktree-remove.sh`](#worktree-remove) | WorktreeRemove (async, type: command only) | yes |

_Total: 10 bash hooks, 10 with PowerShell counterparts._

### Hook Details

### cleanup

_File:_ `cleanup.sh`

_Anchor:_ `#cleanup`

Cleans up temporary files created during session

| Field | Value |
|---|---|
| Hook Type | SessionEnd |
| Trigger / Matcher | — |
| Exit codes | 0=success |
| Response format | none (lifecycle event, no JSON output needed) |
| PowerShell counterpart | present (`cleanup.ps1`) |
| Source | `global/hooks/cleanup.sh` |

### dangerous-command-guard

_File:_ `dangerous-command-guard.sh`

_Anchor:_ `#dangerous-command-guard`

Denies irreversible shell operations and asks before destructive local ones.

| Field | Value |
|---|---|
| Hook Type | PreToolUse (Bash) |
| Trigger / Matcher | Bash |
| Exit codes | 0 (always — decision is in JSON) |
| Response format | hookSpecificOutput with hookEventName |
| PowerShell counterpart | present (`dangerous-command-guard.ps1`) |
| Source | `global/hooks/dangerous-command-guard.sh` |

### memory-access-logger

_File:_ `memory-access-logger.sh`

_Anchor:_ `#memory-access-logger`

Logs Claude Code Read tool calls targeting memory files (path only).

| Field | Value |
|---|---|
| Hook Type | PostToolUse (Read) |
| Trigger / Matcher | Read |
| Exit codes | 0 (always — this is a passive logger; failure must NOT affect tool flow) |
| Response format | empty stdout (PostToolUse cannot influence the past tool call) |
| PowerShell counterpart | present (`memory-access-logger.ps1`) |
| Source | `global/hooks/memory-access-logger.sh` |

### memory-integrity-check

_File:_ `memory-integrity-check.sh`

_Anchor:_ `#memory-integrity-check`

Prints a brief memory health summary at SessionStart. Reads ~/.claude/memory-shared/ metadata only -- no network, no validators.

| Field | Value |
|---|---|
| Hook Type | SessionStart (sync) |
| Trigger / Matcher | sync |
| Exit codes | 0 always (SessionStart must never block the session) |
| Response format | — |
| PowerShell counterpart | present (`memory-integrity-check.ps1`) |
| Source | `global/hooks/memory-integrity-check.sh` |

### memory-write-guard

_File:_ `memory-write-guard.sh`

_Anchor:_ `#memory-write-guard`

Validates Claude Code Edit/Write tool calls targeting memory files BEFORE disk write.

| Field | Value |
|---|---|
| Hook Type | PreToolUse (Edit|Write) |
| Trigger / Matcher | Edit|Write |
| Exit codes | 0 (always — decision is encoded in JSON response) |
| Response format | hookSpecificOutput with hookEventName "PreToolUse" |
| PowerShell counterpart | present (`memory-write-guard.ps1`) |
| Source | `global/hooks/memory-write-guard.sh` |

### merge-gate-guard

_File:_ `merge-gate-guard.sh`

_Anchor:_ `#merge-gate-guard`

Blocks gh pr merge commands when any PR check is not passing.

| Field | Value |
|---|---|
| Hook Type | PreToolUse (Bash) |
| Trigger / Matcher | Bash |
| Exit codes | 0 (always — decision is in JSON) |
| Response format | hookSpecificOutput with hookEventName |
| Fail policy | FAIL-OPEN on gh CLI errors. If gh is missing, unauthenticated, |
| PowerShell counterpart | present (`merge-gate-guard.ps1`) |
| Source | `global/hooks/merge-gate-guard.sh` |

### permission-denial-logger

_File:_ `permission-denial-logger.sh`

_Anchor:_ `#permission-denial-logger`

Appends a redacted JSONL audit record for every denied tool call.

| Field | Value |
|---|---|
| Hook Type | PermissionDenied |
| Trigger / Matcher | — |
| Exit codes | 0 (always — passive logger, never alters the permission decision) |
| Response format | none (observation-only event; no JSON emitted, never blocks) |
| Fail policy | best-effort; logging failures are swallowed and never surface |
| PowerShell counterpart | present (`permission-denial-logger.ps1`) |
| Source | `global/hooks/permission-denial-logger.sh` |

### prune-permission-rules

_File:_ `prune-permission-rules.sh`

_Anchor:_ `#prune-permission-rules`

Prunes permissions.allow entries that can never match again from the project-scope settings.local.json

| Field | Value |
|---|---|
| Hook Type | SessionEnd |
| Trigger / Matcher | — |
| Exit codes | 0=always (fail-open; teardown is never blocked) |
| Response format | none (lifecycle event, no JSON output needed) |
| Fail policy | fail-open - any parse, classification, or IO error leaves the file byte-identical |
| PowerShell counterpart | present (`prune-permission-rules.ps1`) |
| Source | `global/hooks/prune-permission-rules.sh` |

### worktree-create

_File:_ `worktree-create.sh`

_Anchor:_ `#worktree-create`

Creates an isolated worktree directory for non-git environments

| Field | Value |
|---|---|
| Hook Type | WorktreeCreate (synchronous, type: command only) |
| Trigger / Matcher | synchronous, type: command only |
| Exit codes | — |
| Response format | — |
| PowerShell counterpart | present (`worktree-create.ps1`) |
| Source | `global/hooks/worktree-create.sh` |

### worktree-remove

_File:_ `worktree-remove.sh`

_Anchor:_ `#worktree-remove`

Cleans up and logs worktree removal events

| Field | Value |
|---|---|
| Hook Type | WorktreeRemove (async, type: command only) |
| Trigger / Matcher | async, type: command only |
| Exit codes | — |
| Response format | — |
| PowerShell counterpart | present (`worktree-remove.ps1`) |
| Source | `global/hooks/worktree-remove.sh` |

<!-- END AUTO-GENERATED HOOKS -->
