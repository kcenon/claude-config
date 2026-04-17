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
| Prevent git merge/rebase on dirty trees | [Conflict Guard](#11-conflict-guard-pretooluse) |
| Block PRs targeting main from non-develop branches | [PR Target Guard](#12-pr-target-guard-pretooluse) |
| Block non-English titles/bodies in gh PR/issue commands | [PR Language Guard](#13-pr-language-guard-pretooluse) |
| Block gh pr merge when any check is non-passing | [Merge Gate Guard](#14-merge-gate-guard-pretooluse) |
| Block AI/Claude attribution in gh PR/issue commands | [Attribution Guard](#15-attribution-guard-pretooluse) |
| Re-inject critical policy after instruction load | [Instructions Loaded Reinforcer](#16-instructions-loaded-reinforcer-instructionsloaded) |
| Restore core principles after context compaction | [Post-Compact Restore](#17-post-compact-restore-postcompact) |
| Validate task descriptions at creation time | [Task Created Validator](#18-task-created-validator-taskcreated) |
| Block direct pushes to protected branches | [Pre-push Protected Branch Guard](#git-hooks-pre-push-protected-branch-guard) |
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

### 11. Conflict Guard (PreToolUse)

*Prevents git merge/rebase/cherry-pick/pull when the working tree is dirty or another operation is already in progress.*

**Purpose**: Block conflict-prone git operations when conditions would cause data loss or nested conflicts.

**Trigger**: Bash commands matching `git merge`, `git rebase`, `git cherry-pick`, or `git pull`.

**Checks performed**:
1. **Existing operation**: Denies if `MERGE_HEAD`, `REBASE_HEAD`, or `CHERRY_PICK_HEAD` exists (another operation is in progress)
2. **Uncommitted changes**: Denies if `git status --porcelain` is non-empty (dirty working tree)

**Behavior**:
- Returns JSON with `permissionDecision: "deny"` describing the blocking condition
- Fail-open: if parsing fails or git is not available, the command is allowed
- Advisory only (conflict prevention), not security-critical
- Cross-platform: `conflict-guard.sh` and `conflict-guard.ps1`

## 12. PR Target Guard (PreToolUse)

*Enforces branching policy: only `develop` may merge into `main`.*

**Purpose**: Intercepts `gh pr create` commands and blocks those targeting `main` unless the source branch is `develop` (a legitimate release PR).

**Trigger**: `Bash` tool calls containing `gh pr create`

**Files**: `global/hooks/pr-target-guard.sh`, `global/hooks/pr-target-guard.ps1`

**Logic**:
1. Scope gate: only process `gh pr create` commands (all others pass through)
2. Extract `--base` value (`--base main`, `--base=main`, `-B main`)
3. If `--base main` detected:
   - Allow if `--head develop` is also present (release PR via `/release`)
   - Deny otherwise with guidance message
4. If no `--base` flag: allow (defaults to `develop`)

**Fail policy**: Fail-closed (deny if JSON parsing fails)

**Complements**:
- `pre-push` git hook: blocks `git push origin main/develop`
- `validate-pr-target.yml` GitHub Actions: auto-closes non-develop PRs to main (server-side)

**Configuration**:
```json
{
  "type": "command",
  "command": "~/.claude/hooks/pr-target-guard.sh",
  "timeout": 5
}
```

### 13. PR Language Guard (PreToolUse)

*Hard-blocks non-English titles and bodies in `gh pr` and `gh issue` commands — eliminates the rule drift that lets Korean PR/issue content slip through in long-running batch workflows.*

**Purpose**: Enforces the "All GitHub Issues and Pull Requests must be written in English" rule from `commit-settings.md` at the Bash tool boundary. Mirrors the `commit-message-guard` enforcement model that proved effective for commit messages.

**Trigger**: `Bash` tool calls matching `gh (pr|issue) (create|edit|comment)`.

**Files**: `global/hooks/pr-language-guard.sh`, `global/hooks/pr-language-guard.ps1`

**Shared validation library**: `hooks/lib/validate-language.sh` (single source of truth — same pattern as `validate-commit-message.sh`).

**Logic**:
1. Scope gate: only process `gh (pr|issue) (create|edit|comment)` commands (all others pass through). Six combinations are guarded — `gh pr create`, `gh pr edit`, `gh pr comment`, `gh issue create`, `gh issue edit`, `gh issue comment`.
2. Skip command-substitution / heredoc bodies (`--body "$(...)"`) and `--body-file` references — these cannot be parsed at the shell layer, so the hook defers to other safeguards.
3. Extract `--title` / `-t` and `--body` / `-b` values, supporting both double-quoted and single-quoted forms and `--flag value` / `--flag=value` layouts.
4. Reject if any extracted value contains a byte outside ASCII printable (0x20-0x7E) or ASCII whitespace (0x09-0x0D).
5. Deny reason includes the first offending character so Claude can self-correct (e.g. `first: '한'`).

**Allowed characters**: ASCII printable (0x20-0x7E) and ASCII whitespace (tab, LF, VT, FF, CR). Anything else — accented Latin, CJK, emoji, symbols outside ASCII — is blocked.

**Not covered**: `gh pr review --body` is intentionally not guarded (review comments may have different tone/content needs and would warrant a separate policy decision).

**Fail policy**: Fail-open. If stdin parsing fails or the command is unrecognized, the hook returns `allow`. Server-side review and `commit-msg` hooks remain as additional layers.

**Behavior**:
- Returns JSON with `permissionDecision: "deny"` listing the first non-ASCII grapheme found
- Defers to other layers for command-substitution and `--body-file` cases
- Timeout: 5 seconds
- Cross-platform: `pr-language-guard.sh` and `pr-language-guard.ps1`

**Configuration**:
```json
{
  "type": "command",
  "command": "~/.claude/hooks/pr-language-guard.sh",
  "timeout": 5
}
```

**Example deny response**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "PR/issue --body rejected: Text contains non-ASCII characters (first run: '한국어'). GitHub Issues and Pull Requests must be written in English only — see commit-settings.md."
  }
}
```

### 14. Merge Gate Guard (PreToolUse)

*Hard-blocks `gh pr merge` when any PR check is failing, pending, or cancelled — eliminates the rule drift that lets failing CI rationalizations slip through in long-running batch workflows.*

**Purpose**: Enforces the "ABSOLUTE CI GATE" rule from `global/CLAUDE.md` at the Bash tool boundary. Mirrors the `commit-message-guard` and `pr-language-guard` enforcement model: a deterministic hook gate that catches drift where the model occasionally rationalizes failing checks as "unrelated", "infrastructure", or "pre-existing".

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

**Fail policy**: **Fail-OPEN** on `gh` CLI errors. Unlike most other guards, this hook allows the merge when:
- `gh` CLI is not installed
- `gh pr checks` returns a non-zero exit code (e.g. transient network error, auth failure, unresolvable PR)
- The JSON response cannot be parsed
- The PR has no checks configured at all

A diagnostic is written to stderr in each fail-open case so the user can see why the gate did not run. The rationale is that this hook is a "best-effort gate", not a "hard fail on tool unavailability" — server-side branch protection rules remain as the authoritative gate, so a transient failure here should not permanently block user work.

**Behavior**:
- Returns JSON with `permissionDecision: "deny"` listing every non-passing check
- Fail-open on any gh CLI error; diagnostics written to stderr
- Timeout: 30 seconds (longer than other guards because it makes an external API call)
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

### 15. Attribution Guard (PreToolUse)

*Hard-blocks AI/Claude attribution markers (Co-Authored-By: Claude, "Generated with Claude", Anthropic, etc.) in `gh pr` and `gh issue` titles and bodies — extends the existing commit-message attribution check to PR/issue text.*

**Purpose**: Enforces the "No AI/Claude attribution in commits, issues, or PRs" rule from `commit-settings.md`. The existing `commit-message-guard` only inspects `git commit -m` messages; PR and issue bodies created via `gh` previously bypassed it. This hook closes that gap by gating the same Bash boundary that `pr-language-guard` uses.

**Trigger**: `Bash` tool calls matching `gh (pr|issue) (create|edit|comment)`.

**Files**: `global/hooks/attribution-guard.sh`, `global/hooks/attribution-guard.ps1`

**Shared validation library**: `hooks/lib/validate-commit-message.sh` exposes `CMV_ATTRIBUTION_REGEX` and `validate_no_attribution()` — the same regex used by `commit-message-guard` for git commit messages. Both bash hooks source this single source of truth so attribution rules stay in lockstep across enforcement layers. The PowerShell variant inlines the equivalent regex (since the bash library cannot be sourced from PowerShell); update both when changing the pattern.

**Patterns blocked** (case-insensitive):
- `claude` (any standalone occurrence)
- `anthropic`
- `ai-assisted`
- `co-authored-by: claude` (with optional whitespace)
- `generated with` (matches "Generated with Claude Code" etc.)

**Logic**:
1. Scope gate: only process `gh (pr|issue) (create|edit|comment)` commands. Six combinations are guarded: `gh pr create|edit|comment`, `gh issue create|edit|comment`.
2. Skip command-substitution / heredoc bodies (`--body "$(...)"`) and `--body-file` references — these cannot be parsed at the shell layer.
3. Extract `--title` / `-t` and `--body` / `-b` values supporting double-quoted, single-quoted, and `--flag value` / `--flag=value` layouts.
4. Pass each value through `validate_no_attribution()`. Reject if the regex matches.

**Fail policy**: Fail-open. If stdin parsing fails or the command is unrecognized, the hook returns `allow`. The `commit-msg` git hook and `commit-message-guard` PreToolUse hook remain as additional layers for committed content.

**Behavior**:
- Returns JSON with `permissionDecision: "deny"` when attribution is detected
- Defers to other layers for command-substitution and `--body-file` cases
- Timeout: 5 seconds
- Cross-platform: `attribution-guard.sh` and `attribution-guard.ps1`

**Configuration**:
```json
{
  "type": "command",
  "command": "~/.claude/hooks/attribution-guard.sh",
  "timeout": 5
}
```

**Example deny response**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "PR/issue --body rejected: Text contains AI/Claude attribution (claude, anthropic, ai-assisted, generated with, co-authored-by: claude). Remove attribution before submitting."
  }
}
```

### 16. Instructions Loaded Reinforcer (InstructionsLoaded)

*Re-asserts critical policy (commit-settings, branching, conventional commits) immediately after `CLAUDE.md` and `.claude/rules/*.md` are loaded — closes the gap where long sessions drift away from policy that lives only in the system prompt.*

**Purpose**: Inject a policy-reinforcement block right after Claude finishes loading instruction files. The block restates AI-attribution prohibition, English-only PR/issue rule, branching policy, and Conventional Commits format so they remain in active context even when the original instruction files scroll out.

**Trigger**: `InstructionsLoaded` event — fires once per session, after `CLAUDE.md` / `.claude/rules/*.md` have been ingested.

**Files**: `global/hooks/instructions-loaded-reinforcer.sh`, `global/hooks/instructions-loaded-reinforcer.ps1`

**Logic**:
1. Locate `commit-settings.md` in `~/.claude/commit-settings.md` (falls back to `${CLAUDE_HOME}/commit-settings.md`, then to an inline minimal policy if neither file exists).
2. Compose a reinforcement block containing the located policy text plus branching and commit-format reminders.
3. Emit JSON via `jq` if available; otherwise hand-escape and print the JSON literal.

**Behavior**:
- Returns JSON with `hookSpecificOutput.additionalContext` carrying the reinforcement text
- Always exits 0 — the hook never blocks instruction loading; it only augments context
- Cross-platform: `instructions-loaded-reinforcer.sh` and `instructions-loaded-reinforcer.ps1`

**Configuration**:
```json
{
  "type": "command",
  "command": "~/.claude/hooks/instructions-loaded-reinforcer.sh",
  "timeout": 5
}
```

**Sample input** (JSON via stdin):
```json
{
  "session_id": "abc123",
  "hook_event_name": "InstructionsLoaded",
  "cwd": "/path/to/project"
}
```

**Sample output**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "InstructionsLoaded",
    "additionalContext": "## Critical Policy Reinforcement (auto-injected after instruction load)\n\n# Commit, Issue, and PR Settings\n\nNo AI/Claude attribution in commits, issues, or PRs.\nAll GitHub Issues and Pull Requests must be written in English.\n\n## Branching\n\n- Default working branch: `develop`. Never push directly to `main` or `develop`.\n..."
  }
}
```

### 17. Post-Compact Restore (PostCompact)

*Re-injects `core/principles.md` immediately after Claude Code automatically compacts the conversation — pairs with `pre-compact-snapshot` to keep the four core principles in context across long sessions.*

**Purpose**: When automatic context compaction discards the original `CLAUDE.md` and rule files, this hook re-asserts the four core principles (Think, Minimize, Surgical, Verify) plus behavioral guardrails so the model does not regress to pre-policy defaults after compaction.

**Trigger**: `PostCompact` event — fires once whenever the harness completes an automatic compaction cycle. Pairs with the existing `pre-compact-snapshot` hook (PreCompact event) which captures pre-compact state.

**Files**: `global/hooks/post-compact-restore.sh`, `global/hooks/post-compact-restore.ps1`

**Logic**:
1. Append a restore record (timestamp, session id, working directory) to `~/.claude/logs/compact-snapshots.log` — the same log written by `pre-compact-snapshot.sh` so PreCompact / PostCompact pairs can be correlated.
2. Locate `core/principles.md` from one of: `${CLAUDE_PROJECT_DIR}/.claude/rules/core/principles.md`, `~/.claude/rules/core/principles.md`, or the current working directory tree (falls back to an inline minimal principles block if no file is found).
3. Wrap the located text in a "Post-Compaction Restore" section explaining why it is being re-asserted.
4. Emit JSON via `jq` if available; otherwise hand-escape and print the JSON literal.

**Behavior**:
- Returns JSON with `hookSpecificOutput.additionalContext` carrying the principles re-assertion
- Always exits 0 — the hook never blocks compaction; it only augments the post-compact context
- Writes to `~/.claude/logs/compact-snapshots.log` (created on demand)
- Cross-platform: `post-compact-restore.sh` and `post-compact-restore.ps1`

**Configuration**:
```json
{
  "type": "command",
  "command": "~/.claude/hooks/post-compact-restore.sh",
  "timeout": 5
}
```

**Sample input** (JSON via stdin):
```json
{
  "session_id": "abc123",
  "hook_event_name": "PostCompact",
  "cwd": "/path/to/project"
}
```

**Sample output**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostCompact",
    "additionalContext": "## Post-Compaction Restore (auto-injected)\n\nContext was just compacted. Re-asserting core principles to prevent drift:\n\n# Core Principles\n\n1. **Think Before Acting** — State assumptions explicitly. If uncertain, ask.\n..."
  }
}
```

### 18. Task Created Validator (TaskCreated)

*Hard-blocks low-quality task descriptions at the `TaskCreate` boundary — enforces a minimum length and at least one acceptance-criteria checkbox so that downstream teammates and reviewers never receive vague work items.*

**Purpose**: Validate that every task created via `TaskCreate` carries enough scope and acceptance criteria to be actionable. Mirrors the `commit-message-guard` enforcement model: a deterministic gate that catches the drift where short, ambiguous task descriptions leak into multi-agent batch workflows.

**Trigger**: `TaskCreated` event — fires synchronously when any agent (lead or teammate) calls `TaskCreate`. Blocking: a non-zero exit halts task creation and surfaces the rejection reason to the calling model.

**Files**: `global/hooks/task-created-validator.sh`, `global/hooks/task-created-validator.ps1`

**Rules enforced**:
1. **Description length**: trimmed description must be at least 20 characters.
2. **Acceptance criteria**: description must contain at least one `- [ ]` markdown checkbox marker.

**Logic**:
1. Read JSON from stdin. If empty, fail open (nothing to validate).
2. Extract description from one of `tool_input.description`, `description`, or `task.description` — supports `jq` first, falls back to `python3` / `python`. If neither parser is available, fail open.
3. If no description field is present, fail open. If the field is present but fails either rule, exit 2 with a guidance message on stderr.

**Decision control**: Uses **exit code only** (not JSON `permissionDecision`):

| Exit Code | Effect |
|-----------|--------|
| `0` | Approve task creation |
| `2` | Block creation — stderr message sent as feedback to the model |

**Fail policy**: Fail-open on missing field, missing JSON parser, or unparseable input. Fail-closed only when the description is present and demonstrably violates a rule. The rationale matches `merge-gate-guard`: a tooling gap should not permanently block legitimate work.

**Behavior**:
- Returns exit code 0 on approval, exit code 2 on rejection with a stderr message naming the failed rule
- Reads JSON from stdin via `jq` or `python` (no JSON parser → fail-open)
- Timeout: 5 seconds
- Cross-platform: `task-created-validator.sh` and `task-created-validator.ps1`

**Configuration**:
```json
{
  "type": "command",
  "command": "~/.claude/hooks/task-created-validator.sh",
  "timeout": 5
}
```

**Sample input** (JSON via stdin):
```json
{
  "session_id": "abc123",
  "hook_event_name": "TaskCreated",
  "tool_input": {
    "subject": "Implement validation",
    "description": "Add input validation to the user form.\n\nAcceptance:\n- [ ] Empty fields rejected\n- [ ] Email format validated"
  }
}
```

**Sample rejection** (stderr, exit 2):
```
TaskCreated rejected: description must be at least 20 characters (got 12). Add scope, context, and acceptance criteria.
```

```
TaskCreated rejected: description must contain at least one '- [ ]' checkbox marker for acceptance criteria.
```

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

## Git Hooks: Pre-push Protected Branch Guard

*Prevent accidental pushes to main or develop — requires pull request workflow for protected branches.*

> **Note**: This is a standard git hook (`.git/hooks/pre-push`), not a Claude Code event hook. It runs whenever `git push` is executed, regardless of whether Claude Code is active.

**Purpose**: Block direct pushes to protected branches (`main`, `develop`)

**Install**: `./hooks/install-hooks.sh` (or `.\hooks\install-hooks.ps1` on Windows)

**Protected branches**: `main`, `develop`

**How it works**:
1. Git invokes the hook before pushing, passing remote info via stdin
2. The hook extracts the target branch from each ref being pushed
3. If the target branch matches a protected branch, the push is blocked with an error message
4. The error message guides the user to use the feature-branch + pull request workflow

**Behavior**:
- Exits with code 1 to block the push when targeting a protected branch
- Exits with code 0 to allow the push for non-protected branches
- Bypass: `git push --no-verify` (forbidden by project policy)

**Cross-platform**:

| File | Runtime |
|------|---------|
| `hooks/pre-push` | bash |
| `hooks/pre-push.ps1` | PowerShell 7+ |

---

## References

- [Claude Code Hooks Official Documentation](https://code.claude.com/docs/en/hooks)
- [Settings Official Documentation](https://code.claude.com/docs/en/settings)
