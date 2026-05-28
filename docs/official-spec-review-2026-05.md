# Official Spec Review — 2026-05-29

Re-validation of `claude-config` against the **current Claude Code official documentation**
(`docs.claude.com/en/docs/claude-code/{settings,hooks,skills,sub-agents}`), fetched and
cross-checked on 2026-05-29.

## Method

1. Inventoried every Claude Code asset the repo ships: `settings.json` top-level keys,
   hook events, skill / agent / command frontmatter fields, plugin manifests.
2. Fetched the live official docs and extracted the authoritative field/event lists.
3. Cross-checked agent output against the primary source (the docs themselves) to catch
   model hallucination — one was found and corrected (see "Corrections" below).
4. Classified each finding as **conformant**, **drift (fix)**, **opportunity (backlog)**,
   or **intentional non-standard extension (no action)**.

## Executive Summary

`claude-config` tracks the latest official schema **very closely**. No deprecated keys are
in use and no broken event wiring was found. The repo is unusually disciplined: it explicitly
documents which of its frontmatter fields are *advisory metadata not enforced by the harness*
(`global/skills/_policy.md:40`) and ships its own `agent-frontmatter-spec.md` that mirrors the
official agent field set exactly.

The single genuine drift is the `temperature` field on subagents, which is **not an official
field and is not even listed in the repo's own agent spec** — it is silently ignored by the
harness and duplicates the intent of the already-present `effort` field.

| Severity | Finding | Action |
|----------|---------|--------|
| **Drift** | `temperature` on all 8 project agents | Remove (this PR) |
| **Drift (docs)** | `keywords` / `applies_to` agent fields undocumented in repo's own spec | Document as non-standard extension (this PR) |
| **Opportunity** | 5 new hook events unused | Backlog |
| **Opportunity** | ~10 new `settings.json` keys unused | Backlog |
| **Housekeeping** | `harness_policies` custom key + expired P4 timeline | Note only (team decision) |
| **Conformant** | hook events, attribution, sandbox, skill advisory fields | No action |

## Corrections to Preliminary Analysis

- **`attribution` is an object, not a string.** The official schema defines
  `attribution: {commit, pr}` with empty strings hiding attribution. `claude-config`'s
  `{commit:"", pr:""}` is correct. (A first-pass agent claimed it had "changed to a string" —
  that was a hallucination, refuted against the live doc.)
- **`includeCoAuthoredBy` is deprecated** in favor of `attribution`. `claude-config` already
  uses `attribution` and does not set the deprecated key. Conformant.

## 1. Hooks — Conformant

All 18 hook events wired in `global/settings.json` and `global/settings.windows.json` are
present in the official hooks documentation:

`PreToolUse, PostToolUse, PostToolUseFailure, SessionStart, SessionEnd, UserPromptSubmit,
Stop, SubagentStart, SubagentStop, PreCompact, PostCompact, InstructionsLoaded, TaskCreated,
TaskCompleted, ConfigChange, TeammateIdle, WorktreeCreate, WorktreeRemove.`

The `async: true` and `timeout` handler fields are both officially supported. Every wired hook
has a matching script in `global/hooks/`, and every script is wired — no orphans.

### Unused official hook events (opportunity)

| Event | Possible use for this repo |
|-------|----------------------------|
| `FileChanged` | React to edits of `settings.json` / `SKILL.md` (live-validate frontmatter) |
| `PermissionRequest` | Audit/log permission escalations centrally |
| `Notification` | Surface long-running batch (`issue-work`/`pr-work`) completion |
| `CwdChanged` | Re-resolve project-scoped rules on directory switch |
| `Setup` | One-time `init`/`maintenance` provisioning (currently done by `bootstrap.sh`) |

## 2. settings.json — Conformant, with unused new keys

Every key in use is officially supported: `attribution, effortLevel, autoUpdatesChannel,
skipDangerousModePermissionPrompt, teammateMode, spinnerVerbs, alwaysThinkingEnabled,
includeGitInstructions, outputStyle, language, sandbox, statusLine, cleanupPeriodDays,
respectGitignore, env, permissions`.

### Unused official keys (opportunity)

`skillOverrides`, `skillListingBudgetFraction`, `maxSkillDescriptionChars`,
`disableSkillShellExecution`, `forceLoginMethod`, `enabledPlugins`, `disableAllHooks`,
`autoMemoryDirectory`, `model`, `agents`.

Of these, the skill-governance keys (`skillOverrides`, `maxSkillDescriptionChars`,
`disableSkillShellExecution`) are the most relevant to a config repo that ships many skills,
and are worth a dedicated follow-up evaluating whether to set policy defaults.

### Non-standard custom key (housekeeping)

`harness_policies` (in both `global/settings.json` and `global/settings.windows.json`) is **not
in the official schema**. Claude Code ignores unknown top-level keys, so there is no runtime
effect, but a strict `$schema` validator will flag it. Additionally, its P4 timeline values are
expired as of this review (`p4_freeze_until: 2026-05-20` < 2026-05-29). Recommendation: either
move P4 timeline state out of `settings.json` into a dedicated `harness_policies.json` read by
the P4 hooks, or prune the expired window. Left to the team that owns the P4 timeline rollout.

## 3. Skills — Conformant

Official frontmatter fields (`name, description, when_to_use, argument-hint, arguments,
disable-model-invocation, user-invocable, allowed-tools, disallowed-tools, model, effort,
context, agent, hooks, paths, shell`) are all respected. `disable-model-invocation: true` and
`user-invocable: false` — used widely across the `_internal` skills — are confirmed official.

The repo's many additional frontmatter fields (`loop_safe`, `halt_conditions`, `on_halt`,
`max_iterations`, `iso_class`, `tiers`, `default_tier`, `applies_at_or_above`, `severity`,
`finding_levels`) are **intentional advisory metadata**, explicitly documented as
"LLM-advisory metadata only — Claude Code does not enforce them at runtime"
(`global/skills/_policy.md:40`). **No action** — this is a deliberate, well-documented design.

## 4. Subagents — One drift, one doc gap

The repo's own `global/skills/_internal/harness/reference/agent-frontmatter-spec.md` correctly
mirrors the official field set: `name, description, tools, disallowedTools, model, maxTurns,
effort, background, permissionMode, memory, skills, mcpServers, hooks, isolation, color,
initialPrompt`.

### 4.1 Drift: `temperature` (FIX)

All 8 agents under `project/.claude/agents/` set `temperature` (0.1–0.5). This field is:

- **not** in the official subagent frontmatter spec,
- **not** in the repo's own `agent-frontmatter-spec.md`,
- silently ignored by Claude Code (subagents do not expose a sampling-temperature knob),
- redundant with `effort`, which every agent already sets and which *is* official.

Unlike the skill advisory fields, `temperature` cannot be honored even as prompt-level
self-regulation (it is a sampling parameter, not a behavior the model can emulate by reading
its own frontmatter). It is pure dead metadata. **Removed in this PR.**

### 4.2 Doc gap: `keywords` / `applies_to` (DOCUMENT)

Both fields appear on all 8 agents but are absent from `agent-frontmatter-spec.md`.
`docs/architecture-review-skills-rules.md:115` already notes `keywords` is "NOT officially
supported". These are non-standard advisory extensions (used by the repo's own routing/index
tooling, not the harness). To keep the spec honest and consistent with the skills `_policy.md`
pattern, a "Non-standard advisory extensions" section is added to `agent-frontmatter-spec.md`
in this PR. No change to the agent files for these two fields (they are intentional).

### 4.3 Unused official fields (opportunity)

Agents set none of `color`, `permissionMode`, `disallowedTools`. Adding `color` aids tmux
split-pane identification; `permissionMode: plan` or `acceptEdits` would make the
implementation-capable agents' trust level explicit rather than inherited. Backlog.

## 5. Plugins — Conformant

`plugin/.claude-plugin/plugin.json` (`minClaudeCodeVersion: 2.2.0`) and
`plugin-lite/.claude-plugin/plugin.json` (`2.0.0`) are well-formed. No schema issues found.

## Recommended Follow-ups (Backlog)

1. Evaluate skill-governance keys (`skillOverrides`, `maxSkillDescriptionChars`,
   `disableSkillShellExecution`) for policy defaults.
2. Resolve `harness_policies`: relocate out of `settings.json` or prune expired P4 window.
3. Consider adopting `FileChanged` to live-validate config frontmatter on edit.
4. Add `color` / explicit `permissionMode` to the 8 project agents.

---

*Generated by an official-spec re-validation pass. Source docs fetched 2026-05-29 from
`docs.claude.com/en/docs/claude-code/`.*
