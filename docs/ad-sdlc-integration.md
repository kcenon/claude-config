# AD-SDLC Integration Guide

This document explains how to use claude-config resources in the [AD-SDLC (Agent-Driven SDLC)](https://github.com/kcenon/claude_code_agent) project.

## Overview

AD-SDLC is a platform that automates the software development lifecycle using 35 specialized AI agents (Greenfield, Enhancement, and Import modes). By referencing claude-config's Skills and Guidelines, agents can generate higher quality code. Since claude-config v2.3.0, the project also ships as an installable Claude Code plugin (`claude-config@2.3.0`) that exposes its Skills via the plugin runtime — see [Plugin Activation](#plugin-activation) below.

## Resource Mapping

### Skills → AD-SDLC Agents

| claude-config Skill | AD-SDLC Stage | Adoption | Notes |
|---------------------|---------------|----------|-------|
| `coding-guidelines` | worker | v0.1.0 auto-preload | AD-19 |
| `security-audit` | worker, pr-reviewer | v0.1.0 auto-preload | AD-19 |
| `code-quality` | pr-reviewer | v0.1.0 auto-preload | AD-19 |
| `pr-review` | pr-reviewer | v0.1.0 auto-preload | AD-19 |
| `ci-debugging` | ci-fixer | v0.1.0 auto-preload | AD-19 |
| `api-design` | sds-writer | manual reference | URL or plugin enable |
| `documentation` | prd-writer, srs-writer, sds-writer | manual reference | URL or plugin enable |
| `performance-review` | codebase-analyzer | manual reference | |
| `project-workflow` | controller, issue-generator | manual reference | |

### Guidelines → AD-SDLC Agents

| claude-config Guideline | Recommended AD-SDLC Agent | Purpose |
|-------------------------|---------------------------|---------|
| `coding-standards/general.md` | worker | General coding rules |
| `coding-standards/error-handling.md` | worker, ci-fixer | Error handling patterns |
| `coding-standards/concurrency.md` | worker | Concurrent code writing |
| `project-management/testing.md` | worker, regression-tester | Test writing rules |
| `security.md` | pr-reviewer | Security review checklist |
| `api-architecture/api-design.md` | sds-writer | REST/GraphQL design |

## Reference Methods

### Recommended (v0.1.0+): Plugin + SDK Skills Frontmatter

Since claude-config v2.3.0, install the plugin and let AD-SDLC v0.1.0+ agents auto-preload Skills via SDK frontmatter — no manual URL or clone is required:

```bash
# Inside a Claude Code session
/plugins install claude-config@2.3.0
/plugins enable claude-config
```

Once enabled, agents that declare `skills:` in their frontmatter receive the matching plugin Skills automatically at session start. AD-SDLC v0.1.0+ wires `worker`, `pr-reviewer`, and `ci-fixer` to auto-preload `coding-guidelines`, `security-audit`, `code-quality`, `pr-review`, and `ci-debugging`. Skills marked "manual reference" in the table above continue to use Methods 1-3 below.

### Method 1 (legacy): URL Reference in Agent Prompts

Add references to AD-SDLC agent definition files (`.claude/agents/*.md`):

```markdown
## Reference Guidelines

Follow these guidelines when generating code:
- [Coding Standards](https://github.com/kcenon/claude-config/blob/main/project/.claude/rules/coding/general.md)
- [Error Handling](https://github.com/kcenon/claude-config/blob/main/project/.claude/rules/coding/error-handling.md)
```

### Method 2 (legacy): Local Clone Reference

```bash
# Clone claude-config
git clone https://github.com/kcenon/claude-config.git ../claude-config

# Reference via relative path in agent prompts
# "Follow the rules in ../claude-config/project/.claude/rules/ when generating code"
```

### Method 3 (legacy): Direct Remote Reference

```bash
# View SKILL.md content
curl -s https://raw.githubusercontent.com/kcenon/claude-config/main/plugin/skills/coding-guidelines/SKILL.md

# View specific guideline
curl -s https://raw.githubusercontent.com/kcenon/claude-config/main/project/.claude/rules/coding/general.md
```

## Recommended References by Agent

### Worker Agent

Responsible for code implementation. Recommended references:

```markdown
## Code Generation Rules

Follow these guidelines when generating code:

1. **Naming Conventions**: claude-config/coding-standards/general.md
   - Variables: camelCase
   - Classes: PascalCase
   - Constants: UPPER_SNAKE_CASE

2. **Error Handling**: claude-config/coding-standards/error-handling.md
   - Use explicit error types
   - Provide appropriate error messages
   - Distinguish recoverable vs non-recoverable errors

3. **Testing**: claude-config/project-management/testing.md
   - AAA Pattern (Arrange-Act-Assert)
   - 80%+ coverage
   - Include edge cases
```

### PR Reviewer Agent

Responsible for code review. Recommended references:

```markdown
## Review Checklist

Review code against these criteria:

1. **Security**: claude-config/security.md
   - Input validation
   - SQL injection prevention
   - XSS prevention

2. **Code Quality**: claude-config/coding-standards/quality.md
   - Complexity (Cyclomatic Complexity < 10)
   - Remove duplicate code
   - SOLID principles compliance

3. **Performance**: claude-config/coding-standards/performance.md
   - Remove unnecessary operations
   - Appropriate data structure selection
   - Memory efficiency
```

### SDS Writer Agent

Responsible for design documentation. Recommended references:

```markdown
## API Design Guidelines

Follow these patterns for API design:

1. **REST API**: claude-config/api-architecture/api-design.md
   - Resource-oriented URL design
   - Appropriate HTTP method usage
   - Consistent response format

2. **Architecture**: claude-config/api-architecture/architecture.md
   - SOLID principles
   - Layer separation
   - Dependency injection
```

## Expected Benefits

| Aspect | Expected Benefit |
|--------|------------------|
| **Code Consistency** | Same coding style across the entire project |
| **Quality Improvement** | Leverage verified patterns and best practices |
| **Review Efficiency** | Reduce review time with clear criteria |
| **Security Enhancement** | Apply systematic security checklist |

## Plugin Activation

This section describes how AD-SDLC v0.1.0+ activates claude-config as a Claude Code plugin instead of relying on URL or clone-based references.

```bash
# Inside a Claude Code session
/plugins install claude-config@2.3.0
/plugins enable claude-config

# When AD-SDLC v0.1.0+ runs, worker / pr-reviewer / ci-fixer automatically
# preload the Skills declared as auto-preload in their frontmatter.
ad-sdlc run
```

Once `claude-config` is enabled at the session level, every agent definition that lists matching `skills:` entries receives the plugin Skills without further configuration. Agents whose stage is marked `manual reference` in the Skills table continue to consume Skills via URL or clone (Methods 1 and 2 above).

## Cautions

1. **Version Sync**: Verify reference URLs when claude-config is updated
2. **Project Customization**: Adjust guidelines to fit project characteristics
3. **Selective Application**: Apply only necessary guidelines, not all

## Related Links

- [claude-config Repository](https://github.com/kcenon/claude-config)
- [AD-SDLC Repository](https://github.com/kcenon/claude_code_agent)
- [Skills List (plugin)](../plugin/skills/)
- [Rules List](../project/.claude/rules/)
