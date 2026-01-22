# Skills and Rules System Architecture Review

> **Issue**: #63
> **Date**: 2026-01-22
> **Status**: Analysis Complete

## Executive Summary

This document provides a comprehensive analysis of the Skills and Rules systems in claude-config, evaluates three architectural options, and provides a recommendation for the optimal integration strategy.

**Recommendation**: **Option B (Maintain Skills + Supplement Rules)** with enhanced documentation and clear role separation.

## Current Architecture Analysis

### Current Structure (3 Tiers)

```
CLAUDE.md
└── .claude/skills/*/SKILL.md (keyword-based auto-activation)
      └── reference/*.md (symbolic links to .claude/rules)

CLAUDE.md
└── .claude/rules/*.md (path-based conditional loading)
```

### Skills System (Current Implementation)

**Location**: `.claude/skills/<skill-name>/SKILL.md`

**Current Skills**:
| Skill | Purpose | Activation Method |
|-------|---------|-------------------|
| `coding-guidelines` | Code standards, quality, error handling | Model-driven (description match) |
| `api-design` | REST/GraphQL, architecture, observability | Model-driven |
| `documentation` | README, API docs, comments | Model-driven |
| `performance-review` | Profiling, caching, optimization | Model-driven |
| `project-workflow` | Git, issues, PRs, testing | Model-driven |
| `security-audit` | Input validation, auth, secure coding | Model-driven |

**Key Features**:
- `description` field enables automatic invocation based on context
- `allowed-tools` restricts available tools
- `reference/` directory uses symbolic links to shared guidelines
- Supports `@reference/file.md` import syntax

### Rules System (Current Implementation)

**Location**: `.claude/rules/<rule-name>.md`

**Current Rules**:
| Rule | Paths | Purpose |
|------|-------|---------|
| `coding.md` | `**/*.{ts,tsx,js,py,cpp,hpp,go,rs,kt,java}` | Naming, structure, comments |
| `api/rest-api.md` | `**/api/**`, `**/routes/**`, etc. | REST conventions |
| `documentation.md` | `**/*.md`, `**/docs/**` | Documentation standards |
| `security.md` | Various auth/security paths | Security guidelines |
| `testing.md` | `**/test/**`, `**/*.test.*` | Testing conventions |

**Key Features**:
- `paths` frontmatter enables file-based conditional loading
- Rules without `paths` load unconditionally
- Automatically discovered recursively
- No model-driven activation

## Official Claude Code Recommendations

Based on official documentation analysis:

### Skills (Recommended Approach)
- **Purpose**: Extensible capabilities that enhance Claude's functionality
- **Activation**: Model-driven (automatic) or user-driven (slash commands)
- **Structure**: Full directory with SKILL.md and supporting files
- **Status**: Current recommended approach (commands deprecated)

### Rules
- **Purpose**: Topic-specific project instructions
- **Activation**: File path-based (conditional) or unconditional
- **Structure**: Simple .md files in `.claude/rules/`
- **Status**: Officially supported for modular project configuration

### Key Insight

The official documentation does **not** explicitly distinguish between Skills and Rules for overlapping use cases. Both systems are supported and recommended for different purposes:

- **Skills**: Task-type specific guides with model-driven activation
- **Rules**: File path-specific rules with conditional loading

## Architecture Options Evaluation

### Option A: Rules-Centered Integration

Replace Skills' keyword-based activation with Rules' `paths` frontmatter.

**Proposed Structure**:
```yaml
---
paths:
  - "**/*.ts"
  - "**/*.py"
keywords:  # Extension proposal (not officially supported)
  - "implement"
  - "refactor"
---
# Coding Guidelines
```

**Pros**:
- Simplifies to single-tier structure
- Adheres to official recommended structure
- Reduces maintenance overhead
- Clear file-path based activation

**Cons**:
- **Loses keyword-based auto-activation** (critical feature)
- `keywords` frontmatter is NOT officially supported
- Cannot replicate model-driven behavior
- Regression in functionality

**Token Efficiency**: Similar to current Rules system
**Migration Effort**: High (requires reimplementation of activation logic)
**Risk Level**: High (functionality loss)

**Verdict**: **Not Recommended** - Loses essential model-driven activation feature

### Option B: Maintain Skills + Supplement Rules (Recommended)

Keep current structure but clarify roles explicitly.

**Proposed Structure**:
```
.claude/
├── skills/          # WHAT to do (task-type specific guides)
│   ├── coding-guidelines/
│   ├── security-audit/
│   ├── api-design/
│   └── ...
└── rules/           # WHERE to apply (file path-specific rules)
    ├── api/rest-api.md
    ├── coding.md
    └── testing.md
```

**Role Separation**:
| System | Trigger | Purpose | Example |
|--------|---------|---------|---------|
| Skills | Context keywords | "How should I do this task?" | User asks about security |
| Rules | File paths | "What applies to this file?" | Editing `*.test.ts` |

**Pros**:
- Maintains advantages of both systems
- Model-driven activation preserved
- Clear separation of concerns
- Official support for both systems
- No functionality loss

**Cons**:
- Two systems to maintain
- Learning curve for users
- Potential confusion without clear documentation

**Token Efficiency**: Optimal (Skills load on-demand, Rules load by file context)
**Migration Effort**: Low (documentation and organization)
**Risk Level**: Low (no functionality changes)

**Verdict**: **Recommended** - Best balance of functionality and maintainability

### Option C: Hybrid Integration

Restructure Skills as a higher tier of Rules.

**Proposed Structure**:
```
.claude/
└── rules/
    ├── by-task/           # (former Skills - converted to rules)
    │   ├── coding.md
    │   └── security.md
    └── by-path/           # (current Rules)
        ├── api.md
        └── testing.md
```

**Pros**:
- Single system (rules only)
- Simplified mental model
- Adheres to official structure

**Cons**:
- **Loses model-driven activation** (Skills converted to passive rules)
- `by-task/` rules would load based on paths only
- Cannot replicate context-aware loading
- Significant regression in functionality

**Token Efficiency**: Worse (rules load unconditionally or by file path only)
**Migration Effort**: Medium (restructure files)
**Risk Level**: High (functionality loss)

**Verdict**: **Not Recommended** - Same critical issues as Option A

## Token Efficiency Analysis

### Current Approach (Skills + Rules)

| Component | Token Cost | Loading Condition |
|-----------|------------|-------------------|
| Skills (inactive) | ~100-200 per skill | Description only (for matching) |
| Skills (active) | ~1000-3000 | When invoked by model/user |
| Rules (conditional) | ~200-500 | When paths match |
| Rules (unconditional) | ~500-1000 | Always loaded |

**Estimated Total (typical session)**: 2000-5000 tokens

### Option A/C (Rules Only)

| Component | Token Cost | Loading Condition |
|-----------|------------|-------------------|
| All rules | ~3000-6000 | Based on file paths only |

**Estimated Total**: 3000-6000 tokens (worse due to unconditional loading)

### Option B (Enhanced Current)

| Component | Token Cost | Loading Condition |
|-----------|------------|-------------------|
| Skills (optimized) | ~100 per skill | Description matching |
| Active skill | ~800-2000 | Model/user invocation |
| Rules (conditional) | ~200-400 | Path matching |

**Estimated Total (typical session)**: 1500-3500 tokens (15-30% improvement with optimization)

## Recommendation: Option B with Enhancements

### Immediate Actions

1. **Document Role Separation**
   - Add clear documentation distinguishing Skills vs Rules
   - Update README with usage guidelines

2. **Optimize Skill Descriptions**
   - Make descriptions more specific for better matching
   - Reduce false-positive activations

3. **Review Rule Paths**
   - Ensure paths are specific enough
   - Remove overlapping rules

### Future Considerations

1. **Monitor Official Updates**
   - Claude Code may introduce unified system
   - Be prepared to migrate if better solution emerges

2. **Community Feedback**
   - Collect user feedback on system usability
   - Adjust based on real-world usage patterns

## Implementation Plan

### Phase 1: Documentation (Immediate)

- [ ] Update README with Skills vs Rules explanation
- [ ] Add architecture diagram
- [ ] Create migration guide for users

### Phase 2: Optimization (Short-term)

- [ ] Review and optimize skill descriptions
- [ ] Audit rule paths for specificity
- [ ] Remove duplicate/overlapping content

### Phase 3: Monitoring (Ongoing)

- [ ] Track official Claude Code updates
- [ ] Collect community feedback
- [ ] Measure token efficiency improvements

## Conclusion

After comprehensive analysis of the three proposed options:

| Option | Functionality | Token Efficiency | Maintenance | Verdict |
|--------|--------------|------------------|-------------|---------|
| A: Rules-Centered | Loss (High Risk) | Worse | Simpler | Not Recommended |
| B: Maintain Both | Preserved | Best | Manageable | **Recommended** |
| C: Hybrid | Loss (High Risk) | Worse | Simpler | Not Recommended |

**Final Recommendation**: Maintain the current dual-system architecture (Option B) with enhanced documentation and clear role separation. The model-driven activation feature of Skills is too valuable to lose, and both systems are officially supported by Claude Code.

## References

- [Claude Code Memory Documentation](https://code.claude.com/docs/en/memory)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Agent Skills Standard](https://agentskills.io)
