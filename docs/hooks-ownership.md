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
| `PreToolUse` | `Edit\|Write\|Read` | `sensitive-file-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Edit\|Write\|Read` | `pre-edit-read-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Edit\|Write\|Read` | `memory-write-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `dangerous-command-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `bash-sensitive-read-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `shell-env-secret-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `bash-write-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `gh-write-verb-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `github-api-preflight.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `markdown-anchor-validator.ps1` | `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `commit-message-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `traceability-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `conflict-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `pr-target-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `push-target-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `pr-language-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `merge-gate-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `attribution-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `TeamCreate` | `team-limit-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `markdown-anchor-validator.sh` | `project/.claude/settings.json` (project-only override) |
| `SessionStart` | — | `session-logger.{sh,ps1} start` | `global/settings.json` + `global/settings.windows.json` |
| `SessionStart` | — | `version-check.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `SessionStart` | — | `memory-integrity-check.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `SessionStart` | — | `export TZ=Asia/Seoul` | `project/.claude/settings.json` |
| `SessionEnd` | — | `session-logger.{sh,ps1} end` + `cleanup.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `UserPromptSubmit` | — | `prompt-validator.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `Stop` | — | `session-logger.{sh,ps1} stop` | `global/settings.json` + `global/settings.windows.json` |
| `PostToolUse` | `Edit\|Write` | inline formatter (black/isort/prettier/clang-format/ktlint/gofmt/rustfmt) | **`plugin/hooks/hooks.json`** (canonical; do not duplicate in settings files) |
| `PostToolUse` | `Task\|Agent` | `post-task-checkpoint.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PostToolUse` | `Read` | `pre-edit-read-guard.{sh,ps1}` (tracker) | `global/settings.json` + `global/settings.windows.json` |
| `PostToolUse` | `Read` | `memory-access-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PostToolUseFailure` | `.*` | `tool-failure-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `SubagentStart` | `.*` | `subagent-logger.{sh,ps1} start` | `global/settings.json` + `global/settings.windows.json` |
| `SubagentStop` | `.*` | `subagent-logger.{sh,ps1} stop` | `global/settings.json` + `global/settings.windows.json` |
| `PreCompact` | — | `pre-compact-snapshot.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `SessionStart` | `compact` | `post-compact-restore.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `InstructionsLoaded` | — | `instructions-loaded-reinforcer.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `TaskCreated` | — | `task-created-validator.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `WorktreeCreate` | — | `worktree-create.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `WorktreeRemove` | — | `worktree-remove.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `TaskCompleted` | — | `task-completed-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `ConfigChange` | — | `config-change-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `TeammateIdle` | — | `session-logger.{sh,ps1} teammate-idle` | `global/settings.json` + `global/settings.windows.json` |
| `CwdChanged` | — | `cwd-change-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PermissionDenied` | — | `permission-denial-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |

"`global/settings.json` + `global/settings.windows.json`" means the
same hook is installed from either file depending on OS; only one of
the two files is the active surface at runtime, so there is no
duplicate execution.

The plugin bundle (`plugin/hooks/hooks.json`) also registers simplified
inline `PreToolUse: Edit|Write|Read` and `PreToolUse: Bash` guards. These
activate only when the full global suite is absent — they detect
`~/.claude/.full-suite-active` (written by `scripts/install.sh` and
`scripts/install.ps1` on a full install) and exit early when the
canonical hooks are present. The detection is per-hook, so the plugin
falls back only for canonical hooks the probe does not advertise. Any
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
