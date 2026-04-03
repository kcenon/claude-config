# Token Optimization Discoveries

> **Date**: 2026-01-27
> **Context**: Real-world testing with `/Users/dongcheolshin/Sources/` project
> **Initial Problem**: 70,000+ tokens at startup, target: 15,000-20,000 tokens

## Executive Summary

Through systematic testing, we discovered that **Claude Code automatically scans the `.claude/rules/` directory** regardless of CLAUDE.md or .claudeignore settings. The only reliable method to achieve significant token reduction is **physical directory restructuring**.

## Key Findings

### Finding 1: Claude Code's Automatic Directory Scanning

**Discovery**: Claude Code has built-in behavior to scan `.claude/rules/` directory and load all `.md` files.

**Evidence**:
- Created .claudeignore with correct patterns → Still 70,000 tokens
- Minimized CLAUDE.md to prevent auto-loading → Still 70,000 tokens
- Restructured `.claude/rules/` directory → **Dropped to 18,000 tokens** ✅

**Implication**: Configuration files (.claudeignore, CLAUDE.md) have limited effect compared to directory structure itself.

### Finding 2: .claudeignore Pattern Requirements

**Discovery**: .claudeignore patterns must include `.claude/` prefix to work correctly.

**Before (Ineffective)**:
```gitignore
rules/operations/          # ❌ Wrong path
rules/coding/general.md    # ❌ Wrong path
```

**After (Effective)**:
```gitignore
.claude/rules/operations/          # ✅ Correct path
.claude/rules/coding/general.md    # ✅ Correct path
```

**Impact**: Fixed patterns provide ~10-15% token reduction on top of directory restructuring.

### Finding 3: Large Meta-Documentation Files

**Discovery**: Meta-documentation about the token optimization system itself consumes ~73KB (9,938 tokens).

**Culprits**:
- `intelligent-prefetching.md` - 21KB
- `module-caching.md` - 17KB (previously 16KB)
- `module-priority.md` - 13KB (previously 14KB)
- `conditional-loading.md` - 11KB

**Solution**: Exclude these from automatic loading:
```gitignore
.claude/rules/intelligent-prefetching.md
.claude/rules/module-caching.md
.claude/rules/module-priority.md
.claude/rules/conditional-loading.md
```

### Finding 4: Directory Restructuring is Most Effective

**Discovery**: Reducing files in `.claude/rules/` from 40+ to 9 essential files achieved 74% token reduction.

**Before**:
```
.claude/rules/
├── core/ (4 files)
├── workflow/ (7+ files + reference/)
├── coding/ (5+ files)
├── api/ (4+ files)
├── operations/ (2+ files)
├── project-management/ (3+ files)
└── [meta-docs] (4 large files, 73KB)

Total: 40+ files, ~60,000 tokens for rules alone
```

**After**:
```
.claude/rules/
├── core/
│   ├── common-commands.md (227 tokens)
│   ├── communication.md (752 tokens)
│   ├── environment.md (248 tokens)
│   └── problem-solving.md (75 tokens)
└── workflow/
    ├── git-commit-format.md (1,378 tokens)
    ├── github-issue-5w1h.md (1,222 tokens)
    ├── github-pr-5w1h.md (2,427 tokens)
    ├── question-handling.md (266 tokens)
    └── problem-solving.md (215 tokens)

Total: 9 files, 6,812 tokens for rules
```

**Reduction**: 60,000 → 6,812 tokens (**88.6%** reduction)

## Optimization Strategy Priority

Based on effectiveness:

### Priority 1: Directory Restructuring (MOST EFFECTIVE)

**Impact**: 70-80% token reduction
**Method**: Keep only 9 essential files in `.claude/rules/`

**Essential Files**:
- Core (4 files): environment, communication, problem-solving, common-commands
- Workflow (5 files): git-commit-format, github-issue-5w1h, github-pr-5w1h, question-handling, problem-solving

**Implementation**:
```bash
# 1. Backup everything
mv .claude/rules .claude/rules_BACKUP_$(date +%Y%m%d_%H%M%S)

# 2. Create minimal structure
mkdir -p .claude/rules/core .claude/rules/workflow

# 3. Copy only essential files
cp [backup]/core/{environment,communication,problem-solving,common-commands}.md .claude/rules/core/
cp [backup]/workflow/{git-commit-format,github-issue-5w1h,github-pr-5w1h,question-handling,problem-solving}.md .claude/rules/workflow/
```

### Priority 2: Fix .claudeignore Patterns (MEDIUM EFFECTIVENESS)

**Impact**: 10-15% additional reduction
**Method**: Add `.claude/` prefix to all patterns

**Update patterns**:
```gitignore
# Before
rules/operations/

# After
.claude/rules/operations/
```

### Priority 3: Exclude Meta-Documentation (LOW-MEDIUM EFFECTIVENESS)

**Impact**: ~10,000 tokens (if meta-docs exist in rules/)
**Method**: Add explicit exclusions

```gitignore
.claude/rules/intelligent-prefetching.md
.claude/rules/module-caching.md
.claude/rules/module-priority.md
.claude/rules/conditional-loading.md
```

### Priority 4: Update CLAUDE.md (DOCUMENTATION ONLY)

**Impact**: None (but clarifies behavior)
**Method**: Remove "automatic loading" claims

Update CLAUDE.md to reflect reality:
```markdown
## Rule Loading Behavior

**CRITICAL**: Claude Code automatically scans `.claude/rules/` directory.
The only reliable optimization is directory restructuring.
```

## Measured Results

From `/Users/dongcheolshin/Sources/` optimization:

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Total startup tokens** | ~70,000 | ~18,000 | **74%** ⬇️ |
| **Rules directory tokens** | ~60,000 | ~6,812 | **88.6%** ⬇️ |
| **File count in rules/** | 40+ | 9 | **77%** ⬇️ |

## Command-Specific Token Usage

Estimated token usage after optimization:

| Command | Before | After | Savings |
|---------|--------|-------|---------|
| `/commit` | ~70,000 | ~8,000 | **88%** |
| `/issue-work` | ~70,000 | ~18,000 | **74%** |
| `/pr-work` | ~70,000 | ~15,000 | **79%** |
| `/issue-create` | ~70,000 | ~12,000 | **83%** |

## Loading Additional Modules When Needed

### Method 1: Temporary Copy

When specific rules needed:
```bash
# For security work
cp .claude/rules_BACKUP_*/security.md .claude/rules/

# After work is done
rm .claude/rules/security.md
```

### Method 2: Explicit Reference

```markdown
Can you review .claude/rules_BACKUP_20260127_210858/security.md and apply those guidelines?
```

### Method 3: @load Directive (if supported)

```markdown
@load: security, performance
```

## Recommendations for claude-config Project

1. **Update documentation**: Reflect the discovery that directory scanning is automatic
2. **Provide restructuring script**: Help users easily create minimal structure
3. **Update .claudeignore**: Add `.claude/` prefix to all patterns
4. **Exclude meta-docs**: Add patterns for large meta-documentation files
5. **Create backup strategy**: Document how to safely backup and restore rules
6. **Update TOKEN_OPTIMIZATION.md**: Add section about directory restructuring as primary method

## Backup and Restore Procedure

### Creating Backup

```bash
cp -r .claude/rules ".claude/rules_BACKUP_$(date +%Y%m%d_%H%M%S)"
```

### Restoring from Backup

```bash
rm -rf .claude/rules
mv .claude/rules_BACKUP_20260127_210858 .claude/rules
```

### Verification

```bash
# Check file count
find .claude/rules -name "*.md" | wc -l

# Expected: 9 files for optimized, 40+ for full
```

## Future Considerations

### Potential Claude Code Updates

If Claude Code team adds features:
- **Selective loading API**: Allow programmatic control of which files to load
- **.claudeignore priority boost**: Make .claudeignore override directory scanning
- **CLAUDE.md directives**: Add `exclude_dirs` or `minimal_load` options
- **Lazy loading**: Load files only when content is actually referenced

### Alternative Structures

**Option 1: Separate Directories**
```
.claude/
├── rules/          # Minimal (9 files, auto-loaded)
├── rules_optional/ # Additional rules (not auto-loaded)
└── rules_archive/  # Backup (not auto-loaded)
```

**Option 2: Skill-Based Structure**
```
.claude/
├── rules/          # Only workflow essentials
└── skills/         # Everything else in skill references
    ├── coding-guidelines/reference/
    └── performance-review/reference/
```

## Conclusion

**Primary Lesson**: Configuration files have limited power. Physical directory structure matters most.

**Best Practice**:
1. Start with minimal `.claude/rules/` (9 essential files)
2. Keep full backup in separate directory
3. Load additional modules temporarily when needed
4. Use .claudeignore for additional optimizations

**Expected Results**: 70-75% token reduction achievable through directory restructuring alone.

---

**Document Version**: 1.0.0
**Last Updated**: 2026-01-27
**Tested On**: `/Users/dongcheolshin/Sources/` project
**Next Review**: After Claude Code updates
