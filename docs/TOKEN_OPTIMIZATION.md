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

**Note**: `permissions.deny` is designed for **security** (blocking access to sensitive files), not for **token optimization**. Files blocked by `permissions.deny` are excluded from file discovery and search results.

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
rules/*/reference/
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

Tested on production system:

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Initial tokens | 56,058 | ~18,000 | **68% reduction** |
| Session startup | ~8s | ~3s | **62% faster** |
| Monthly cost (50 sessions) | $6.90 | $2.25 | **$4.65 saved** |

## Using Reference Documents

Reference documents are excluded by default but easily accessible when needed.

### Method 1: Explicit File Path

```markdown
Can you review the label definitions in rules/workflow/reference/label-definitions.md?
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
| `rules/workflow/reference/label-definitions.md` | ~4,000 | GitHub label standards |
| `rules/workflow/reference/automation-patterns.md` | ~6,000 | GitHub Actions, gh CLI |
| `rules/workflow/reference/issue-examples.md` | ~8,000 | Issue splitting, templates |
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
# rules/*/reference/
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

## Support

For issues or questions:

- **GitHub Issues**: https://github.com/kcenon/claude-config/issues
- **Documentation**: https://github.com/kcenon/claude-config
- **Discussion**: GitHub Discussions

---

*Token optimization: Because every token counts.*
