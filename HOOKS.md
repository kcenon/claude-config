# Claude Code Hook Configuration Guide

This document describes the Hook settings included in claude-config.

## Overview

Hooks are user-defined commands that automatically execute during specific Claude Code events.

## Quick Navigation

| I want to... | See |
|--------------|-----|
| Protect sensitive files from being read | [Sensitive File Protection](#1-sensitive-file-protection-pretooluse) |
| Block dangerous shell commands | [Dangerous Command Blocking](#2-dangerous-command-blocking-pretooluse) |
| Validate markdown links before commit | [Markdown Anchor Validation](#5-markdown-anchor-validation-pretooluse) |
| Auto-format code after edits | [Auto Formatting](#1-auto-formatting-posttooluse) |
| Limit concurrent Agent Teams | [Team Limit Guard](#6-team-limit-guard-pretooluse) |
| Log session activity | [Session Logging](#3-session-logging-sessionstartsessionend) |
| Check for known Claude Code bugs | [Version Check](#8-version-check-sessionstart) |
| Validate commit messages before git commit | [Commit Message Guard](#10-commit-message-guard-pretooluse) |
| Add my own custom hook | [Adding New Hooks](#adding-new-hooks) |
| Set up hooks on Windows | [Windows Support](#windows-support-powershell) |

## Configuration File Locations

| File | Purpose | Scope |
|------|---------|-------|
| `global/settings.json` | Global Hook settings | All projects |
| `project/.claude/settings.json` | Project Hook settings | Current project only |

## Global Hooks (global/settings.json)

### 1. Sensitive File Protection (PreToolUse)

*Prevents accidental exposure of secrets — Claude will never read your .env or credentials, even if asked directly.*

**Purpose**: Block access to sensitive files like `.env`, `.pem`, `.key`

**Blocked targets**:
- Extensions: `.env`, `.pem`, `.key`, `.p12`, `.pfx`
- Directories: `secrets/`, `credentials/`, `passwords/`, `private/`

**Behavior**:
- Returns JSON with `permissionDecision: "deny"` and exits with code 0
- Claude Code reads the deny reason from the JSON response

### 2. Dangerous Command Blocking (PreToolUse)

*Stops catastrophic mistakes before they happen — no accidental root deletion or unsafe permission changes.*

**Purpose**: Block commands that could have catastrophic system impact

**Blocked targets**:
- `rm -rf /` (root deletion)
- `chmod 777` (dangerous permission change)
- `curl ... | sh` (remote script execution)

### 3. Session Logging (SessionStart/SessionEnd)

*Track when and how long Claude Code sessions run for audit and debugging purposes.*

**Purpose**: Record Claude Code session start/end times

**Log location**: `~/.claude/session.log`

**Log format**:
```
[Session] Claude Code session started: 2025-12-03 14:30:00
[Session] Claude Code session ended: 2025-12-03 15:45:00
```

### 4. Temporary File Cleanup (SessionEnd)

*Keeps your temp directory clean without manual intervention.*

**Purpose**: Automatically delete old temporary files on session end

**Cleanup targets**:
- `/tmp/claude_*` (files older than 60 minutes)
- `/tmp/tmp.*` (owned by current user, older than 60 minutes)

### 5. Markdown Anchor Validation (PreToolUse)

*Catch broken documentation links before they reach your repository — validates every cross-reference on commit.*

**Purpose**: Validate markdown cross-reference anchors before git commit to prevent broken links

**Trigger**: `git commit` commands only (all other commands pass through)

**How it works**:
1. Auto-detects markdown directory (`docs/reference/` → `docs/` → `./`)
2. **Pass 1**: Builds anchor registry from all headings (GitHub-style slug algorithm)
3. **Pass 2**: Checks all `](#anchor)` and `](file.md#anchor)` references against registry
4. Blocks commit if broken anchors are found

**Anchor generation algorithm** (matches GitHub):
- Strip inline formatting (bold, italic, code, links)
- Lowercase → remove non-alphanumeric/space/hyphen (Unicode letters preserved) → spaces to hyphens
- Duplicate headings get `-1`, `-2` suffixes

**Features**:
- Skips code blocks (``` and ~~~ delimiters)
- Handles Korean/CJK characters in anchors
- Validates both intra-file and inter-file references
- Excludes external URLs (detects `:` in path)

**Behavior**:
- Returns JSON with `permissionDecision: "deny"` listing broken anchors
- Timeout: 30 seconds

### 6. Team Limit Guard (PreToolUse)

*Prevent resource exhaustion by capping the number of concurrent Agent Teams across sessions.*

**Purpose**: Enforce a maximum number of concurrent Agent Teams across sessions

**Trigger**: `TeamCreate` tool invocation

**How it works**:
1. Reads `MAX_TEAMS` environment variable (default: 3)
2. Counts directories in `~/.claude/teams/`
3. Blocks team creation if the count meets or exceeds the limit

**Behavior**:
- Returns JSON with `permissionDecision: "deny"` when limit is reached
- Timeout: 5 seconds
- Cross-platform: `team-limit-guard.sh` (bash) and `team-limit-guard.ps1` (PowerShell)

### 7. TeammateIdle (TeammateIdle)

*React when teammates finish work — enforce quality gates or trigger follow-up actions.*

**Purpose**: Fires when a teammate finishes its turn and is about to go idle. Use this to enforce quality gates or log teammate activity.

**Hook input** (JSON via stdin):
```json
{
  "session_id": "abc123",
  "hook_event_name": "TeammateIdle",
  "teammate_name": "researcher",
  "team_name": "my-project",
  "cwd": "/path/to/project",
  "permission_mode": "default"
}
```

**Decision control**: Uses **exit code only** (not JSON `permissionDecision`):

| Exit Code | Effect |
|-----------|--------|
| `0` | Allow teammate to go idle |
| `2` | Block idle — stderr message sent as feedback to teammate |

### 8. Version Check (SessionStart)

*Get warned early if your Claude Code version has known performance bugs.*

**Purpose**: Warn when running Claude Code versions with known cache efficiency bugs

**Trigger**: Every session start (async, non-blocking)

**How it works**:
1. Gets current Claude Code version via `claude --version`
2. Compares against a hardcoded list of known problematic versions (2.1.69–2.1.81)
3. Logs a warning to `~/.claude/session.log` if a match is found

**Known bugs tracked**:
- Resume cache regression ([#34629](https://github.com/anthropics/claude-code/issues/34629))
- Sentinel replacement ([#40524](https://github.com/anthropics/claude-code/issues/40524))

**Behavior**:
- Lifecycle event hook — no JSON output required
- Always exits 0 (non-blocking)
- Timeout: 10 seconds, async
- Cross-platform: `version-check.sh` (bash) and `version-check.ps1` (PowerShell)

### 9. TaskCompleted (TaskCompleted)

*Enforce quality gates before accepting task completion from teammates.*

**Purpose**: Fires when a teammate completes a task from the shared task list. Use this to enforce quality gates before accepting task completion.

**Hook input** (JSON via stdin):
```json
{
  "session_id": "abc123",
  "hook_event_name": "TaskCompleted",
  "task_id": "task-456",
  "task_subject": "Implement user validation",
  "teammate_name": "backend",
  "team_name": "my-project",
  "cwd": "/path/to/project"
}
```

**Decision control**: Uses **exit code only** (not JSON `permissionDecision`):

| Exit Code | Effect |
|-----------|--------|
| `0` | Accept task completion |
| `2` | Block completion — stderr message sent as feedback to teammate |

### 10. Commit Message Guard (PreToolUse)

*Blocks non-conventional commit messages at Claude's Bash tool boundary — deterministic, same input always yields same decision.*

**Purpose**: Validate git commit messages against Conventional Commits rules before Claude invokes `git commit`.

**Trigger**: Bash commands matching `git commit ... -m ...` only.

**Rules enforced**:
- Conventional Commits format: `type(scope): description` or `type: description`
- Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, security
- Description starts with lowercase, no trailing period
- No AI/Claude attribution
- No emojis

**Behavior**:
- Returns JSON with `permissionDecision: "deny"` listing the failed rule
- Defers to the git `commit-msg` hook for command-substitution messages (`-m "$(..."`)
- Timeout: 5 seconds
- Cross-platform: `commit-message-guard.sh` and `commit-message-guard.ps1`

**Shared validation library**: Both this PreToolUse hook and the git `commit-msg` hook (installed by `hooks/install-hooks.sh`) source the same validator at `hooks/lib/validate-commit-message.sh`, ensuring rule consistency across enforcement layers.

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

**Input**: Hooks receive tool input as JSON via stdin. Use `jq` to extract fields:
```bash
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
```

**Exit codes**: Always exit 0 when returning JSON. The decision (allow/deny) is conveyed
through the `permissionDecision` field, not through the exit code.

## Project Hooks (project/.claude/settings.json)

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

## Permission Settings (permissions.deny)

Deny rules defined in `global/settings.json`:

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

## Windows Support (PowerShell)

### Overview

All hooks have PowerShell (`.ps1`) equivalents for native Windows support without Git Bash.

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
  "command": "pwsh -NoProfile -File ~/.claude/hooks/sensitive-file-guard.ps1",
  "timeout": 5
}
```

### PowerShell Hook Scripts

| Hook | File | Description |
|------|------|-------------|
| Sensitive File Guard | `sensitive-file-guard.ps1` | Blocks `.env`, `.pem`, `.key` access |
| Dangerous Command Guard | `dangerous-command-guard.ps1` | Blocks `rm -rf /`, `chmod 777`, pipe execution |
| Session Logger | `session-logger.ps1` | Logs session start/end/stop events |
| Cleanup | `cleanup.ps1` | Removes old temp files from `$env:TEMP` |
| Prompt Validator | `prompt-validator.ps1` | Warns on dangerous operation requests |
| GitHub API Preflight | `github-api-preflight.ps1` | Tests GitHub API connectivity |
| Tool Failure Logger | `tool-failure-logger.ps1` | Logs tool execution failures |
| Subagent Logger | `subagent-logger.ps1` | Logs subagent start/stop events |
| Pre-Compact Snapshot | `pre-compact-snapshot.ps1` | Captures state before compaction |
| Worktree Create | `worktree-create.ps1` | Creates isolated worktree directory |
| Worktree Remove | `worktree-remove.ps1` | Logs worktree removal events |
| Task Completed Logger | `task-completed-logger.ps1` | Logs task completion events |
| Config Change Logger | `config-change-logger.ps1` | Logs configuration changes |
| Markdown Anchor Validator | `markdown-anchor-validator.ps1` | Validates markdown cross-reference anchors before commit |
| Team Limit Guard | `team-limit-guard.ps1` | Enforces MAX_TEAMS concurrent team limit |
| Version Check | `version-check.ps1` | Warns about known cache bug versions on session start |

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

Increase the `timeout` value (unit: seconds, max: 300)

### Formatter not working

Verify the formatter is installed:
```bash
which black
which prettier
which clang-format
```

## References

- [Claude Code Hooks Official Documentation](https://docs.anthropic.com/claude-code/hooks)
- [Settings Official Documentation](https://docs.anthropic.com/claude-code/settings)
