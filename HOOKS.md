# Claude Code Hook Configuration Guide

This document describes the Hook settings included in claude-config.

## Overview

Hooks are user-defined commands that automatically execute during specific Claude Code events.

## Configuration File Locations

| File | Purpose | Scope |
|------|---------|-------|
| `global/settings.json` | Global Hook settings | All projects |
| `project/.claude/settings.json` | Project Hook settings | Current project only |

## Global Hooks (global/settings.json)

### 1. Sensitive File Protection (PreToolUse)

**Purpose**: Block access to sensitive files like `.env`, `.pem`, `.key`

**Blocked targets**:
- Extensions: `.env`, `.pem`, `.key`, `.p12`, `.pfx`
- Directories: `secrets/`, `credentials/`, `passwords/`, `private/`

**Behavior**:
- Displays `[BLOCKED]` message and stops operation
- Returns exit code 2

### 2. Dangerous Command Blocking (PreToolUse)

**Purpose**: Block commands that could have catastrophic system impact

**Blocked targets**:
- `rm -rf /` (root deletion)
- `chmod 777` (dangerous permission change)
- `curl ... | sh` (remote script execution)

### 3. Session Logging (SessionStart/SessionEnd)

**Purpose**: Record Claude Code session start/end times

**Log location**: `~/.claude/session.log`

**Log format**:
```
[Session] Claude Code session started: 2025-12-03 14:30:00
[Session] Claude Code session ended: 2025-12-03 15:45:00
```

### 4. Temporary File Cleanup (SessionEnd)

**Purpose**: Automatically delete old temporary files on session end

**Cleanup targets**:
- `/tmp/claude_*` (files older than 60 minutes)
- `/tmp/tmp.*` (owned by current user, older than 60 minutes)

### 5. Markdown Anchor Validation (PreToolUse)

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
- Displays list of broken anchors and blocks commit (exit code 2)
- Timeout: 30 seconds

## Project Hooks (project/.claude/settings.json)

### 1. Auto Formatting (PostToolUse)

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
