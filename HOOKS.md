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
