# Custom Extensions vs Official Features

This document clarifies which features in this configuration are **official Claude Code features** versus **custom extensions** implemented specifically for this project.

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
| **CLAUDE.md memory hierarchy** | 5-tier memory system (Enterprise, Project, Rules, User, Local) | [Memory documentation](https://docs.anthropic.com/en/docs/claude-code) |
| **`.claude/rules/` directory** | Auto-loaded rule files with YAML frontmatter | Official feature |
| **YAML frontmatter** | `paths` and `alwaysApply` for conditional loading | Official feature |
| **settings.json** | Hook configuration (PreToolUse, PostToolUse, etc.) | Official feature |
| **Hook events** | SessionStart, SessionEnd, UserPromptSubmit, Stop, etc. | Official feature |
| **`.claudeignore`** | Exclude files from context loading | Official feature |
| **Skills** | SKILL.md with name and description frontmatter | Official feature |
| **Agents** | Agent configuration files | Official feature |
| **Commands** | Custom slash commands in `.claude/commands/` | Official feature |

### Custom Extensions (This Project Only)

These features are **custom implementations** specific to this configuration and are **NOT portable**:

| Feature | Description | Portable? |
|---------|-------------|-----------|
| **`@./module.md` import syntax** | Inline file references in markdown | No |
| **`@load:` directive** | Force-load specific modules | No |
| **`@skip:` directive** | Exclude specific modules | No |
| **`@focus:` directive** | Set focus area | No |
| **Phase-based token optimization** | 4-phase loading strategy design | No |
| **Module caching strategy** | HOT/WARM/COLD tier design | No |
| **Markov chain prediction** | Command prediction for prefetching | No |
| **Custom settings.json fields** | `description`, `version` fields | No |
| **5W1H issue framework** | Structured issue templates | Guidelines only |
| **Global commands** | `/issue-work`, `/release`, etc. | Config-specific |

## Detailed Breakdown

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
4. **Global commands** - Require installation to `~/.claude/commands/`

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

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Memory Hierarchy](https://docs.anthropic.com/en/docs/claude-code/memory)
- [Rules and Settings](https://docs.anthropic.com/en/docs/claude-code/settings)
- [Hooks Configuration](https://docs.anthropic.com/en/docs/claude-code/hooks)

## Reporting Issues

If a feature from this configuration doesn't work:

1. Check if it's an official feature or custom extension (this document)
2. For official features: Report to [Claude Code Issues](https://github.com/anthropics/claude-code/issues)
3. For custom extensions: Report to [this repository's issues](https://github.com/kcenon/claude-config/issues)

---

*Version: 1.0.0 | Last updated: 2026-02-03*
