# Compatibility Guide

This document maps claude-config versions to their minimum Claude Code requirements, lists feature dependencies, and documents known issues.

---

## Minimum Requirements

| claude-config | Min Claude Code | Key Features Introduced |
|:---:|:---:|---|
| **1.6.0** | **2.2.0+** | Agent Teams (TeamCreate guard), batch processing, version-check hook, `/harness` skill |
| **1.5.0** | **2.1.0+** | Skills format (`.claude/skills/`), Agent Teams env var, 8 new hook types, worktree hooks, `teammateMode` |
| **1.4.0** | **2.0.0+** | Import syntax (`@path/to/file`), recursive imports |
| **1.3.0** | **2.0.0+** | Slash commands (`.claude/commands/`), `UserPromptSubmit` / `Stop` hook events |
| **1.2.0** | **1.0.0+** | Basic hooks (`PreToolUse`, `SessionStart`, `SessionEnd`), `settings.json` permissions |
| **1.1.0** | **1.0.0+** | Rules (`.claude/rules/`), commands, agents, MCP configuration |
| **1.0.0** | **1.0.0+** | Initial CLAUDE.md, basic settings |

> **Note**: Minimum versions are estimates based on when Claude Code introduced the underlying features. Check the [Claude Code changelog](https://code.claude.com/docs/en/changelog) for exact feature availability.

---

## Feature Dependencies

### Hook Event Types

Each hook event type requires a Claude Code version that supports it. If your Claude Code version does not recognize an event type, the hook is silently ignored.

| Hook Event | Used By | Purpose |
|---|---|---|
| `PreToolUse` | sensitive-file-guard, dangerous-command-guard, github-api-preflight, markdown-anchor-validator, prompt-validator (LLM), team-limit-guard | Block or allow tool calls before execution |
| `PostToolUseFailure` | tool-failure-logger | Log failed tool executions |
| `SessionStart` | session-logger, version-check | Session lifecycle logging, version warnings |
| `SessionEnd` | session-logger, cleanup | Session logging, temp file cleanup |
| `Stop` | session-logger | Log when Claude stops generating |
| `UserPromptSubmit` | prompt-validator | Validate user prompts before processing |
| `SubagentStart` | subagent-logger | Track subagent lifecycle |
| `SubagentStop` | subagent-logger | Track subagent lifecycle |
| `PreCompact` | pre-compact-snapshot | Snapshot context before auto-compaction |
| `WorktreeCreate` | worktree-create | Custom worktree initialization |
| `WorktreeRemove` | worktree-remove | Custom worktree cleanup |
| `TaskCompleted` | task-completed-logger | Log task completions (Agent Teams) |
| `ConfigChange` | config-change-logger | Log configuration changes |
| `TeammateIdle` | session-logger | Log teammate idle events (Agent Teams) |

### Settings Features

| Feature | Setting Key | Min Version (est.) |
|---|---|---|
| Skills | `.claude/skills/` directory with `SKILL.md` | 2.1.0+ |
| Agent Teams | `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | 2.1.0+ |
| Teammate mode | `teammateMode` | 2.1.0+ |
| Effort level | `effortLevel` | 2.0.0+ |
| Output style | `outputStyle` | 2.0.0+ |
| Always thinking | `alwaysThinkingEnabled` | 2.0.0+ |
| Status line | `statusLine` | 2.1.0+ |
| Spinner verbs | `spinnerVerbs` | 2.1.0+ |
| Sandbox config | `sandbox` | 2.0.0+ |
| Permissions deny | `permissions.deny` | 1.0.0+ |
| LLM hook (prompt type) | `hooks[].hooks[].type: "prompt"` | 2.0.0+ |
| Async hooks | `hooks[].hooks[].async: true` | 2.0.0+ |
| Tool search | `env.ENABLE_TOOL_SEARCH` | 2.1.0+ |

### Component Dependencies

| Component | Depends On |
|---|---|
| `/issue-work`, `/pr-work` skills | Skills system, `gh` CLI, Bash tool |
| `/harness` skill | Skills system, Agent Teams, TeamCreate tool |
| `/release` skill | Skills system, `gh` CLI, Bash tool |
| Agent definitions (`.claude/agents/`) | Agent/subagent system |
| Worktree hooks | WorktreeCreate/WorktreeRemove hook events |
| Team limit guard | TeamCreate PreToolUse matcher |
| Version check hook | SessionStart hook event, `claude --version` |
| Auto-formatting hooks | PostToolUse hook event (project settings) |

---

## Settings Field Inventory and Stability

Every non-schema field in `global/settings.json` and `global/settings.windows.json` is
catalogued here with its status relative to the official Claude Code settings
reference: [`code.claude.com/docs/en/settings`](https://code.claude.com/docs/en/settings).

**Status legend:**

| Status | Meaning |
|---|---|
| **Stable** | Documented on `code.claude.com/docs/en/settings`. Changes follow deprecation policy. |
| **Experimental** | Officially documented as experimental, opt-in, or subject to removal. |
| **Undocumented** | Not listed on the official settings page. May be session-only, internal, or pending documentation. |
| **Misplaced** | Documented but belongs in a different file (e.g., `~/.claude.json`). May trigger a schema warning. |

### settings.json top-level fields

| Field | Status | Min CC Version | Notes |
|---|---|---:|---|
| `$schema` | Stable | 2.0.0+ | Points to JSON Schema Store; enables editor validation. |
| `description` | Undocumented | — | Self-descriptor string; not read by Claude Code. Advisory only. |
| `version` | Undocumented | — | claude-config's own version string; not a Claude Code field. |
| `respectGitignore` | Stable | 2.0.0+ | Controls `@` file picker. Default `true`. |
| `cleanupPeriodDays` | Stable | 2.0.0+ | Session file retention. Minimum 1, rejected at 0. |
| `language` | Stable | 2.0.0+ | Preferred response language. |
| `outputStyle` | Stable | 2.0.0+ | Adjusts the system prompt (e.g. `"Explanatory"`). |
| `attribution.commit` | Stable | 2.0.0+ | Empty string hides commit attribution. |
| `attribution.pr` | Stable | 2.0.0+ | Empty string hides PR attribution. |
| `attribution.issue` | Undocumented | — | Not on settings reference; used by claude-config's `attribution-guard` hook. Verify on each CC release. |
| `permissions.defaultMode` | Stable | 2.0.0+ | Valid: `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`. |
| `permissions.deny` / `allow` / `ask` | Stable | 1.0.0+ | Permission rule arrays. |
| `hooks` | Stable | 1.0.0+ | Lifecycle hook events. See [HOOKS.md](HOOKS.md). |
| `statusLine` | Stable | 2.1.0+ | Custom status line script. |
| `sandbox.enabled` / `autoAllowBashIfSandboxed` / `allowUnsandboxedCommands` / `excludedCommands` | Stable | 2.0.0+ | Bash sandboxing (macOS, Linux, WSL2). |
| `sandbox.network.allowedDomains` / `allowLocalBinding` | Stable | 2.0.0+ | Sandbox network policy. |
| `spinnerVerbs` | Stable | 2.1.0+ | Customize spinner action verbs. |
| `alwaysThinkingEnabled` | Stable | 2.0.0+ | Enable extended thinking by default. |
| `effortLevel` | Stable | 2.0.0+ | Valid: `low`, `medium`, `high`, `xhigh`. **Note:** `max` is NOT officially supported despite our local schema permitting it ([tracked](https://github.com/kcenon/claude-config/issues/336)). |
| `autoUpdatesChannel` | Stable | 2.1.0+ | `"stable"` or `"latest"`. |
| `skipDangerousModePermissionPrompt` | Stable | 2.0.0+ | Ignored in project settings (security). |
| `showTurnDuration` | **Misplaced** | 2.1.0+ | Officially belongs in `~/.claude.json`, not `settings.json`. May trigger schema validation warning in future CC versions. Consider moving. |
| `teammateMode` | **Misplaced** | 2.1.0+ | Same as above — belongs in `~/.claude.json`. Valid values: `auto`, `in-process`, `tmux`. |
| `harness_policies.p4_strict_schema` | Undocumented | — | claude-config Kill Switch for P4 strict-schema dispatch (EPIC #454). Default `false`. **Bypass:** set `STRICT_SCHEMA=0` env var (env wins over settings) to force lenient schema validation across all skills. |
| `harness_policies.p4_d1_merged_at` | Undocumented | — | ISO-8601 anchor for the D1 (#461) merge. Read by p4-timeline-guard.sh and p4-timeline-reminder.sh. |
| `harness_policies.p4_grace_until` | Undocumented | — | ISO-8601 deadline for the lenient-only grace window. PRs touching `global/skills/_internal/` are blocked by p4-timeline-guard.sh until now() >= this timestamp. **Override:** `CLAUDE_P4_OVERRIDE=1` (RCA required). |
| `harness_policies.p4_observation_until` | Undocumented | — | ISO-8601 deadline for the observation window. Edits flipping `p4_strict_schema` to `true` are blocked until now() >= this timestamp. **Override:** `CLAUDE_P4_OVERRIDE=1` (RCA required). |
| `harness_policies.p4_freeze_until` | Undocumented | — | ISO-8601 deadline for the post-D2 72h freeze. SessionStart banner remains active until now() >= this timestamp. |

### env fields in settings.json

| Field | Status | Min CC Version | Notes |
|---|---|---:|---|
| `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | **Experimental** | 2.1.0+ | Documented as experimental on `code.claude.com/docs/en/env-vars`. Set to `1` to enable agent teams. Subject to renaming or removal. |
| `env.MAX_TEAMS` | Undocumented | 2.1.0+ | Paired with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Not on env-vars reference page. |
| `env.ENABLE_TOOL_SEARCH` | Undocumented | 2.1.0+ | Deferred-tool schema loading. Mentioned indirectly on env-vars page but not formally documented. |
| `env.MAX_MCP_OUTPUT_TOKENS` | Undocumented | 2.0.0+ | MCP output token cap. Not on env-vars reference page. |

### Operational guidance

1. **Before upgrading Claude Code**: Review Experimental/Undocumented rows. If a row disappears from code.claude.com docs entirely, the feature may be removed.
2. **When a flag silently stops working**: Run `/config` in an interactive session and check whether the field is rejected, then check code.claude.com for renaming.
3. **Misplaced fields**: The two Misplaced rows are accepted today but may trigger schema validation errors in future CC versions. A follow-up migration is tracked separately.

### SessionStart version check (optional)

`global/hooks/version-check.sh` currently warns on known-bad versions (see "Known Problematic Versions" below). A future enhancement could extend it to warn when the detected Claude Code version has known breaking changes to any Experimental field above.

---

## Known Problematic Versions

The following Claude Code versions have confirmed bugs. The `version-check.sh` SessionStart hook warns users on these versions.

| Versions | Issue | Impact |
|---|---|---|
| **2.1.69 -- 2.1.81** | Resume cache regression + sentinel replacement bug | Degraded cache efficiency; sessions may use significantly more tokens than expected |

**References:**
- Resume cache regression: [anthropics/claude-code#34629](https://github.com/anthropics/claude-code/issues/34629)
- Sentinel replacement: [anthropics/claude-code#40524](https://github.com/anthropics/claude-code/issues/40524)

> To update the known-bad list, edit `global/hooks/version-check.sh` and modify the `KNOWN_CACHE_BUG_VERSIONS` variable.

---

## Upgrade Guidance

### Upgrading claude-config

When upgrading claude-config to a new version:

1. **Check minimum Claude Code version** in the table above. If your Claude Code is older than the minimum, unsupported features will be silently ignored.

2. **Review the changelog** in [README.md](README.md#version) or the version-specific `VERSION_HISTORY.md` files for breaking changes.

3. **Run the install script** to deploy updated files:
   ```bash
   ./scripts/install.sh
   ```

4. **Verify the installation** after deploying:
   ```bash
   ./scripts/verify.sh
   ```

5. **Restart Claude Code** for changes to take effect. Settings, hooks, and skills are loaded at session start.

### Upgrading Claude Code

When upgrading Claude Code itself:

1. **Check for known problematic versions** in the table above. Skip those versions if possible.

2. **New hook events** added in newer Claude Code versions may enable previously-ignored hooks in your configuration. This is generally safe -- hooks are designed to be forward-compatible.

3. **Test hooks after upgrade** by starting a new session and checking `~/.claude/session.log` for any errors.

### Cross-Platform Notes

- macOS/Linux uses `.sh` hook scripts; Windows uses `.ps1` variants
- The `settings.windows.json` maps hooks to PowerShell equivalents
- Use `install.ps1` on Windows instead of `install.sh`
- PowerShell 7+ (`pwsh`) is required for Windows support

#### Cross-platform `timeout` fallback (`global/hooks/lib/timeout-wrapper.sh`)

`merge-gate-guard.sh` bounds its `gh pr checks` call via `_run_with_timeout`. The
wrapper resolves to the first available implementation, in this order:

1. **GNU `timeout`** — present on Linux (coreutils) and BSD distros that ship coreutils.
2. **`gtimeout`** — installed by `brew install coreutils` on macOS.
3. **`perl alarm`** — universal fallback. macOS ships `/usr/bin/perl` by default, so vanilla machines without Homebrew coreutils still get a bounded call.
4. **Pure-bash `wait`/`kill`** — last-resort fallback for minimal images (e.g. busybox) that lack perl.

All branches normalize to GNU-timeout exit semantics (exit 124 on budget exceeded). The PowerShell guard uses `Start-Job` + `Wait-Job -Timeout` for the same contract. Override the budget with `GH_CHECKS_TIMEOUT_SEC` (default `10`).

---

*Last updated: 2026-04-17 | claude-config v1.6.0*
