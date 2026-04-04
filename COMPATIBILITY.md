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

> **Note**: Minimum versions are estimates based on when Claude Code introduced the underlying features. Check the [Claude Code changelog](https://docs.anthropic.com/en/docs/claude-code/changelog) for exact feature availability.

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

---

*Last updated: 2026-04-04 | claude-config v1.6.0*
