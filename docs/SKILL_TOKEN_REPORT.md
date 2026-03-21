# Skill Token Consumption Report

> **Measured**: 2026-03-21 KST
> **Method**: Byte count / 4 = estimated tokens (conservative)
> **Scope**: All user-invocable skills + runtime overhead

## Executive Summary

Each skill invocation consumes **~35,000-48,000 tokens** at startup. Roughly 60-65% is
unavoidable Claude Code runtime overhead (system prompt + tool definitions). The remaining
35-40% comes from the skill content, always-loaded rules, and configuration files.

| Component | Tokens | Controllable |
|-----------|--------|:------------:|
| Claude Code runtime | ~30,000 | No |
| Skill SKILL.md | 1,600-7,700 | Yes |
| Always-loaded rules | ~1,010 | Yes |
| CLAUDE.md + settings.json | ~3,160 | Yes |
| Conditional rules (on demand) | 0-5,000 | By design |
| **Typical total** | **~36,000-47,000** | |

---

## Runtime Overhead (Fixed Cost Per Session)

These tokens are consumed regardless of which skill is invoked.

| Component | Est. Tokens | Notes |
|-----------|-------------|-------|
| System prompt (base instructions) | ~10,000 | Committing, PRs, safety, sandbox rules |
| Tool definitions (27 tools) | ~17,000 | Agent, Bash, Glob, Grep, Read, Edit, Write, etc. |
| Auto memory system | ~2,500 | Memory read/write instructions |
| Output style (Explanatory) | ~500 | Style-specific formatting rules |
| **Runtime subtotal** | **~30,000** | **~60-65% of total** |

---

## Per-Skill Token Budget

### Global Skills (User-Invocable)

| Skill | Bytes | Tokens | Dual Mode | Total Est. |
|-------|------:|-------:|:---------:|----------:|
| `/pr-work` | 30,822 | 7,706 | Solo/Team | ~42,900 |
| `/issue-work` | 29,079 | 7,270 | Solo/Team | ~42,400 |
| `/doc-review` | 19,053 | 4,763 | Solo/Team | ~39,900 |
| `/release` | 16,733 | 4,183 | Solo/Team | ~39,300 |
| `/implement-all-levels` | 14,965 | 3,741 | Solo/Team | ~38,900 |
| `/issue-create` | 7,139 | 1,785 | No | ~36,900 |
| `/branch-cleanup` | 6,462 | 1,616 | No | ~36,800 |

> **Total Est.** = Runtime (~30,000) + Skill tokens + Always-loaded rules (~1,010) + Config (~3,160)

### Plugin Skills (Context-Triggered)

These load automatically when matching file patterns are detected, not via slash commands.

| Skill | Bytes | Tokens | Model | Trigger |
|-------|------:|-------:|-------|---------|
| ci-debugging | 3,064 | 766 | sonnet | CI/CD failures |
| performance-review | 1,389 | 347 | sonnet | Performance-related files |
| security-audit | 1,355 | 338 | sonnet | Auth/security files |
| project-workflow | 1,264 | 316 | — | Workflow operations |
| documentation | 1,116 | 279 | haiku | Doc files |
| api-design | 1,016 | 254 | sonnet | API files |
| coding-guidelines | 951 | 237 | sonnet | Source code files |

> Plugin skills are lightweight (237-766 tokens each) — negligible overhead.

### Shared Policy

| File | Bytes | Tokens |
|------|------:|-------:|
| `_policy.md` | 413 | 103 |

---

## Section Breakdown: Top 3 Sections Per Skill

### `/issue-work` (7,270 tokens)

| Section | Bytes | Tokens | Notes |
|---------|------:|-------:|-------|
| Team Mode Instructions | 11,277 | 2,819 | 3-agent orchestration |
| Solo Mode Instructions | 6,537 | 1,634 | 12-step workflow |
| Test Plan | 2,582 | 646 | Manual verification steps |

### `/pr-work` (7,706 tokens)

| Section | Bytes | Tokens | Notes |
|---------|------:|-------:|-------|
| CI/CD Failure Analysis | ~11,500 | 2,875 | Error categorization + root cause |
| Team Mode Instructions | ~8,900 | 2,225 | Diagnoser + fixer + doc-writer |
| Error Handling | ~3,200 | 800 | 3 retries, escalation |

### `/doc-review` (4,763 tokens)

| Section | Bytes | Tokens | Notes |
|---------|------:|-------:|-------|
| Team Mode Instructions | ~8,300 | 2,075 | Analyzer + fixer + validator |
| Solo Mode Instructions | ~4,100 | 1,025 | Subagent parallelism |
| Report Template | ~1,400 | 350 | Severity classification |

### `/release` (4,183 tokens)

| Section | Bytes | Tokens | Notes |
|---------|------:|-------:|-------|
| Team Mode Instructions | ~7,800 | 1,950 | Tag, changelog, validate |
| Solo Mode | ~4,200 | 1,050 | 6-step sequential |
| Changelog Categories | ~800 | 200 | Commit prefix mapping |

### `/implement-all-levels` (3,741 tokens)

| Section | Bytes | Tokens | Notes |
|---------|------:|-------:|-------|
| Team Mode Instructions | ~7,700 | 1,925 | Per-tier cycle with approval gates |
| Enforcement Rules | ~3,200 | 800 | Prohibited patterns |
| Solo Mode | ~2,900 | 725 | 5-step sequential |

### `/issue-create` (1,785 tokens)

| Section | Bytes | Tokens | Notes |
|---------|------:|-------:|-------|
| Instructions | ~5,600 | 1,400 | 5W1H framework + interactive flow |
| Title Conventions | ~400 | 100 | Type prefix examples |
| Error Handling | ~480 | 120 | Validation errors |

### `/branch-cleanup` (1,616 tokens)

| Section | Bytes | Tokens | Notes |
|---------|------:|-------:|-------|
| Instructions | ~4,600 | 1,150 | 8-step branch cleanup |
| Error Handling | ~480 | 120 | Prerequisites, runtime |
| Output Summary | ~800 | 200 | Deletion report |

---

## Dual Mode Overhead Analysis

5 of 7 skills include both Solo and Team Mode instructions. When `--solo` is used,
Team Mode content (~1,900-2,800 tokens) loads unnecessarily, and vice versa.

| Skill | Solo Section | Team Section | Wasted if Solo | Wasted if Team |
|-------|------------:|-------------:|---------------:|---------------:|
| `/pr-work` | ~2,000 | ~2,225 | 2,225 (29%) | 2,000 (26%) |
| `/issue-work` | ~1,634 | ~2,819 | 2,819 (39%) | 1,634 (22%) |
| `/doc-review` | ~1,025 | ~2,075 | 2,075 (44%) | 1,025 (22%) |
| `/release` | ~1,050 | ~1,950 | 1,950 (47%) | 1,050 (25%) |
| `/implement-all-levels` | ~725 | ~1,925 | 1,925 (51%) | 725 (19%) |

**Potential savings from mode splitting**: 1,600-2,800 tokens per invocation (4-7% of total).

---

## Conditional Rules Impact

When a skill executes, it triggers file operations that activate conditional rules.
Below is the estimated additional token load per workflow stage.

| Triggered Rule | Tokens | Triggering Skills |
|----------------|-------:|-------------------|
| github-pr-5w1h.md | 431 | issue-work, pr-work, implement-all-levels |
| github-issue-5w1h.md | 443 | issue-work, issue-create |
| build-verification.md | 1,132 | issue-work, pr-work |
| ci-resilience.md | 972 | issue-work, pr-work |
| session-resume.md | 423 | All (always loaded) |
| git-commit-format.md | 181 | All (always loaded) |

**Typical conditional overhead for issue-work**: ~2,000-3,000 additional tokens during execution.

---

## Optimization Opportunities

### High Impact

| Optimization | Savings | Effort | Trade-off |
|-------------|--------:|--------|-----------|
| Split Solo/Team into separate files | 1,600-2,800 tokens | Medium | Duplicated shared sections |
| Reduce SKILL.md verbosity (examples) | 500-1,000 tokens | Low | Less explicit guidance |

### Low Impact (Not Recommended)

| Optimization | Savings | Why Not |
|-------------|--------:|---------|
| Reduce runtime overhead | ~17,000 | Not controllable (Claude Code internal) |
| Remove always-loaded rules | ~1,010 | Already minimal (5 essential files) |
| Shrink settings.json | ~500 | Hooks/permissions are necessary |

### Already Optimized

| Item | Status |
|------|--------|
| Rule frontmatter (`alwaysApply: false`) | Fixed (2026-03-21) — 86% reduction |
| Reference docs excluded via `.claudeignore` | Active |
| Plugin skills are lightweight (237-766 tokens) | By design |

---

## Key Findings

1. **~60% of token budget is Claude Code runtime** — not controllable by configuration
2. **SKILL.md is the largest controllable cost** — `/pr-work` (7,706) and `/issue-work` (7,270) are the heaviest
3. **Dual mode wastes 22-51% of skill tokens** when only one mode is used
4. **Plugin skills are efficient** — all under 800 tokens, context-triggered only
5. **Conditional rules add ~2,000-3,000 tokens** during active workflow, by design
6. **Always-loaded rules are already minimal** at ~1,010 tokens (5 files)

---

*Report generated from live system measurements. Token estimates use bytes/4 ratio.*
*Runtime overhead is estimated based on system prompt analysis and may vary by Claude Code version.*
