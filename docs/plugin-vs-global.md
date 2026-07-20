# Plugin vs. Global Suite

The Claude Config plugin (`plugin/`) ships a reduced standalone subset of
the security guards in the full global suite (`global/hooks/`). Its
sensitive-file guard matches the same filename pattern set as the
canonical `global/hooks/sensitive-file-guard.sh`, but the plugin's guards
are inline shell approximations rather than the canonical scripts, and
they stop short of the full suite in the ways listed under
[Retained Divergences](#retained-divergences). Both surfaces are
intentionally available, but only one should be active on a given machine
at a time — otherwise each `PreToolUse` event runs duplicated checks. This
document describes how the plugin detects the global suite at runtime,
when to install which surface, how the handoff fails safely, and where the
two surfaces still differ.

## Decision Matrix

| User type | Wants | Install | Probe written? |
|-----------|-------|---------|----------------|
| Quick drop-in, single machine | Security hooks + skills only | Plugin only (`claude plugin install …`) | No |
| Full configuration owner | Skills, hooks, skills, agents, scripts, tmux, etc. | `scripts/install.sh` (full suite) | Yes |
| Full suite + plugin loaded together | Full suite hooks; skills from either surface | `scripts/install.sh` plus plugin | Yes — plugin guards stand down |
| Development / testing | Load both deliberately | `claude --plugin-dir ./plugin` on a machine with the full suite | Yes — plugin guards stand down |

The rule of thumb: if `scripts/install.sh` (or its PowerShell sibling)
ran for install type 1 / 3 / 5, the global suite is active and the
plugin's inline guards must stay out of the way. Otherwise the plugin is
the standalone defense.

## Probe File Contract

The plugin detects the global suite by reading a probe file at a
well-known path.

| Field | Value |
|-------|-------|
| Path | `~/.claude/.full-suite-active` |
| Format | Single-line JSON, UTF-8 |
| Writer | `scripts/install.sh` / `scripts/install.ps1`, full-install path only |
| Reader | `plugin/hooks/hooks.json` inline `PreToolUse` guards |

Schema:

```json
{
  "schema": 1,
  "hooks": {
    "sensitive-file-guard": true,
    "dangerous-command-guard": true
  }
}
```

- `schema` is an integer. Only `1` is recognised today; other values
  are treated as unknown and fall back to the safe default.
- `hooks` is a flat map from canonical hook name (matching the script
  filename in `global/hooks/`, without extension) to a boolean. `true`
  means "the global suite owns this hook on this machine." `false` or a
  missing key means "the plugin should keep its inline fallback active
  for this hook."
- The installer writes the probe atomically (POSIX: `mktemp` + `mv`;
  PowerShell: `Move-Item -Force`) so a partial write cannot produce a
  half-valid probe.
- The POSIX installer uses `python3` to serialise the JSON; if
  `python3` is not on `PATH` it skips the probe write and warns. The
  plugin's inline guards stay active in that case.

## Behavior Matrix

The plugin inspects the probe file before every `PreToolUse: Edit|Write|Read`
and `PreToolUse: Bash` event. For the matching hook name, the guard
behaves as follows:

| Probe state | Plugin guard behavior |
|-------------|----------------------|
| Probe absent | Active (standalone fallback) |
| Probe present, `schema: 1`, hook key `true` | Skip (exit 0) |
| Probe present, `schema: 1`, hook key `false` | Active (fallback for that hook) |
| Probe present, `schema: 1`, hook key missing | Active (fallback for that hook) |
| Probe present, unknown schema | Active (safe default: deny) |
| Probe present, malformed JSON | Active (safe default: deny) |

The check is per-hook. A probe that only advertises
`sensitive-file-guard: true` stands down the plugin's sensitive-file
guard while leaving its `Bash` guard active. This gives correct coverage
when the full suite is installed but one of its hook scripts is absent
(for example, a partial manual copy).

## Retained Divergences

The plugin's sensitive-file guard matches the same *filename* pattern set
as `global/hooks/sensitive-file-guard.sh` — the `.env.*` family, the bare
`*.env` suffix, `.envrc`, credential containers, SSH private keys, and AWS
credential files, with `.env.example` / `.env.sample` / `.env.template`
allowed through. The differences below remain by design. They are
documented limitations, not oversights.

| Area | Global suite | Plugin | Disposition |
|------|--------------|--------|-------------|
| Path canonicalization | `resolve_path` (`global/hooks/lib/path-utils.sh`) expands `~`/`$HOME`, collapses symlinks through `realpath`, and canonicalizes macOS `/var` → `/private/var` before matching | Basename only — strips the directory prefix, trims surrounding whitespace, folds case | Limitation. A symlink pointing at a sensitive file is not caught. Resolving symlinks inside a single-line `bash -c` string would be a fragile approximation of the real check. |
| Decision protocol | Reads hook JSON on stdin, replies with `permissionDecision` on stdout, always exits 0 | Reads `CLAUDE_FILE_PATH`, writes to stderr, exits 2 to deny | Intentional, not a gap. The plugin ships without the `jq` dependency and the `lib/` helpers the canonical hooks source. |
| Sensitive-directory patterns | `secrets`, `credentials`, `passwords` | Same, plus `private` | Plugin is broader. Kept — narrowing it would remove shipped coverage. |
| `Bash` matcher scope | Three hooks: `dangerous-command-guard.sh`, `bash-write-guard.sh` (read-before-write, via shell tokenization), `bash-sensitive-read-guard.sh` (secret reads through the Bash channel) | One inline guard, three regexes: recursive delete of `/`, `chmod 777`/`a+rwx`, and `curl`/`wget` piped to a shell | Limitation. The plugin covers only part of the destructive-command class. Reading a secret via `cat`, and writing a file without reading it first, are unguarded on the plugin-only surface. |

A machine running the plugin standalone therefore has meaningfully less
coverage than one running the full suite. The plugin is a drop-in
baseline, not a substitute for `scripts/install.sh`.

## Failure Modes

- **Probe deleted post-install.** The plugin falls back to its inline
  guards immediately on the next `PreToolUse` — no restart or
  re-registration required. Running `scripts/install.sh` again
  restores the probe.
- **Probe corrupted** (unknown schema, truncated JSON, binary
  garbage). The plugin's guards stay active as the safe default; the
  global suite's canonical hooks (installed separately in
  `~/.claude/hooks/`) also continue to run, so the user sees duplicate
  denial messages but never a gap in coverage.
- **Partial install.** If only some canonical hook scripts are present
  in `~/.claude/hooks/`, the installer records `false` for the missing
  ones in the probe. The plugin keeps its fallback active for those
  hooks only, so gaps are always filled.
- **Schema evolution.** A future release that bumps `schema` to `2`
  will cause older plugins to see an unknown schema and revert to
  active fallback. Users on the mismatched pair get safe duplication,
  never a silent bypass. The recommended upgrade order is
  `scripts/install.sh` first, then reinstall the plugin.
- **No `python3` on POSIX install.** The installer warns and skips the
  probe write; the plugin's guards stay active. The user has the same
  coverage as a standalone plugin install.

## Spec Compliance

Verified 2026-04-30 against the official plugin structure documented at
https://code.claude.com/docs/en/plugins.

| Plugin | Layout | Verdict |
|--------|--------|---------|
| `plugin/` | `.claude-plugin/`, `agents/`, `hooks/`, `skills/`, `.lsp.json`, `.claudeignore`, `README.md` at plugin root | Compliant |
| `plugin-lite/` | `.claude-plugin/`, `skills/`, `README.md` at plugin root | Compliant |

Both plugins place required directories (`agents/`, `hooks/`, `skills/`) at
the plugin root, not nested inside `.claude-plugin/`. The official docs
explicitly warn against the nested layout — only the plugin manifest
(`plugin.json`) and related metadata belong inside `.claude-plugin/`.

`plugin/` ships an `.lsp.json` for LSP server registration. This is an
official optional component listed in the structure table, not an ad-hoc
extension.

Neither plugin currently uses `monitors/`, `bin/`, or a plugin-level
`settings.json`. These are valid optional extension points per the spec —
their absence reflects a scope decision, not a gap. Adding them later
requires no migration of the existing layout.

## Related

- `docs/hooks-ownership.md` — single-owner-per-hook rule, including the
  plugin's place in the ownership table.
- `docs/install.md` — how the full installer decides when to copy each
  file.
- `plugin/README.md` — plugin-specific install and behavior notes.
