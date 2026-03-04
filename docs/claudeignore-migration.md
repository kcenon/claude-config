# .claudeignore Migration Strategy

> **Version**: 1.0.0
> **Created**: 2026-03-04
> **Related Issue**: #170
> **Purpose**: Migration plan from `.claudeignore` to official Claude Code alternatives

## Overview

`.claudeignore` is an unofficial feature that provides ~57,000 tokens of savings across
this project. This document categorizes every entry by migration path, identifies gaps,
and defines a fallback plan if `.claudeignore` is removed.

## Current Token Savings

| File | Estimated Savings | Entries |
|------|-------------------|---------|
| `global/.claudeignore` | ~37,000 tokens | 7 categories |
| `project/.claudeignore` | ~20,000 tokens | 12 categories |
| **Total** | **~57,000 tokens** | **19 categories** |

## Migration Matrix

### Global `.claudeignore` Entries

| Entry | Savings | Official Alternative | Status | Notes |
|-------|---------|---------------------|--------|-------|
| `**/session-memory/` | ~5,000 | `.gitignore` | **Ready** | Session memory is transient; should be git-ignored |
| `plugins/cache/`, `**/cache/` | ~3,000 | `.gitignore` | **Ready** | Cache directories are transient |
| `backup_*/`, `**/backup_*/` | ~2,000 | `.gitignore` | **Ready** | Backups are transient |
| `plugins/marketplaces/` | ~15,000 | `.gitignore` | **Ready** | Large plugin directories; not source code |
| `plans/`, `**/plans/` | ~2,000 | `.gitignore` | **Ready** | Plan files are transient |
| `commands/`, `**/commands/` | ~5,000 | On-demand loading | **Done** | Commands load only when invoked by design |
| `skills/`, `**/skills/` | ~5,000 | On-demand loading | **Done** | Skills load only when invoked by design |

### Project `.claudeignore` Entries

| Entry | Savings | Official Alternative | Status | Notes |
|-------|---------|---------------------|--------|-------|
| Large meta-docs (4 files) | ~4,000 | YAML `alwaysApply: false` | **Gap** | No `paths` match for design docs |
| `.claude/rules/*/reference/` | ~3,000 | YAML `alwaysApply: false` | **Partial** | 3/6 reference files lack frontmatter |
| `.claude/rules/operations/` | ~1,500 | YAML `alwaysApply: false` + `paths` | **Done** | `ops.md` has proper frontmatter |
| `.claude/rules/project-management/` | ~2,000 | YAML `alwaysApply: false` + `paths` | **Done** | All 3 files have frontmatter |
| `.claude/rules/api/` | ~2,000 | YAML `alwaysApply: false` + `paths` | **Done** | All 4 files have frontmatter |
| Coding rule files (5 files) | ~2,500 | YAML `alwaysApply: false` + `paths` | **Done** | All have frontmatter |
| `security.md` | ~500 | YAML `alwaysApply: false` + `paths` | **Done** | Has frontmatter |
| `testing.md` | ~500 | Part of `project-management/testing.md` | **Done** | Has frontmatter |
| `documentation.md` | ~500 | Part of `project-management/documentation.md` | **Done** | Has frontmatter |
| `agents/`, `skills/` | ~1,000 | On-demand loading | **Done** | Load when invoked by design |
| `.mcp.json.example` | ~200 | Not loaded as active config | **Verify** | Template file, may not need exclusion |
| `settings.json`, `settings.local.json` | ~300 | Not loaded as context | **Verify** | Settings are parsed, not injected as context |
| `README.md`, `README.ko.md`, `TOKEN_OPTIMIZATION.md` | ~1,500 | No direct equivalent | **Gap** | No official way to exclude specific files |
| `.npm-cache/`, `*.backup`, `*.bak`, `*.tmp` | ~500 | `.gitignore` | **Ready** | Transient files; should be git-ignored |

## Migration Status Summary

| Status | Count | Token Savings | Percentage |
|--------|-------|---------------|------------|
| **Done** (official alternative in place) | 10 | ~22,000 | 39% |
| **Ready** (can migrate to `.gitignore`) | 6 | ~27,500 | 48% |
| **Partial** (needs frontmatter fix) | 1 | ~3,000 | 5% |
| **Gap** (no official equivalent) | 2 | ~5,500 | 10% |
| **Verify** (may not need exclusion) | 2 | ~500 | <1% |

## Action Items

### Phase 3a: Immediate (This PR)

1. **Add missing YAML frontmatter** to 3 reference files:
   - `workflow/reference/5w1h-examples.md` — add `alwaysApply: false`
   - `workflow/reference/commit-hooks.md` — add `alwaysApply: false`
   - `coding/reference/anti-patterns.md` — add `alwaysApply: false`

2. **Annotate `.claudeignore` files** with per-entry migration status

3. **Create this migration document** as a reference

### Phase 3b: Short-term (Future PR)

4. **Add `.gitignore` entries** for transient directories that should also be git-ignored:
   - `session-memory/`, `cache/`, `backup_*/`, `plans/`, `.npm-cache/`
   - Coordinate with global `.gitignore` to avoid duplication

5. **Verify assumptions**:
   - Confirm `skills/` and `commands/` truly load on-demand without `.claudeignore`
   - Confirm `.mcp.json.example` and `settings.json` are not injected as context
   - Measure token usage with and without `.claudeignore` to quantify the actual gap

### Phase 3c: Long-term (Monitoring)

6. **Monitor Claude Code releases** for:
   - Official `.claudeignore` support (tracking issue: anthropics/claude-code#579)
   - New context exclusion mechanisms
   - Changes to how files are loaded into context

7. **Feature requests** to consider:
   - Official file-level exclusion (beyond `permissions.deny` which blocks access entirely)
   - Context budget controls per file type

## Gap Analysis

### Gap 1: Large Meta-Documentation Files

**Files**: `intelligent-prefetching.md`, `module-caching.md`, `module-priority.md`, `conditional-loading.md`

**Problem**: These are design documents (~63KB total) that describe conceptual
architecture. They are not rule files, so YAML frontmatter does not apply.

**Workarounds**:
- Move to `docs/design/` (already partially done) — Claude Code may not auto-load from `docs/`
- Use `permissions.deny` with `Read(docs/design/*)` — but this blocks all access, not just auto-loading
- Accept the token cost (~4,000 tokens) as acceptable overhead

**Recommendation**: Keep in `.claudeignore` until an official alternative exists. The
4,000 token cost is manageable if `.claudeignore` is removed.

### Gap 2: README and Documentation Files

**Files**: `README.md`, `README.ko.md`, `TOKEN_OPTIMIZATION.md`

**Problem**: These are standard documentation files that Claude Code auto-loads from
the project root. There is no official way to prevent specific files from being loaded
into context without blocking read access entirely.

**Workarounds**:
- Move READMEs to a subdirectory (breaks GitHub conventions)
- Use `permissions.deny` with `Read(README.md)` — blocks all access, not just auto-loading
- Accept the token cost (~1,500 tokens) as acceptable overhead

**Recommendation**: Accept the token cost. READMEs are small and occasionally useful
in context. This is a ~1,500 token overhead, which is minor.

### Total Gap Impact

If `.claudeignore` is removed entirely:
- **Mitigated by official alternatives**: ~52,500 tokens (92%)
- **Unmitigated gap**: ~5,500 tokens (10%)
- **Acceptable overhead**: The 5,500 token gap is well within the tolerance for normal sessions

## Fallback Plan

If `.claudeignore` is removed in a future Claude Code version:

1. **No action needed** for entries already using official alternatives (92%)
2. **Accept ~5,500 tokens overhead** for gap entries (design docs + READMEs)
3. **Add `.gitignore` entries** for transient directories if not already done
4. **Monitor** for new official features that close the remaining gaps
5. **Consider** moving large design docs to a separate repository if token overhead
   becomes problematic

## References

- [Claude Code .claudeignore Discussion](https://github.com/anthropics/claude-code/issues/579)
- [Token Optimization Guide](./TOKEN_OPTIMIZATION.md)
- [YAML Frontmatter Documentation](../project/CLAUDE.md)
