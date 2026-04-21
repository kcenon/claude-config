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
| `PreToolUse` | `Bash` | `dangerous-command-guard.{sh,ps1}` et al. | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `TeamCreate` | `team-limit-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Edit\|Write` | `pre-edit-read-guard.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreToolUse` | `Bash` | `markdown-anchor-validator.sh` | `project/.claude/settings.json` (project-only override) |
| `SessionStart` | — | `session-logger`, `version-check` | `global/settings.json` + `global/settings.windows.json` |
| `SessionStart` | — | `export TZ=Asia/Seoul` | `project/.claude/settings.json` |
| `SessionEnd` | — | `session-logger end` + `cleanup` | `global/settings.json` + `global/settings.windows.json` |
| `UserPromptSubmit` | — | `prompt-validator.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `Stop` | — | `session-logger stop` | `global/settings.json` + `global/settings.windows.json` |
| `PostToolUse` | `Edit\|Write` | inline formatter (black/isort/prettier/clang-format/ktlint/gofmt/rustfmt) | **`plugin/hooks/hooks.json`** (canonical; do not duplicate in settings files) |
| `PostToolUse` | `Task\|Agent` | `post-task-checkpoint.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PostToolUse` | `Read` | `pre-edit-read-guard.{sh,ps1}` (tracker) | `global/settings.json` + `global/settings.windows.json` |
| `PostToolUseFailure` | `.*` | `tool-failure-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `SubagentStart`/`SubagentStop` | `.*` | `subagent-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PreCompact` | — | `pre-compact-snapshot.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `PostCompact` | — | `post-compact-restore.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `InstructionsLoaded` | — | `instructions-loaded-reinforcer.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `TaskCreated` | — | `task-created-validator.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `WorktreeCreate`/`WorktreeRemove` | — | `worktree-create.{sh,ps1}` / `worktree-remove.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `TaskCompleted` | — | `task-completed-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `ConfigChange` | — | `config-change-logger.{sh,ps1}` | `global/settings.json` + `global/settings.windows.json` |
| `TeammateIdle` | — | `session-logger teammate-idle` | `global/settings.json` + `global/settings.windows.json` |

"`global/settings.json` + `global/settings.windows.json`" means the
same hook is installed from either file depending on OS; only one of
the two files is the active surface at runtime, so there is no
duplicate execution.

The plugin bundle (`plugin/hooks/hooks.json`) also registers simplified
inline `PreToolUse: Edit|Write|Read` and `PreToolUse: Bash` guards; see
issue #423 for the plan to make these standalone-only when the full
global suite is installed.

## Adding a new hook

1. Choose a single owner file from the table above (typically
   `global/settings.json` + `global/settings.windows.json` for OS-wide
   hooks, or `project/.claude/settings.json` for project-scoped ones).
2. Do not add the same entry to any other file.
3. If the hook might reasonably be registered from multiple surfaces
   (for example, a formatter or a language-specific linter), extend
   `tests/scripts/test-no-duplicate-formatter.sh` with a matching
   pattern so CI catches accidental duplication.
