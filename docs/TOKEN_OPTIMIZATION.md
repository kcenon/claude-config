# Token Optimization Guide

> **Version**: 2.1.0
> **Last Updated**: 2026-02-03
> **Purpose**: Reduce token usage through official and experimental methods

## Official Token Optimization Methods

These methods are **officially supported** by Claude Code and recommended for all users:

### 1. Use `/clear` Between Unrelated Tasks

Reset conversation context when switching tasks:

```
/clear
```

This prevents context accumulation from previous tasks.

### 2. Move Domain Knowledge to Skills

Skills (`.claude/skills/`) load on-demand when invoked:

```
.claude/skills/
├── coding-guidelines/SKILL.md    # Loads when invoked
├── security-audit/SKILL.md       # Loads when invoked
└── api-design/SKILL.md           # Loads when invoked
```

### 3. Delegate to Subagents

Subagents run with separate context, reducing main conversation load:

```markdown
Use the Task tool to investigate the authentication system.
```

### 4. Offload Validation to Hooks

Move repetitive validation to hooks instead of conversation context:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "validate-command.sh" }]
    }]
  }
}
```

### 5. Write Specific Prompts

Specific prompts require less context disambiguation:

```markdown
# Good - Specific
Fix the null pointer exception in src/auth/login.ts:42

# Bad - Vague (requires more context)
Fix the bug in the login system
```

### 6. Use `permissions.deny` for Security

Block access to unnecessary files via official settings:

```json
{
  "permissions": {
    "deny": [
      "Read(**/node_modules/**)",
      "Read(**/dist/**)",
      "Read(**/build/**)"
    ]
  }
}
```

---

## Experimental Methods (Not Official)

The following methods use features that are **NOT officially supported**:

## Important Notice: .claudeignore Status

**WARNING**: `.claudeignore` is **NOT an official Claude Code feature**.

- **GitHub Issue**: [#579 - .claudeignore feature request](https://github.com/anthropics/claude-code/issues/579)
- **Status**: Feature is still being developed
- **Behavior**: May work in some versions but is not guaranteed

### Official Alternative: permissions.deny

For **security-related file exclusions**, use the official `permissions.deny` in `settings.json`:

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(**/secrets/**)",
      "Read(**/*.pem)",
      "Read(**/*.key)"
    ]
  }
}
```

**Note**: Path rules in `permissions.deny` are designed for **security** (blocking access to sensitive files), not for **token optimization**. Files blocked by `permissions.deny` are excluded from file discovery and search results. A rule that is a bare tool name is different: it removes that tool's definition from every request (see [Unused Tool Definitions](#unused-tool-definitions)).

### Migration Strategy

This project has migrated security-related exclusions to `settings.json`:
- `global/settings.json` - Global security rules
- `project/.claude/settings.json` - Project-specific security rules

`.claudeignore` files are now **deprecated** but retained for potential token optimization if the feature becomes official.

---

## Overview

This guide explains how `claude-config` optimizes token usage through `.claudeignore` files (deprecated) and `permissions.deny` (official), reducing initial session costs from ~50,000 tokens to ~15,000-20,000 tokens.

## Problem Statement

### Before Optimization

Without `.claudeignore` files, Claude Code loads:

| Category | Token Usage | Needed? |
|----------|-------------|---------|
| Core configuration | ~5,000 | ✅ Always |
| Reference documents | ~18,000 | ❌ On demand only |
| .npm-cache | ~8,000 | ❌ Duplicate content |
| Plugin marketplace | ~15,000 | ❌ Rarely used |
| Session memory | ~5,000 | ❌ Past conversations |
| Commands/Skills | ~10,000 | ❌ Load when invoked |
| **Total** | **~61,000** | Only ~8% needed |

### Impact

- **High API costs**: Every session wastes ~46,000 tokens ($0.046-$0.138 per session)
- **Slow startup**: Large context takes longer to process
- **Context pollution**: Rarely-used content occupies valuable context window
- **No on-demand loading**: Reference materials loaded even when unused

## Solution: Layered Approach

### Strategy

This project uses a layered approach for file exclusion:

1. **`permissions.deny` (Official)**: Security-focused file blocking
   - Blocks access to sensitive files (.env, secrets, credentials)
   - Officially supported by Claude Code
   - Prevents both reading and context inclusion

2. **`.claudeignore` (Deprecated/Experimental)**: Token optimization
   - May reduce token usage by excluding large files
   - **Not officially supported** - behavior may change
   - Retained for potential future support

### What to Exclude

1. **Reference documents**: Load only when explicitly needed
2. **Cache directories**: Exclude duplicate/generated content
3. **Plugin marketplace**: Very large, rarely accessed
4. **Session memory**: Past conversations not needed in new sessions
5. **Commands/Skills**: Auto-loaded when invoked

### Implementation

Three `.claudeignore` files optimize different scopes:

#### 1. Global Configuration (`global/.claudeignore`)

Excludes user-specific content:

```gitignore
# Session memory (past conversations)
projects/*/session-memory/

# Plugin cache
plugins/cache/

# Backups
backup_*/

# Plugin marketplace (very large)
plugins/marketplaces/

# Plans
plans/

# Commands (load when invoked)
commands/

# Skills (load when invoked)
skills/
```

**Token savings**: ~37,000 tokens (65%)

#### 2. Project Configuration (`project/.claudeignore`)

Excludes project-specific unnecessary content:

```gitignore
# NPM cache (duplicate files)
.npm-cache/

# Reference documents (load on demand)
reference/          # on-demand docs, relocated out of rules/ (issue #714)
skills/*/reference/

# Agents (load when needed)
agents/

# Settings files (user-specific)
settings.json
settings.local.json

# Documentation files
README.md
README.ko.md
```

**Token savings**: ~38,500 tokens (68%)

#### 3. Plugin Configuration (`plugin/.claudeignore`)

Excludes plugin development artifacts:

```gitignore
# NPM cache
.npm-cache/

# Node modules
node_modules/

# Build outputs
dist/
build/

# Settings
settings.json
.env

# Documentation
README.md
docs/
```

**Token savings**: ~17,500 tokens (60%)

## After Optimization

### Token Usage Breakdown

| Category | Before | After | Savings |
|----------|--------|-------|---------|
| Core configuration | ~5,000 | ~5,000 | 0 |
| Reference documents | ~18,000 | 0 | 18,000 |
| .npm-cache | ~8,000 | 0 | 8,000 |
| Plugin marketplace | ~15,000 | 0 | 15,000 |
| Session memory | ~5,000 | 0 | 5,000 |
| Commands/Skills | ~10,000 | 0 | 10,000 |
| **Total** | **~61,000** | **~5,000** | **~56,000 (92%)** |

### Real-World Results

Measured on claude-config project (2026-03-21):

| Metric | Before (no frontmatter) | After (`alwaysApply: false`) | Improvement |
|--------|-------------------------|------------------------------|-------------|
| Always-loaded rules | 11 files, ~105KB (~26,200 tokens) | 5 files, ~4KB (~1,010 tokens) | **96% reduction** |
| Initial load (rules + config) | ~122KB (~30,500 tokens) | ~17KB (~4,300 tokens) | **86% reduction** |
| Conditional rules | 0 files | 28 files (~208KB, on demand) | Loaded only when relevant |

**Key finding**: `paths` frontmatter alone does NOT prevent loading. `alwaysApply: false` is required alongside `paths` for conditional loading to work.

### Re-measured 2026-07-26 (#880)

The 2026-03-21 figures above had drifted. Five rule files carried
`alwaysApply: false` with no `paths:` trigger (or no frontmatter at all), which
the loader reads as "no condition" rather than "off" — so they had silently
rejoined the always-loaded set.

| Metric | Before #880 | After #880 |
|--------|-------------|------------|
| Always-loaded rules | 11 files, ~25KB (~6,496 est. tokens) | 6 files, ~10KB (~2,516 est. tokens) |
| Conditional rules | 21 files | 26 files (~194KB, on demand) |

**Corollary to the key finding**: `alwaysApply: false` is not an off switch on its
own. The loader gates a rule file solely on its `paths:` globs, so each of these
loads unconditionally:

| Frontmatter | Effect |
|-------------|--------|
| `alwaysApply: false`, no `paths:` | loads always — no condition to gate on |
| no frontmatter at all | loads always |
| `paths: ["**/*"]` | loads always — catch-all matches every file |
| `globs:` instead of `paths:` | loads always — key is not read |

`scripts/validate-rule-frontmatter.sh` enforces this contract in CI
(`.github/workflows/validate-rule-frontmatter.yml`).

## Using Reference Documents

Reference documents are excluded by default but easily accessible when needed.

### Method 1: Explicit File Path

```markdown
Can you review the label definitions in .claude/reference/workflow/label-definitions.md?
```

Claude Code will load the specific file when you reference it.

### Method 2: @load Directive

```markdown
@load: reference/label-definitions, reference/automation-patterns

Help me set up issue labels.
```

Load multiple reference files at once.

### Method 3: Ask to Load

```markdown
I need help with GitHub issue labeling. Please load the relevant reference documentation.
```

Claude Code will identify and load appropriate reference files.

## File-by-File Token Estimation

### Reference Documents

| File | Tokens | Purpose |
|------|--------|---------|
| `.claude/reference/workflow/label-definitions.md` | ~4,000 | GitHub label standards |
| `.claude/reference/workflow/automation-patterns.md` | ~6,000 | GitHub Actions, gh CLI |
| `.claude/reference/workflow/issue-examples.md` | ~8,000 | Issue splitting, templates |
| **Total** | **~18,000** | Load on demand only |

### Cache Directories

| Directory | Tokens | Why Excluded |
|-----------|--------|--------------|
| `.npm-cache/` | ~8,000 | Duplicate package files |
| `plugins/cache/` | ~3,000 | Temporary plugin data |
| **Total** | **~11,000** | Unnecessary duplicates |

### Plugin Marketplace

| Component | Tokens | Why Excluded |
|-----------|--------|--------------|
| Official plugins | ~10,000 | Large, rarely accessed |
| External plugins | ~5,000 | Third-party code |
| **Total** | **~15,000** | Not needed in sessions |

## Rollback Instructions

If you encounter issues or need all content loaded:

### Option 1: Modify permissions.deny

Edit `settings.json` to remove or comment out specific deny rules:

```json
{
  "permissions": {
    "deny": [
      // "Read(./.env)"  // Commented out to allow access
    ]
  }
}
```

### Option 2: Delete .claudeignore Files (Deprecated)

```bash
rm global/.claudeignore
rm project/.claudeignore
rm plugin/.claudeignore
```

Restart your session - all content will load.

### Option 2: Temporary Override

For a single session, rename the files:

```bash
mv global/.claudeignore global/.claudeignore.bak
```

Restore after session:

```bash
mv global/.claudeignore.bak global/.claudeignore
```

### Option 3: Selective Re-enabling

Comment out specific patterns in `.claudeignore`:

```gitignore
# Temporarily re-enable reference docs
# reference/
```

## Troubleshooting

### Issue: Missing Information

**Symptom**: Claude Code doesn't have context it needs.

**Solution**: Reference the specific file or use `@load` directive:

```markdown
@load: reference/label-definitions

Help me with GitHub labels.
```

### Issue: Slower Responses

**Symptom**: Claude Code takes longer to respond.

**Solution**: You may have loaded too much content. Restart session to reset context.

### Issue: No Token Savings

**Symptom**: Token usage still high after installing `.claudeignore`.

**Solution**:
1. Verify `.claudeignore` files exist: `ls -la {global,project,plugin}/.claudeignore`
2. Check file contents for syntax errors
3. Restart Claude Code session
4. Use `/token-usage` to verify current usage

## Tier Preset Impact

Skills whose `SKILL.md` body exceeds 5 KB declare tier presets in their
frontmatter. The caller selects a tier at invocation time to dial the context
budget up or down for the same workflow, trading reference depth and
verification cost against tokens loaded.

> **Authority**: `global/skills/_policy.md` §Tier Preset Schema defines the
> canonical field names and semantics. This section reports empirical impact.

### Overview

| Tier | `ref_docs` | `deep_checks` | `max_files` |
|------|------------|---------------|-------------|
| `light` | None — SKILL.md body only | `false` | Narrow |
| `standard` | Baseline reference set | `false` | Default |
| `deep` | Full reference set | `true` | Expanded |

`ref_docs` keys are skill-defined aliases (`core`, `advanced`, `batch`, etc.)
resolved against the skill's own `reference/` directory. See `_policy.md` for
the authoritative schema.

### Baseline Measurements

Measured against `pr-work` at full-body load (issue #401 figures):

| Tier | Tokens | Delta vs. `standard` |
|------|--------|----------------------|
| `light` | ~1,500 | **−72%** |
| `standard` | ~5,350 | baseline |
| `deep` | ~6,530 | **+22%** |

Frontmatter tier-selection logic adds a one-time **+150–300 tokens** per
tiered skill, independent of invocation tier.

**Weighted session average**: **−39%** token reduction, using the projected
invocation mix:

| Tier | Share |
|------|-------|
| `light` | 40% |
| `standard` | 50% |
| `deep` | 10% |

### Default Tier Rationale

`default_tier: standard` preserves existing behavior byte-for-byte. Current
workflows need no opt-out — they continue to load the baseline reference set
as before. Callers explicitly opt into `light` for quick, scoped tasks or
`deep` when exhaustive checks are warranted.

### Invocation

Pass the tier as a flag when invoking a tiered skill:

```
/<skill> --tier=light
/<skill> --tier=standard
/<skill> --tier=deep
```

Omitting `--tier` selects the skill's declared `default_tier`. Unknown tier
values fall back to `default_tier` with a warning.

### Tiered Skills

- `pr-work`
- `issue-work`
- `fleet-orchestrator`
- `harness`
- `release`

Additional skills will adopt the schema as their bodies cross the 5 KB
threshold or as workflow demand justifies differentiated loading.

### Follow-up

A/B measurement is scheduled post-rollout (tracked in
[issue #401](https://github.com/kcenon/claude-config/issues/401)):

- 20 test runs before/after to validate the −39% weighted projection
- Dedicated light-tier PR review test case to verify the target token budget
- Re-measurement of `pr-work` and `issue-work` under realistic workloads

Results will be appended to this section once collected.

---

## Harness Routing Audit

Harness-layer CLAUDE.md files are loaded on every session regardless of task, so procedural content paid for once lives forever in that always-on budget. `scripts/validate_skills.sh` enforces a routing-only discipline on the three harness files.

### Audited files

- `global/CLAUDE.md`
- `project/CLAUDE.md`
- `enterprise/CLAUDE.md`

### Classification

For each non-blank, non-heading line outside the footer (first `---`):

| Line shape | Counted as |
|------------|-----------|
| `- ...`, `* ...`, `+ ...` (bullet) | routing |
| `\| ...` (table row) | routing |
| `@./...` (import directive) | routing |
| `> ...` (blockquote) | routing |
| Any line inside a heading whose text matches `[Ii]nvariant` | routing/invariant |
| Anything else (free-form sentences) | prose |

### Threshold

Fail the build if `prose / (routing + prose) > AUDIT_PROSE_RATIO` (default `0.30`).

```bash
# Override for experimentation
AUDIT_PROSE_RATIO=0.40 ./scripts/validate_skills.sh
```

Current measurements (post-harness-diet):

| File | Prose | Routing/Invariant | Ratio |
|------|-------|-------------------|-------|
| `global/CLAUDE.md` | 2 | 11 | 15.4% |
| `project/CLAUDE.md` | 9 | 26 | 25.7% |
| `enterprise/CLAUDE.md` | 0 | 3 | 0.0% |

### Intent

- **Keep** short always-on invariants inside an `## Always-on Invariants` heading — they count as routing regardless of shape, because the block's purpose is guardrails.
- **Move** procedural prose (how-to, workflow detail) into `docs/**`, `global/skills/**/SKILL.md`, or project-level `rules/**/*.md`.
- **Prefer** a routing bullet that points to the existing file over a prose paragraph that duplicates it.

### Related frontmatter drift checks

The same validator flags inconsistency between skill frontmatter contracts and body:

- `max_iterations` or `halt_condition` declared → body must mention `loop|retry|iteration|poll`
- `loop_safe: false` declared → body must document side effects / non-idempotent behavior

Failures here are warnings (non-fatal) to avoid blocking incremental skill authoring, but CI surfaces the count.

---

## Best Practices

### 1. Start Lean

Always start sessions with optimized context:
- Core configuration only (~5,000 tokens)
- Load reference docs when needed

### 2. Use @load Sparingly

Only load reference documents when actively using them:

```markdown
# Good: Load when needed
@load: reference/label-definitions
Help me create issue labels.

# Bad: Load everything upfront
@load: reference/*
Generic question about the project.
```

### 3. Regular Cleanup

Periodically remove unnecessary files:

```bash
# Remove .npm-cache
rm -rf .npm-cache/

# Remove old backups
rm -rf backup_*/
```

### 4. Monitor Token Usage

Track token consumption:
- Use `/token-usage` command
- Check Claude Code UI
- Review API billing dashboard

## Cost Savings Calculator

### Individual Developer

| Sessions/Month | Before | After | Monthly Savings |
|----------------|--------|-------|-----------------|
| 50 | $6.90 | $2.25 | **$4.65** |
| 100 | $13.80 | $4.50 | **$9.30** |
| 200 | $27.60 | $9.00 | **$18.60** |

### Team (5 Developers)

| Sessions/Month/Person | Before | After | Monthly Savings |
|-----------------------|--------|-------|-----------------|
| 100 | $69.00 | $22.50 | **$46.50** |
| 200 | $138.00 | $45.00 | **$93.00** |

### Enterprise (50 Developers)

| Sessions/Month/Person | Before | After | Monthly Savings |
|-----------------------|--------|-------|-----------------|
| 200 | $1,380.00 | $450.00 | **$930.00** |
| 500 | $3,450.00 | $1,125.00 | **$2,325.00** |

*Assumes $0.138 per 1,000 input tokens (Claude Sonnet 4.5 pricing)*

## Implementation Checklist

When installing `claude-config`:

- [ ] Run `./bootstrap.sh` to install `.claudeignore` files
- [ ] Verify `.claudeignore` files exist in global/, project/, plugin/
- [ ] Remove existing `.npm-cache/` directories
- [ ] Restart Claude Code session
- [ ] Verify token reduction using `/token-usage`
- [ ] Bookmark this guide for reference document loading

## FAQ

### Q: Is .claudeignore an official Claude Code feature?

**A**: **No.** As of February 2026, `.claudeignore` is not officially supported. See [GitHub Issue #579](https://github.com/anthropics/claude-code/issues/579). Use `permissions.deny` in `settings.json` for security-related file exclusions.

### Q: What's the difference between permissions.deny and .claudeignore?

**A**:
- `permissions.deny`: Official feature for **security** - blocks tool access to sensitive files
- `.claudeignore`: Experimental/unsupported - may reduce **token usage** but behavior is not guaranteed

### Q: Will this break my workflow?

**A**: No. Core functionality remains unchanged. Reference documents load on-demand when you explicitly reference them.

### Q: How do I access excluded content?

**A**: Use explicit file paths, `@load` directive, or ask Claude to load relevant documentation.

### Q: Can I customize .claudeignore?

**A**: Yes, but remember it's deprecated. Edit the files to add/remove patterns. Follow gitignore syntax.

### Q: What if I need everything loaded?

**A**: Remove deny rules from `settings.json` or delete `.claudeignore` files and restart your session.

### Q: Does this affect code generation quality?

**A**: No. Core rules and guidelines remain loaded. Reference materials load when needed.

## Measuring Token Load from Transcripts

`scripts/token-audit/token_audit.py` reads the transcripts that Claude Code
keeps under `~/.claude/projects/` and prints aggregates only (#999). Run it
before a configuration change to record a baseline, then again over a window
after the change.

```bash
python3 scripts/token-audit/token_audit.py --project <folder>
python3 scripts/token-audit/token_audit.py --since 2026-11-01T00:00:00Z --json
python3 scripts/token-audit/token_audit.py --session <id> --session <id> --json
```

`--session` (repeatable) counts only the named sessions with their subagents
and workflows; `--exclude-session` leaves one out and wins over `--session`.

What it reports, separately for main, subagent and workflow transcripts:

- Tokens by kind: cache read, cache write (1h and 5m), output (with thinking)
  and uncached input, counted once per API request.
- A cache read is the context a request reads again, so the total grows with
  both the number of requests and the context size of each request.
- First-request context, and the prefix share: the smallest context of each
  transcript times its request count, over all cached input.
- Requests and cached input by context-size bucket.
- Per tool: calls, result characters, errors and residency. Residency is the
  result characters times the number of later requests in the same transcript
  before the next compaction.
- Path-triggered rules: injections, characters and residency per rule file.
- Reads by subagents: characters, the share that the parent session also read,
  and the extra characters when sibling subagents read the same file.
- Compactions by trigger, and by cause with the median context before each:
  `manual`, `idle` and `threshold`. The transcript does not say which kind
  an automatic compaction was. Idle compaction runs after about an hour
  without a request, so an automatic compaction 30 minutes or more after the
  last message counts as `idle` and any other as `threshold`. The `auto`
  trigger count holds both.
- Re-reads after a compaction: Reads of the same file and range (`offset`,
  `limit`) as an earlier Read in the same transcript, with a compaction
  between them and no `Edit`, `Write` or `NotebookEdit` of the file. Both
  results must be longer than 200 characters, which leaves out the one-line
  notice a Read returns for a file it already showed unchanged. Reads in
  requests outside the window or copied from a resumed session count on
  neither side.

Characters are not converted to tokens, because the ratio depends on language
and content. The output holds no prompt, tool result, file content or subagent
task description; file paths of sibling reads appear only with `--show-paths`.

A comparison needs history, so both profiles keep transcripts for 90 days
(`cleanupPeriodDays`). On the machine where this was measured, 30 days of
transcripts took about 1.3 GB.

## Unused Tool Definitions

Every request carries the definition of each tool the session can call. On
Claude Code 2.1.318 an interactive main session sent 47 definitions, about
184,000 characters of JSON. A bare tool name in `permissions.deny` removes
that tool's definition from the requests that follow, while a scoped rule
such as `Bash(rm *)` only blocks calls
([permissions](https://code.claude.com/docs/en/permissions.md),
[prompt caching](https://code.claude.com/docs/en/prompt-caching.md)).

Both profiles deny the tools below (#1000). None of them was called in 30
days on the measuring machine. Sizes are from an interactive main session on
2.1.318 and add up to about 58,000 characters.

| Entry | Characters | What stops working |
|---|---|---|
| `DesignSync` | 10,868 | `/design-sync` with claude.ai/design |
| `SendToProject`, `SendToProjectContext` | 7,177 and 805 | `/send-to-project` |
| `RemoteTrigger` | 4,151 | Creating, running and inspecting cloud routines from a session |
| `ArtifactData`, `ArtifactComments` | 12,526 and 7,527 | Reading and writing an artifact's database and comment threads; publishing with `Artifact` still works |
| `SendFeedback` | 5,618 | Feedback drafts about Claude Code |
| `PushNotification` | 1,811 | Notifications that Claude sends on its own to the desktop or a phone |
| `mcp__claude_ai_Claude_Docs` | 6,001 (8 tools) | The claude.ai Claude Docs connector |
| `mcp__claude_ai_Google_Drive` | 1,552 (2 tools) | The claude.ai Google Drive connector |

Measured effect, with print-mode sessions on 2.1.318 started from an empty
folder with and without these entries (`claude -p --settings <file>`):

| Request | Without | With |
|---|---|---|
| Main: tool definitions | 32, 93,060 characters | 24, 72,152 characters |
| Main: first request | 50,138 tokens | 41,651 tokens |
| General-purpose subagent: tool definitions | 31, 84,074 characters | 23, 63,166 characters |
| General-purpose subagent: first request | 42,330 tokens | 33,843 tokens |

- Print mode does not load `SendToProject`, `SendToProjectContext`,
  `ArtifactData`, `ArtifactComments`, `SendFeedback` or the Google Drive
  connector, so those entries were not observed there. Check them with
  `/context` in an interactive session.
- Denying a connector removes its tools but not its server instructions,
  which still reach the model as an attachment (1,893 characters for Claude
  Docs). `disableClaudeAiConnectors` turns off claude.ai connectors as a
  whole; the profiles do not set it, because it would also turn off
  connectors that a machine does use.
- The tool set changes between versions (2.1.316 sent 45 definitions), so
  repeat the comparison on the version in use. The `api-request-shape`
  records in a transcript hold the tool array each session sent
  (`shape.tools`), and `token_audit.py --since` compares first-request
  context before and after a change.

To use one of these tools again, remove its entry from both
`global/settings.json` and `global/settings.windows.json` and reinstall.
There is no machine-local override: `permissions` is an installer policy key,
so a reinstall replaces the whole block in `~/.claude/settings.json`, and a
deny rule cannot be lifted by an `allow` rule in another scope.

## Support

For issues or questions:

- **GitHub Issues**: https://github.com/kcenon/claude-config/issues
- **Documentation**: https://github.com/kcenon/claude-config
- **Discussion**: GitHub Discussions

---

*Token optimization: Because every token counts.*
