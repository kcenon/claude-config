# Official Spec Re-Review -- 2026-05-29

Re-validation of `claude-config` against the **current Claude Code official documentation**,
fetched and cross-checked on 2026-05-29 from the **migrated** canonical host
`code.claude.com/docs/en/{hooks,settings,permissions,skills,sub-agents,slash-commands,plugins,
plugins-reference,plugin-marketplaces,mcp,memory,output-styles,statusline}`.

> **Supersedes**: `docs/official-spec-review-2026-05.md`. That earlier file fetched the **old**
> host (`docs.claude.com/en/docs/claude-code/`, which now 301-redirects) and consequently
> **undercounted the official surface** (it reported 18 hook events and ~10 unused settings keys;
> the live surface is ~30 events and ~94 keys). Treat the earlier file as historical and this
> file as the current ground truth until the next re-review.

## Method

1. Established ground truth by fetching the live official docs directly and extracting the
   authoritative event/key/field lists (host migration confirmed: `docs.claude.com/en/docs/
   claude-code/*` -> `code.claude.com/docs/en/*`, 301).
2. Ran a 12-dimension cross-check (24 sub-agents: per-dimension `review` then adversarial
   `verify`), each dimension re-fetching the live doc and re-reading the actual repo files.
3. Adversarially verified every candidate finding against both the live doc and the cited
   repo `file:line`, rejecting any claim that did not hold up (4 rejected).
4. Classified each confirmed finding as **drift** (conflicts with current official spec),
   **opportunity** (a new official feature the repo could adopt), **stale-doc** (the repo's own
   documentation now misrepresents the official surface), or **conformant** (matches spec /
   intentional documented extension).

## Executive Summary

The repo's **actual configuration remains structurally very conformant** to the current
official surface: all 19 wired hook events are official, no deprecated keys are in use, and
`attribution`, `skipDangerousModePermissionPrompt`, skill `allowed-tools`, and the agent
frontmatter (post-`temperature` removal, PR #662) all match the latest schema.

The dominant problem is **not** drift in the live config -- it is that the **official surface
moved and expanded** while the repo's **documentation and validation artifacts** did not keep
up. The single largest source of staleness is the superseded `official-spec-review-2026-05.md`,
which other repo docs cite as ground truth.

| Category | high | medium | low | info | total |
|----------|:----:|:------:|:---:|:----:|:-----:|
| **drift** (conflicts with current spec) | 4 | 2 | 5 | -- | **11** |
| **opportunity** (unadopted official feature) | 1 | 5 | 13 | 9 | **28** |
| **stale-doc** (repo doc misstates the surface) | 5 | 13 | 21 | 3 | **42** |
| **conformant** (verified match / intentional ext.) | -- | -- | -- | 39 | **39** |

Confirmed: 120. Rejected by adversarial verification: 4.

## How The Official Surface Changed Since The Prior Review

| Axis | Prior review assumed | Live (2026-05-29, code.claude.com) |
|------|----------------------|------------------------------------|
| Doc host | `docs.claude.com/en/docs/claude-code/` | `code.claude.com/docs/en/` (old 301-redirects) |
| Hook events | 18 | ~30 (new: `Setup`, `UserPromptExpansion`, `PermissionRequest`, `PermissionDenied`, `PostToolBatch`, `MessageDisplay`, `StopFailure`, `Elicitation`, `ElicitationResult`, `CwdChanged`, `FileChanged`) |
| Hook handler types | `command` only | 5: `command`, `http`, `mcp_tool`, `prompt`, `agent` (+ `if` conditional, `once`) |
| settings top-level keys | ~26 | ~94 (new incl. `ultracode`, `worktree`, `autoMemoryEnabled`, `autoMemoryDirectory`, `disableWorkflows`, `minimumVersion`, `claudeMd`, `claudeMdExcludes`, `subagentStatusLine`, ...) |
| Permission `defaultMode` | 4 (`default`, `acceptEdits`, `bypassPermissions`, `plan`) | 6 (adds `auto`, `dontAsk`) + `disableBypassPermissionsMode` / `disableAutoMode` hardening |
| Auto-memory path | cwd-encoded, per-worktree | git-repo-derived, **shared across worktrees**; configurable via `autoMemoryDirectory` |

## Corrections to Orchestrator-Level Ground Truth (Adversarial Verification Catches)

These two were initially suspected as drift but were **refuted** against the live doc + actual
files. Recording them so future reviews do not re-flag them:

1. **`TeamCreate` is NOT a phantom hook event -- it is a PreToolUse tool matcher.** `TeamCreate`
   is a real Claude Code tool; `global/settings.json:200` matches it under the official
   `PreToolUse` event so `team-limit-guard.sh` runs before the tool. Conformant.
2. **`skipDangerousModePermissionPrompt` is correctly top-level (NOT inside `permissions`).** The
   current settings schema places it at top level (sibling of `permissions`); the `/settings`
   page merely groups it in the permission-settings table for presentation. The repo's top-level
   placement in `global/settings.json:489` and `global/settings.windows.json:53` is correct, and
   because it lives in user-tier (global) settings rather than project settings, it is honored.

## Confirmed Drift (actionable)

| # | Sev | Dim | Drift | Location |
|---|:---:|-----|-------|----------|
| D1 | high | mcp | `.mcp.json` template ships **non-existent** `@anthropic/mcp-server-*` packages; breaks any consumer who copies it | `project/.mcp.json:9,13,21,29,37` |
| D2 | high | plugins | README install commands use **non-existent** flags `--source/--url/--subdir` and there is no `marketplace.json`, so the plugins are not installable as documented | `plugin/README.md:10-15`, `plugin-lite/README.md:19-21` |
| D3 | high | skills | strict skill schema rejects the repo's **own** `iso_class`/`safety_class`/`applies_at_or_above` extension fields, blocking the `p4_strict_schema` flip (internal contradiction) | `scripts/schemas/skill-md.schema.strict.json:8` vs `global/skills/_internal/pr-work/SKILL.md:27` |
| D4 | high | memory | memory-sync docs assume a cwd-encoded per-worktree path; official auto-memory is now git-repo-derived and shared across worktrees, so the user-facing migration instructions are wrong | `docs/MEMORY_MIGRATION.md:77`, `docs/MEMORY_SYNC.md:400` |
| D5 | med | settings/perms | local `settings-json.schema.json` lags official: `defaultMode` enum missing `auto`/`dontAsk`; hook handler `type` enum locked to `command`; permissions object missing `disableBypassPermissionsMode`/`disableAutoMode`/`additionalDirectories` | `scripts/schemas/settings-json.schema.json:29,54,25-37` |
| D6 | med | plugins | both manifests ship a non-official `compatibility.minClaudeCodeVersion` field (trips `--strict`); neither declares `$schema` | `plugin/.claude-plugin/plugin.json:12`, `plugin-lite/.claude-plugin/plugin.json:12` |
| D7 | med | skills | skill schemas mark `name` as required (official: optional, defaults to directory name); description `maxLength` 1024 vs official 1536 | `scripts/schemas/skill-md.schema.*.json` |
| D8 | med | hooks | `tool-failure-logger` header + `HOOKS.md` name a phantom event `ToolFailure` (actual wiring correctly uses `PostToolUseFailure`) | `global/hooks/tool-failure-logger.sh:4`, `HOOKS.md:1041,1572` |

## Opportunities (adopt new official features)

| Sev | Opportunity | Why it helps this repo |
|:---:|-------------|------------------------|
| high | `autoMemoryDirectory` replaces the Phase-6 symlink hack | removes the cwd-encoded-path enumeration problem, is robust to the git-repo-derived path change, and project/local rejection strengthens the threat model |
| med | `permissions.disableBypassPermissionsMode` / `disableAutoMode: "disable"` | a security-focused config currently leaves bypass reachable; this closes it |
| med | `minimumVersion` | turns the advisory `version-check.sh` into a hard guard against harnesses too old for the newer wired events |
| med | `worktree` settings object (`baseRef: develop`) | codifies the worktree fan-out conventions instead of relying on per-session defaults |
| med | MCP governance keys (`enableAllProjectMcpServers:false`, `enabledMcpjsonServers`, `managed-mcp.json`) | consistent with the repo's existing secret-blocking posture |
| low | hook `if` conditional + `prompt`/`agent` handler types | declarative scope-gating could replace shell command-substring gates |
| low | `FileChanged` (live-validate config), `PermissionRequest`/`PermissionDenied` (audit), `subagentStatusLine`, skill `disallowed-tools`/`arguments`, `claudeMdExcludes` | unused current official features that fit this repo |

## Stale-Doc Cluster (42; the dominant class)

- **`docs/official-spec-review-2026-05.md`** (the largest source): old host (`:4`, `:159`),
  "All 18 hook events" (`:49`; live ~30), "~10 unused keys" (`:34`, `:78-80`; live ~94), no MCP
  dimension, plugins wrongly classified "Conformant" (`:143-146`). Superseded by this file.
- **Residual old-host links (3)**: `README.md:14` claims "All references in this repo use the new
  URLs", contradicted by `official-spec-review-2026-05.md:4,159` and
  `global/skills/_internal/harness/reference/agent-frontmatter-spec.md:326` (missed by the
  Issue #336 migration sweep).
- **`COMPATIBILITY.md`**: Hook Event Types table lists 19 events and omits ~11 newer ones
  (`:25-49`); `ToolFailure` vs `PostToolUseFailure` mismatch (`:33`); labels `ENABLE_TOOL_SEARCH`
  / `MAX_MCP_OUTPUT_TOKENS` as "undocumented" though both are on the official MCP page (`:135`).
- **`README.md`**: "37 hook scripts" but `global/hooks/` ships 35 `.sh` / 35 `.ps1` (`:236`);
  directory tree lists a `project/.claude/commands/` subtree that does not exist (`:318-322`).
- **`agent-frontmatter-spec.md`**: omits `xhigh` effort level (`:81`); model-resolution env var
  `CLAUDE_MODEL` vs official `CLAUDE_CODE_SUBAGENT_MODEL` (`:89`).
- **`docs/CUSTOM_EXTENSIONS.md`**: classifies "Commands" as current official without noting the
  merge into skills (`:44`); says global commands install to `~/.claude/commands/` though the repo
  ships them as skills under `~/.claude/skills/_internal/` (`:325`).

> Lower-confidence (verify against the live memory doc before editing): memory import recursion
> depth, documented as "5 levels deep" (`README.md:1104`) vs a finding that the official limit is
> 4 hops. Depth limits are error-prone; confirm directly before changing user instructions.

## Conformance Highlights (no action)

- All 19 wired hook events are official; no phantom event keys.
- `attribution` is correctly an object `{commit, pr}`; deprecated `includeCoAuthoredBy` not used.
- Skills use `allowed-tools` (not `tools`); `disable-model-invocation` used correctly; `_policy.md`
  advisory-field separation is still accurate.
- `temperature` is absent from all 16 agent files (confirmed non-official); `keywords`/`applies_to`
  documented as non-standard advisory extensions.
- `outputStyle: Explanatory`, `statusLine` shape, and the `.mcp.json.example` transport model are
  all current-spec conformant.
- `harness_policies` remains a documented intentional custom key (top-level `additionalProperties`
  tolerates it).

## Remediation Roadmap

### Track A -- Stale-doc regeneration (this PR series, chosen)

1. Add this re-review as the new SSOT (this commit).
2. Mark `official-spec-review-2026-05.md` superseded and/or regenerate its host, event-count,
   key-count, and plugin sections against `code.claude.com`.
3. Fix the 3 residual old-host links; reconcile or soften the `README.md:14` claim.
4. Correct `COMPATIBILITY.md` (event table, `ToolFailure` row, MCP env-var labels).
5. Correct `README.md` ("37 hook scripts" -> 35; remove the non-existent commands subtree).
6. Correct `agent-frontmatter-spec.md` (host, `xhigh`, env var) and `CUSTOM_EXTENSIONS.md`.

### Track B -- High drift fixes (separate PRs, backlog)

D1 `.mcp.json` package names; D2 plugin install flow + `marketplace.json`; D3 strict-schema
`iso_class`; D4 memory-path docs.

### Track C -- Validation-schema sync (backlog)

D5 (settings schema enums/fields), D6 (plugin manifest `compatibility`/`$schema`), D7 (skill
schema `name`/`maxLength`), D8 (`ToolFailure` -> `PostToolUseFailure`).

### Track D -- Opportunity backlog (GitHub issues)

`autoMemoryDirectory`, permissions hardening, `minimumVersion`, `worktree`, MCP governance,
new hook handler types, unused events/fields.

---

*Official-spec re-validation pass. Source docs fetched 2026-05-29 from `code.claude.com/docs/en/`.
Method: 12-dimension review with per-dimension adversarial verification (24 sub-agents); every
finding cross-checked against the live doc and the cited repo `file:line`.*
