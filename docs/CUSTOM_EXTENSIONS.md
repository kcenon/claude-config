# Custom Extensions vs Official Features

> ⚠️ **IMPORTANT NOTICE**
>
> This configuration contains both **official Claude Code features** and **custom extensions**.
> Custom extensions are **NOT portable** and may **NOT work** in other environments.
> Before adopting any feature, verify whether it's official or custom using this document.

This document clarifies which features in this configuration are **official Claude Code features** versus **custom extensions** implemented specifically for this project.

## Quick Reference

| Feature Type | Works Everywhere? | Example |
|--------------|-------------------|---------|
| **Official** | ✅ Yes | `.claude/rules/`, `settings.json` hooks |
| **Custom Extension** | ❌ No | `@load:` directive, Phase 1-4 optimization |
| **Design Concept** | ❌ No (not implemented) | Module caching, intelligent prefetching |

## Why This Matters

When using this configuration:
- **Official features** work in any Claude Code installation
- **Custom extensions** only work within this specific configuration
- Understanding the difference helps with portability and troubleshooting

## Feature Classification

### Official Claude Code Features

These features are part of the official Claude Code product and are portable:

| Feature | Description | Documentation |
|---------|-------------|---------------|
| **CLAUDE.md memory hierarchy** | 5-tier memory system (Enterprise, Project, Rules, User, Local) | [Memory documentation](https://code.claude.com/docs/en/memory) |
| **`.claude/rules/` directory** | Auto-loaded rule files with YAML frontmatter | Official feature |
| **YAML frontmatter** | `paths` and `alwaysApply` for conditional loading | Official feature |
| **settings.json** | Hook configuration (PreToolUse, PostToolUse, etc.) | Official feature |
| **Hook events** | SessionStart, SessionEnd, UserPromptSubmit, Stop, etc. | Official feature |
| **Hook types** | `command`, `prompt`, `agent` types for different validation strategies | Official feature |
| **Async hooks** | `async: true` for non-blocking hook execution | Official feature |
| **`.claudeignore`** | Exclude files from context loading | Official feature |
| **Skills** | SKILL.md with name and description frontmatter | Official feature |
| **Agents** | Agent configuration files | Official feature |
| **Commands** | Custom slash commands in `.claude/commands/` | Official feature |

### Custom Extensions (This Project Only)

These features are **custom implementations** specific to this configuration and are **NOT portable**:

| Feature | Description | Portable? | Status |
|---------|-------------|-----------|--------|
| **`@./module.md` import syntax** | Inline file references in markdown | No | May work as hint |
| **`@load:` directive** | Force-load specific modules | No | May work as hint |
| **`@skip:` directive** | Exclude specific modules | No | May work as hint |
| **`@focus:` directive** | Set focus area | No | May work as hint |
| **Phase-based token optimization** | 4-phase loading strategy design | No | **Design only** |
| **Module caching strategy** | HOT/WARM/COLD tier design | No | **Design only** |
| **Markov chain prediction** | Command prediction for prefetching | No | **Design only** |
| **Custom settings.json fields** | `description`, `version` fields | No | Informational |
| **5W1H issue framework** | Structured issue templates | Guidelines only | Recommended |
| **Global commands** | `/issue-work`, `/release`, etc. | Config-specific | Functional |

### ⚠️ Design Concepts (Not Implemented)

The following features exist as **design documents only** and are **NOT implemented** by Claude Code:

| Design Document | What It Describes | Reality |
|-----------------|-------------------|---------|
| `docs/design/intelligent-prefetching.md` | Markov chain prediction for next command | **Not implemented** - Claude Code doesn't predict commands |
| `docs/design/module-caching.md` | HOT/WARM/COLD caching tiers | **Not implemented** - Claude Code doesn't cache modules |
| `docs/design/module-priority.md` | Dynamic priority-based loading | **Not implemented** - Rules load based on YAML frontmatter only |

These documents serve as **architectural references** for potential future implementation or as examples for other projects, but they do **not affect Claude Code behavior**.

## Detailed Breakdown

### Hook Types and Async Execution (Official)

**Type**: Official feature

Claude Code supports three types of hooks for different validation strategies:

| Hook Type | Description | Use Case |
|-----------|-------------|----------|
| `command` | Execute shell scripts | Complex validation, external tools |
| `prompt` | LLM yes/no decision | Simple safety checks, no scripting needed |
| `agent` | Multi-turn tool verification | Deep validation with Read/Grep access |

**Command Hook** (default):
```json
{
  "type": "command",
  "command": "~/.claude/hooks/validate.sh",
  "timeout": 30
}
```

**Prompt Hook** (AI-based):
```json
{
  "type": "prompt",
  "prompt": "Does this action follow security best practices? Answer yes or no."
}
```

**Agent Hook** (multi-turn):
```json
{
  "type": "agent",
  "prompt": "Verify this follows coding standards",
  "tools": ["Read", "Grep"],
  "timeout": 30000
}
```

**Async Execution**:

For non-blocking operations (formatting, logging), use `async: true`:
```json
{
  "type": "command",
  "command": "~/.claude/hooks/format.sh",
  "async": true,
  "timeout": 30
}
```

**When to use async**:
- ✅ PostToolUse formatting hooks
- ✅ Logging hooks (PostToolUseFailure, SubagentStart/Stop)
- ❌ PreToolUse security validation (must block until verified)
- ❌ SessionStart environment setup (must complete before use)

### Import Syntax (`@path/to/file`)

**Type**: Custom extension

**What it does**: Allows referencing other files inline in markdown:
```markdown
# My CLAUDE.md
@.claude/rules/core/environment.md
@.claude/rules/workflow/workflow.md
```

**Portability**: This syntax is a convention adopted in this project. It may or may not be processed by Claude Code depending on version.

**Alternative**: Use standard markdown links or direct file paths that Claude can read.

### `@load:`, `@skip:`, `@focus:` Directives

**Type**: Custom extension

**What they do**:
- `@load:` - Force load specific modules
- `@skip:` - Exclude modules from loading
- `@focus:` - Set task focus area

**Portability**: These are custom conventions. Claude may interpret them as natural language hints, but they are not official syntax.

### Token Optimization Design

**Type**: Custom architecture design

**What it includes**:
- Phase 1: Exclusion patterns (`.claudeignore`)
- Phase 2: Priority-based loading (module-priority.md)
- Phase 3: Module caching (module-caching.md)
- Phase 4: Intelligent prefetching (intelligent-prefetching.md)

**Portability**: The concepts are described in design documents but are not implemented features. They serve as guidelines for organizing rules.

### 5W1H Issue Framework

**Type**: Custom guidelines

**What it does**: Provides structured templates for GitHub issues and PRs using the 5W1H format (What, Why, Who, When, Where, How).

**Portability**: These are guidelines that can be adopted in any project, but the specific templates are custom to this configuration.

### Shared Skill References (SSOT)

**Type**: Repository-internal convention

Reference files consumed by both rule loading and skill imports are mapped in `reference-map.yml`. To avoid silent drift, each mapped mirror declares its canonical source and comparison mode:

| Mode | Behavior |
|------|----------|
| `exact` | Source and target must be byte-identical. |
| `strip-source-frontmatter` | Source YAML frontmatter and the following blank line are stripped before comparing with the target. |

The map covers workflow references, copy-derived plugin skill references, and explicitly duplicated plugin-internal references. Curated or synthesized plugin files remain outside the map.

**Editing**: Modify the canonical source listed in `reference-map.yml`. Regenerate mirrors with:

```bash
scripts/sync_references.sh      # macOS / Linux / WSL
pwsh scripts/sync_references.ps1   # Windows
```

**CI enforcement**: `.github/workflows/validate-skills.yml` runs `scripts/check_references.sh` and the reference guard tests on every relevant PR. The job fails (exit 2) if any mapped mirror drifts from canonical.

**Why this pattern**: Symlinks do not round-trip reliably through `git clone` on default Windows configurations. Build-time sync keeps copied references aligned without requiring platform-specific filesystem features.

### Doc-Index Drift Guard

**Type**: Repository-internal convention

`docs/.index/{manifest,bundles,graph,router}.yaml` are generated by `/doc-index`, but stale path, byte-size, and generated-date metadata can otherwise ship unnoticed after documentation moves. `scripts/validate-doc-index.sh` validates the checked-in index outputs against the working tree:

- every `documents[].path` must stay inside the repository and exist
- every `documents[].size` must be an integer matching the file's current byte length
- every recorded `documents[].sections[].h` / `l` entry must match a live ATX-style heading line
- duplicate paths are rejected
- every checked-in `docs/.index/*.yaml` file must share the same `_meta.generated` value

The guard intentionally stays narrow. It does not replace `/doc-index`; it fails when the checked-in manifest is no longer a faithful index of the files it claims to cover, or when non-manifest index outputs still carry stale generated metadata after the manifest has been refreshed.

**CI enforcement**: `.github/workflows/validate-skills.yml` runs the validator tests and then `scripts/validate-doc-index.sh` for every relevant PR. When documentation changes legitimately alter sizes, covered paths, or index generation metadata, regenerate the `docs/.index/*.yaml` outputs with `/doc-index` before opening the PR.

### Agent Definitions (drift guard)

**Type**: Repository-internal convention

The eight agent definitions exist in two layers — `project/.claude/agents/` and the standalone `plugin/agents/` bundle. They are near-duplicates but **not** byte-identical by design: frontmatter differs per layer (the project copy carries `color:`; neither carries the non-canonical `temperature:` field; `permissionMode: acceptEdits` is kept identical across both layers for the two write agents, documentation-writer and refactor-assistant), and the body genericizes exactly one repo-specific "language-specific rules" sentence in the plugin copy.

**CI enforcement**: `.github/workflows/validate-skills.yml` runs `scripts/check_agents.sh` (PowerShell twin: `scripts/check_agents.ps1`). It strips frontmatter and normalizes that single sentence, then fails (exit 2) if the agent **bodies** otherwise diverge, or if the behavioral frontmatter fields `tools` or `permissionMode` differ between layers (intended per-layer fields like `color` are exempt) — so a behavioral instruction or capability edited in one layer but not the other cannot ship silently.

**Advisory frontmatter (`applies_to`, `keywords`)**: every agent declares `applies_to` (a glob list) and `keywords`. These are **not** official Claude Code runtime path-triggers — the runtime delegates to a sub-agent only by its `description`. They are advisory inputs consumed by the `fleet-orchestrator` skill's Top-K routing score (`score = 2 * matched_applies_to_globs + 1 * matched_keywords`, see `global/skills/_internal/fleet-orchestrator/SKILL.md`). Opening a file that matches an `applies_to` glob does **not** auto-invoke the agent; keep delegation intent in `description`.

**`structure-explorer` memory scope**: `structure-explorer` is intentionally the only agent with `memory: local` and no `initialPrompt` — it performs stateless, 1-shot, breadth-first exploration with no cross-call state to persist, so the project-memory bootstrap pattern used by the other seven agents does not apply.

**Curated skill reference files are intentionally NOT guarded this way.** Files omitted from `reference-map.yml` are maintained as curated or synthesized plugin content. Examples include `plugin/skills/api-design/reference/logging.md`, documentation cleanup/communication guidance, monitoring guidance, and workflow problem-solving summaries. Do not add those files to the map unless they become direct mirrors of a canonical source.

### Version Declarations (VERSION_MAP SSOT)

**Type**: Repository-internal convention

Four independent version fields are declared across the suite. `VERSION_MAP.yml` at the repo root is the single source of truth; each field moves on its own SemVer track.

| Field             | Consumers                                                  |
|-------------------|------------------------------------------------------------|
| `suite`           | `README.md`, `README.ko.md` (shields.io badge URL)         |
| `plugin`          | `plugin/.claude-plugin/plugin.json` (`version`)            |
| `plugin-lite`     | `plugin-lite/.claude-plugin/plugin.json` (`version`)       |
| `settings-schema` | `global/settings.json`, `global/settings.windows.json`     |

**Bumping a version**: edit the target field in `VERSION_MAP.yml`, then propagate:

```bash
scripts/sync_versions.sh      # macOS / Linux / WSL
pwsh scripts/sync_versions.ps1   # Windows
# or, via sync.sh fast path:
scripts/sync.sh --versions-only
```

The `/release` skill wraps this flow — pass `--target <field>` to bump one track.

**CI enforcement**: `.github/workflows/validate-skills.yml` runs `scripts/check_versions.sh` on every PR. The job fails (exit 2) if any consumer drifts from its declared field in `VERSION_MAP.yml`.

**Why independent tracks**: `plugin` and `plugin-lite` release on their own cadence (different users install different variants), and `settings-schema` rev-locks to schema-breaking changes in `global/settings.json`. A single monorepo version would force lockstep releases where none is semantically required.

### Spec Linter (Official-Spec SSOT)

**Type**: Repository-internal convention

The spec linter validates `SKILL.md` frontmatter, `plugin.json`, and `settings.json` against canonical Claude Code 2026 schemas. Three JSON Schema (Draft 2020-12) files under `scripts/schemas/` declare the official field set; the linter enforces them across every checked-in consumer in the repo.

| File | Validates | Schema |
|------|-----------|--------|
| `**/SKILL.md` (frontmatter) | 14 official fields, `additionalProperties: false` | `scripts/schemas/skill-md.schema.json` |
| `*/.claude-plugin/plugin.json` | `name`, `version` (semver), `description`, `author`, `repository`, `compatibility`, ... | `scripts/schemas/plugin-json.schema.json` |
| `global/settings.json`, `global/settings.windows.json`, `project/.claude/settings.json` | `attribution`, `permissions`, `hooks`, `sandbox`, enums (`teammateMode`, `effortLevel`, ...) | `scripts/schemas/settings-json.schema.json` |

`SKILL.md` uses `additionalProperties: false` to reject unknown fields (typos, deprecated names) — the linter prints a "did you mean" suggestion using closest-match search. `plugin.json` and `settings.json` use `additionalProperties: true` so harness-specific or forward-compat fields are tolerated, but declared fields with enums or patterns (e.g., semver, `defaultMode`) are still strictly enforced.

**Running locally**:

```bash
# Repo-wide lint (advisory; reports without blocking)
scripts/spec_lint.sh --warn-only

# Repo-wide lint (strict; same flag CI uses)
scripts/spec_lint.sh --strict

# Single file or mode-specific
scripts/spec_lint.sh --mode skill global/skills/_internal/release/SKILL.md

# Fast path via sync.sh
scripts/sync.sh --lint --warn-only
```

PowerShell twin: `pwsh scripts/spec_lint.ps1 [-WarnOnly|-Strict|-Quiet] [-Mode skill|plugin|settings <file>...]`. Both wrappers shell out to `scripts/spec_lint.py`, which requires `pyyaml` and `jsonschema` (installed in CI; install locally with `pip install pyyaml jsonschema`).

**Exit codes**: `0` clean, `1` violations, `2` setup error or `--strict` violations. The `--warn-only` flag forces `0` regardless of violations (used by `scripts/sync.sh` and `scripts/validate_skills.sh` for soft rollout). The `--strict` flag promotes `1` to `2` so CI can distinguish strict-mode failures from regular violations.

**Updating schemas when the Claude Code spec changes**:

1. Bump the `$id` URL version (or update `description` to record the spec source date).
2. Add or remove fields in the `properties` block; update `required`, enums, and patterns to match the new spec.
3. For `SKILL.md`, keep `additionalProperties: false` so new fields fail loudly until the schema catches up.
4. Run `bash tests/scripts/test-spec-lint.sh` (or `pwsh tests/scripts/test-spec-lint.ps1`) to verify the regression suite still passes — case 12 lints every checked-in file in the repo.
5. Run `scripts/spec_lint.sh --warn-only` against the working tree and address any newly surfaced violations before flipping back to strict.

**CI enforcement**: `.github/workflows/validate-skills.yml` runs `scripts/spec_lint.sh --strict` on every PR targeting `main`, plus the test suite in `tests/scripts/test-spec-lint.sh`. The job fails (exit 2) on any violation. Path filters trigger the workflow on changes to `scripts/spec_lint.*`, `scripts/schemas/**`, and any `SKILL.md`, `plugin.json`, or `settings.json` consumer.

**Why a separate linter alongside `validate_skills.sh`**: `validate_skills.sh` enforces project-specific conventions (mirror sync, description quality, naming); the spec linter enforces the *official Claude Code spec*. Splitting them lets us upgrade the spec independently of in-repo conventions, and lets the spec linter run in advisory mode (`--warn-only` from `sync.sh` and `validate_skills.sh`) during a soft rollout while `validate_skills.sh` continues to gate the existing rules.

> Tracked in issue [#334](https://github.com/kcenon/claude-config/issues/334) (parent epic [#328](https://github.com/kcenon/claude-config/issues/328)).

### Skill Context Isolation (`context: fork`)

Audit and review skills run in an isolated subagent context so their findings do not consume the calling session's tokens.

| Skill | Agent | Why fork |
|-------|-------|----------|
| `plugin/skills/security-audit` | `Explore` (read-only) | Audit findings can exceed 10K tokens; isolation preserves the main context |
| `plugin/skills/performance-review` | `Explore` (read-only) | Same — large analysis output, read-only by design |
| `global/skills/_internal/doc-review` | `general-purpose` | Needs write access for `--fix` mode; isolation keeps doc-review noise out of the calling thread |

The forked subagent does not see the calling conversation's history. Each skill body is self-contained and operates entirely from the supplied arguments, returning a structured report at the end. Per the official spec, `context: fork` only makes sense for skills with explicit task instructions — guideline-only skills should keep the default inline context.

> Tracked in issue [#335](https://github.com/kcenon/claude-config/issues/335) (parent epic [#328](https://github.com/kcenon/claude-config/issues/328)).

## Using This Configuration Elsewhere

### What Works Out of the Box

When copying this configuration to another project:

1. **Rules directory structure** - `.claude/rules/` with YAML frontmatter
2. **Settings files** - `settings.json` with standard hook events
3. **CLAUDE.md files** - Memory hierarchy files
4. **Skills** - SKILL.md files with proper frontmatter

### What Requires Adaptation

1. **Import syntax** - May need to convert to explicit file paths
2. **Custom directives** - `@load:`, `@skip:` may not work
3. **Design documents** - Describe concepts, not implement features
4. **Global commands** - Installed as skills under `~/.claude/skills/_internal/` (migrated from `~/.claude/commands/`)

### Migration Checklist

When adopting this configuration in a new environment:

- [ ] Copy `.claude/rules/` directory
- [ ] Copy `settings.json` files
- [ ] Review and adapt CLAUDE.md content
- [ ] Remove or adapt custom directive syntax
- [ ] Test hook configurations
- [ ] Verify skill loading

## Official Documentation References

For authoritative information on Claude Code features:

- [Claude Code Documentation](https://code.claude.com/docs/en)
- [Memory Hierarchy](https://code.claude.com/docs/en/memory)
- [Rules and Settings](https://code.claude.com/docs/en/settings)
- [Hooks Configuration](https://code.claude.com/docs/en/hooks)

> **2026 URL migration**: Claude Code documentation moved from `docs.anthropic.com/en/docs/claude-code/*` (and legacy `docs.claude.com/en/docs/claude-code/*`) to `code.claude.com/docs/en/*`. Old URLs 301-redirect but search rankings suffer; all links in this repo should use `code.claude.com`. See [issue #336](https://github.com/kcenon/claude-config/issues/336).

## ADR / Design Doc Frontmatter (#624)

Files in `docs/design/` and the long-lived performance / regression docs
(`docs/tier2-benchmark-results.md`, `docs/batch-drift-regression.md`) carry a
small YAML frontmatter so a reader can tell at a glance whether the document
is still load-bearing without reading the body. The format is intentionally
narrow — five fields, all required:

```yaml
---
status: Active             # one of: Active | Superseded | Draft
audience: maintainer       # one of: maintainer | contributor | user
last_reviewed: 2026-05-09  # ISO date the doc was last confirmed accurate
supersedes: []             # list of relative paths this doc replaces
superseded_by: null        # relative path of the doc that replaces this one, or null
---
```

Field semantics:

- `status`: `Active` for current, `Draft` for proposals or design concepts
  not yet implemented, `Superseded` for documents kept for historical context
  but no longer authoritative.
- `audience`: who the document is for. `maintainer` for internal design,
  `contributor` for outside-PR explanations, `user` for end-user-visible
  docs (rare in `docs/design/`).
- `last_reviewed`: bumped whenever a maintainer confirms the doc still
  reflects reality. A future `/doc-index` extension will flag entries older
  than six months for re-review.
- `supersedes` / `superseded_by`: builds a forward / backward chain so the
  index can render "this design was replaced by …" links without prose
  authors having to add cross-references manually.

Validator: `scripts/validate-adr-headers.sh` is wired into
`validate-skills.yml` and rejects any `docs/design/` file (plus the two
named perf / regression docs) that is missing the frontmatter or has an
out-of-range value. When you create a new design document, copy the
five-field block from the nearest existing file as a starting point.

This is a custom extension — Claude Code itself does not consume these
fields. The doc-index skill (`/doc-index`) will eventually surface them in
`docs/.index/manifest.yaml` so router and bundle recommendations can filter
on `status: Active` and `audience`.

## Reporting Issues

If a feature from this configuration doesn't work:

1. Check if it's an official feature or custom extension (this document)
2. For official features: Report to [Claude Code Issues](https://github.com/anthropics/claude-code/issues)
3. For custom extensions: Report to [this repository's issues](https://github.com/kcenon/claude-config/issues)

---

*Version: 1.4.0 | Last updated: 2026-05-09*
