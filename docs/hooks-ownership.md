# Hooks Ownership

Claude Code merges the `hooks` arrays from every active settings source
(user, project, enterprise, plugins) without deduplication. Every entry
runs. To prevent latency and message noise from duplicate registrations,
each hook is owned by exactly one settings file; other surfaces must
not declare it.

`tests/scripts/test-no-duplicate-formatter.sh` enforces this for the
PostToolUse formatter. Extend the script when introducing new hooks
that could be registered from multiple surfaces.

## Ownership Table

| Hook event | Matcher | Hook script / inline | Owner file |
|------------|---------|----------------------|------------|
| `PreToolUse` | `Edit\|Write` | `memory-write-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `dangerous-command-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `bash-sensitive-read-guard.ps1` (Windows-only, #964) | `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `shell-env-secret-guard.ps1` (Windows-only, #964) | `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `merge-gate-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `SessionStart` | — | `memory-integrity-check.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `SessionStart` | — | `export TZ=Asia/Seoul` | `project/.claude/settings.json` |
| `SessionEnd` | — | `cleanup.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `SessionEnd` | — | `prune-permission-rules.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PostToolUse` | `Edit\|Write` | inline formatter (black/isort/prettier/clang-format/ktlint/gofmt/rustfmt) | **`plugin/hooks/hooks.json`** (canonical; do not duplicate in settings files) |
| `PostToolUse` | `Read` | `memory-access-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `WorktreeCreate` | — | `worktree-create.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `WorktreeRemove` | — | `worktree-remove.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PermissionDenied` | — | `permission-denial-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |

"`global/settings.json` + `global/settings.windows.json`" means the
same hook is installed from either file depending on OS; only one of
the two files is the active surface at runtime, so there is no
duplicate execution.

Ownership is per guard even where Windows does not register the guard
directly. Two matchers are routed through a dispatcher that runs their
guards in a single process instead of one process per guard:
`PreToolUse: Bash` through `global/hooks/bash-guard-dispatcher.ps1`
(issue #895) and `PreToolUse: Edit|Write` through
`global/hooks/edit-guard-dispatcher.ps1` (issue #920). On those matchers
`global/settings.windows.json` names only the dispatcher, and the guard
list lives in the dispatcher's routing table;
`tests/scripts/test-windows-hooks-parity.sh` expands that table so a
guard dropped from it still fails parity. Execution order and fail-open
/ fail-closed behaviour are documented in `HOOKS.md`, not here.

`bash-sensitive-read-guard.ps1` and `shell-env-secret-guard.ps1` are
the only Windows-only rows (#964). macOS and Linux cover secret reads
through the shell with the Bash sandbox read-deny (for files under the
working directory and the home credential files with their own rule; see
[ENFORCEMENT.md](../ENFORCEMENT.md#secrets-outside-the-working-directory)),
but Windows has no OS sandbox, so the Windows Bash dispatcher keeps both
guards. The parity
test lists them in `WIN_ONLY_ALLOW`.

The plugin bundle (`plugin/hooks/hooks.json`) also registers simplified
inline `PreToolUse: Edit|Write|Read` and `PreToolUse: Bash` guards. These
activate only when the full global suite is absent — they detect
`~/.claude/.full-suite-active` (written by `scripts/install.sh` and
`scripts/install.ps1` on a full install) and exit early when the
canonical hooks are present. The detection is per-hook, so the plugin
falls back only for canonical hooks the probe does not advertise. Since
#964 the `sensitive-file-guard` key advertises the `permissions.deny`
coverage of the published settings rather than a hook file. Any
unrecognised probe state (missing, malformed, unknown schema) falls back
to the plugin guard as a safe default. See `docs/plugin-vs-global.md`
for the probe file format, behavior matrix, and failure modes.

## Adding a new hook

1. Choose a single owner file from the table above (typically
   `global/settings.json` + `global/settings.windows.json` for OS-wide
   hooks, or `project/.claude/settings.json` for project-scoped ones).
2. Do not add the same entry to any other file.
3. If the hook might reasonably be registered from multiple surfaces
   (for example, a formatter or a language-specific linter), extend
   `tests/scripts/test-no-duplicate-formatter.sh` with a matching
   pattern so CI catches accidental duplication.
