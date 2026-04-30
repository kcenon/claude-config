# Design Proposal: PermissionRequest / PermissionDenied Hooks

> **Status**: Proposal (no implementation)
> **Audience**: claude-config maintainers
> **Spec source**: <https://code.claude.com/docs/en/hooks>

## Background

Claude Code's hook spec defines two events that fire around the permission system:

| Event | Fires when | Matcher |
|-------|------------|---------|
| `PermissionRequest` | The harness is about to prompt the user to allow a tool call | Tool name |
| `PermissionDenied` | The user denied a permission prompt (or a `permissions.deny` rule rejected the call) | Tool name |

Per the official input schema, both events deliver the same payload to the hook:

```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "..." },
  "permission_suggestions": [ { "behavior": "allow", "rule": "..." } ]
}
```

`tool_input` is the full pending invocation. `permission_suggestions` is the harness's pre-computed set of rules that, if added to `permissions.allow`, would let the call through next time.

claude-config registers neither event. It ships a rich `PreToolUse` surface (`dangerous-command-guard.sh`, `sensitive-file-guard.sh`, `commit-message-guard.sh`) but no observation of the permission flow itself.

## Use Cases

| # | Use case | Event needed | Output |
|---|----------|--------------|--------|
| 1 | Audit trail of denied tool calls (security observation) | `PermissionDenied` | append to `~/.claude/logs/permission-denials.jsonl` |
| 2 | Build a denial-pattern dataset for tightening `permissions.deny` rules over time | `PermissionDenied` | offline analysis of the JSONL log |
| 3 | Auto-suggest `permissions.allow` additions when the user repeatedly approves the same denied call | `PermissionRequest` + `PermissionDenied` correlation | summary report (manual review, never auto-write) |

(1) and (2) are the primary motivations. (3) is exploratory — it depends on (1)/(2) being shipped first.

## Proposed Hook Scripts

| Script | Path | Event | Behavior |
|--------|------|-------|----------|
| `permission-denial-logger.sh` | `global/hooks/permission-denial-logger.sh` | `PermissionDenied` | Append redacted JSON line to `~/.claude/logs/permission-denials.jsonl`; exit 0 |
| `permission-denial-logger.ps1` | `global/hooks/permission-denial-logger.ps1` | `PermissionDenied` | PowerShell pair (mandatory per `docs/CLAUDE_DOCKER_CONTRACT.md` invariant #3) |

The pair is silent on the request side; only denials are logged. `PermissionRequest` instrumentation is deferred to a follow-up if denial volume justifies it.

### Log Line Schema

```json
{
  "ts": "2026-04-30T12:34:56+09:00",
  "session_id": "...",
  "tool_name": "Bash",
  "tool_input_redacted": { "command": "git push <REDACTED>" },
  "permission_suggestions": [ ... ]
}
```

Redaction reuses the regex set already used by `global/hooks/session-logger.sh` so secrets in `tool_input` (env vars, tokens, file paths under `~/.ssh/`, etc.) are scrubbed before disk write.

## Integration Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Event volume — every prompt fires the hook | Medium | Log denials only; tail-rotate `permission-denials.jsonl` at 10 MB |
| `tool_input` may contain secrets | High | Reuse `session-logger.sh` redaction; never log raw `tool_input` |
| Hook latency adds to permission prompt delay | Low | Append-only log write is sub-millisecond; no network call |
| Scope creep: hook auto-modifies `settings.json` | High | **Out of scope.** The hook MUST NOT write to `settings.json`. Suggestions are surfaced offline only. |
| Privacy — the log persists denial patterns | Medium | Document in `global/hooks/known-issues.json`; user can disable via `CLAUDE_PERMISSION_LOGGER=0` |

## Out of Scope

- Implementation. If approved, the implementer should open an issue using the `issue-create` skill referencing this proposal.
- Auto-tuning of `permissions.allow` / `permissions.deny`. This proposal logs only; rule changes remain a manual review step.
- A dashboard or analyzer for the JSONL log. That belongs in a follow-up proposal once data exists.

## Decision Matrix

| Option | Risk | Value | Verdict |
|--------|------|-------|---------|
| **A. Implement denial logger only** | Low (append-only, redacted) | High (audit + tuning data) | **Recommended (conditional)** |
| B. Implement both `PermissionRequest` and `PermissionDenied` | Medium (volume) | Medium (only marginal gain over A) | Defer until A produces data |
| C. Do nothing | None | None | Not recommended — leaves audit gap |

### Recommendation

**Conditional yes for Option A.** Proceed if and only if:

1. `session-logger.sh`'s redaction regex is reviewed against `tool_input` (richer than the bash surface it was built for).
2. A `CLAUDE_PERMISSION_LOGGER=0` opt-out is documented.
3. The follow-up issue references this proposal and the redaction review.

If (1) or (2) fail, defer until redaction is hardened separately.

---
*Version 1.0 (2026-04-30). Proposal for review by claude-config maintainers.*
