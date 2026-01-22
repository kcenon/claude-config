# AD-SDLC Integration Guide

This document explains how to use claude-config resources in the [AD-SDLC (Agent-Driven SDLC)](https://github.com/kcenon/claude_code_agent) project.

## Overview

AD-SDLC is a platform that automates the software development lifecycle using 27 specialized AI agents. By referencing claude-config's Skills and Guidelines, agents can generate higher quality code.

## Resource Mapping

### Skills → AD-SDLC Agents

| claude-config Skill | Recommended AD-SDLC Agent | Purpose |
|---------------------|---------------------------|---------|
| `coding-guidelines` | worker, code-reader | Apply naming/structure rules during code generation |
| `security-audit` | pr-reviewer, ci-fixer | Security vulnerability review |
| `performance-review` | code-reader, codebase-analyzer | Performance issue identification |
| `api-design` | sds-writer | API design pattern reference |
| `documentation` | prd-writer, srs-writer, sds-writer | Documentation standards |
| `project-workflow` | controller, issue-generator | Issue/PR management rules |

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

### Method 1: URL Reference in Agent Prompts

Add references to AD-SDLC agent definition files (`.claude/agents/*.md`):

```markdown
## Reference Guidelines

Follow these guidelines when generating code:
- [Coding Standards](https://github.com/kcenon/claude-config/blob/main/project/.claude/rules/coding/general.md)
- [Error Handling](https://github.com/kcenon/claude-config/blob/main/project/.claude/rules/coding/error-handling.md)
```

### Method 2: Local Clone Reference

```bash
# Clone claude-config
git clone https://github.com/kcenon/claude-config.git ../claude-config

# Reference via relative path in agent prompts
# "Follow the rules in ../claude-config/project/.claude/rules/ when generating code"
```

### Method 3: Direct Remote Reference

```bash
# View SKILL.md content
curl -s https://raw.githubusercontent.com/kcenon/claude-config/main/project/.claude/skills/coding-guidelines/SKILL.md

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

## Cautions

1. **Version Sync**: Verify reference URLs when claude-config is updated
2. **Project Customization**: Adjust guidelines to fit project characteristics
3. **Selective Application**: Apply only necessary guidelines, not all

## Related Links

- [claude-config Repository](https://github.com/kcenon/claude-config)
- [AD-SDLC Repository](https://github.com/kcenon/claude_code_agent)
- [Skills List](../project/.claude/skills/)
- [Rules List](../project/.claude/rules/)
