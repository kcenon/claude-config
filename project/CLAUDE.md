# Universal Development Guidelines

Version: 1.1.0
Last Updated: 2025-12-03

These guidelines define general conventions and practices for working in this repository. They emphasize clear procedures, maintainability, and security while allowing language‑specific details to be handled by the appropriate official guidelines.

> **Note**: This project configuration works together with global settings in `~/.claude/CLAUDE.md`. When conflicts occur, project settings take precedence.

## Quick Reference

<table>
<tr>
<td width="50%">

**Getting Started**
- [Environment Settings](claude-guidelines/environment.md)
- [Question Handling](claude-guidelines/workflow.md)
- [Problem Solving](claude-guidelines/problem-solving.md)
- [Language Conventions](claude-guidelines/communication.md)

</td>
<td width="50%">

**Code Development**
- [Coding Guidelines](claude-guidelines/coding-standards/general.md)
- [Code Quality](claude-guidelines/coding-standards/quality.md)
- [Error Handling](claude-guidelines/coding-standards/error-handling.md)
- [Testing](claude-guidelines/project-management/testing.md)

</td>
</tr>
</table>

## Complete Guidelines Index

### Environment and Workflow

| # | Guideline | Focus Area |
|---|-----------|------------|
| 01 | [Work Environment and Conditions](claude-guidelines/environment.md) | Timezone, locale settings |
| 02 | [Workflow Guidelines](claude-guidelines/workflow.md) | Request analysis, planning |
| 02a | → [Question Handling](claude-guidelines/workflow/question-handling.md) | Translate, analyze, present |
| 02b | → [Problem Solving](claude-guidelines/workflow/problem-solving.md) | Systematic approach, minimal changes |
| 02c | → [Performance Analysis](claude-guidelines/workflow/performance-analysis.md) | Codebase performance analysis |
| 02d | → [GitHub Issue Guidelines](claude-guidelines/workflow/github-issue-5w1h.md) | 5W1H framework for issues |
| 02e | → [GitHub PR Guidelines](claude-guidelines/workflow/github-pr-5w1h.md) | 5W1H framework for PRs |
| 03 | [Problem‑Solving Principles](claude-guidelines/problem-solving.md) | Systematic approach, minimal changes |
| 04 | [Response Language and Documentation](claude-guidelines/communication.md) | Korean responses, English code |
| 05 | [Git and Commit Settings](claude-guidelines/git-commit-format.md) | Commit format, versioning |

### Code Standards

| # | Guideline | Focus Area |
|---|-----------|------------|
| 06 | [Universal Coding Guidelines](claude-guidelines/coding-standards/general.md) | Naming, modularity, comments |
| 07 | [Code Quality and Maintainability](claude-guidelines/coding-standards/quality.md) | Complexity, refactoring, immutability |
| 17 | [Cleanup and Finalisation](claude-guidelines/operations/cleanup.md) | Formatting, linting, cleanup |

### Technical Implementation

| # | Guideline | Focus Area |
|---|-----------|------------|
| 08 | [Exception and Error Handling](claude-guidelines/coding-standards/error-handling.md) | Error patterns, validation |
| 09 | [Concurrency](claude-guidelines/coding-standards/concurrency.md) | Thread safety, async patterns |
| 10 | [Memory Management](claude-guidelines/coding-standards/memory.md) | RAII, GC, leak detection |
| 11 | [Performance Optimisation](claude-guidelines/coding-standards/performance.md) | Profiling, caching, algorithms |

### Project Management

| # | Guideline | Focus Area |
|---|-----------|------------|
| 12 | [Build and Dependency Management](claude-guidelines/project-management/build.md) | Lock files, versioning, security |
| 13 | [Testing Strategy](claude-guidelines/project-management/testing.md) | Unit, integration, E2E tests |
| 14 | [Documentation](claude-guidelines/project-management/documentation.md) | API docs, README, ADR |

### Security and Operations

| # | Guideline | Focus Area |
|---|-----------|------------|
| 15 | [Security and Sensitive Information](claude-guidelines/security.md) | Input validation, secure storage |
| 16 | [Performance Metrics](claude-guidelines/operations/monitoring.md) | Monitoring, alerting, SLOs |

### API and Architecture

| # | Guideline | Focus Area |
|---|-----------|------------|
| 18 | [API Design](claude-guidelines/api-architecture/api-design.md) | REST, GraphQL, versioning |
| 19 | [Logging Standards](claude-guidelines/api-architecture/logging.md) | Structured logging, levels |
| 20 | [Observability](claude-guidelines/api-architecture/observability.md) | Metrics, traces, health checks |
| 21 | [Architecture and Design](claude-guidelines/api-architecture/architecture.md) | SOLID, patterns, microservices |

## Intelligent Module Loading

Claude Code uses **[Conditional Loading Rules](claude-guidelines/conditional-loading.md)** to automatically select relevant modules based on:
- Task keywords in your request
- File types you're working with
- Context and development phase
- Token optimization (saves ~60-70%)

### Manual Override

You can manually control module loading:
```markdown
@load: security, performance  # Force load specific modules
@skip: documentation          # Skip specific modules
@focus: memory-optimization   # Set primary focus
```

## Guidelines by Task Type

### Writing New Code
**Start here:** 06 → 07 → 08 → 13

Focus on coding standards, quality, error handling, and testing.

### Reviewing Code
**Start here:** 07 → 15 → 21 → 06

Emphasize quality, security, architecture, and coding standards.

### Performance Optimization
**Start here:** 16 → 11 → 09 → 10

Profile first, then optimize concurrency and memory.

### Security Audit
**Start here:** 15 → 08 → 18 → 12

Check security, error handling, API design, and dependencies.

### Designing Architecture
**Start here:** 21 → 18 → 09 → 20

Architecture patterns, API design, concurrency, observability.

### Debugging Issues
**Start here:** 19 → 20 → 08 → 11

Leverage logging, observability, error handling, and profiling.

### Writing Documentation
**Start here:** 14 → 18 → 04

Documentation standards, API docs, language conventions.

### Setting Up Project
**Start here:** 12 → 05 → 13 → 17

Dependencies, git, testing, cleanup.

## Quick Reference by Task

| Task | Auto-Loaded Modules | Additional on Detection |
|------|-------------------|------------------------|
| **Writing new code** | General, Quality, Error Handling | Language-specific based on file extension |
| **Fixing bugs** | Error Handling, Quality, Testing | Memory/Concurrency if crash-related |
| **Performance optimization** | Performance, Monitoring, Memory | Concurrency if parallel processing |
| **Adding tests** | Testing, Quality | Error Handling for edge cases |
| **Code review** | ALL Standards, Security, Quality | Full comprehensive load |
| **Git operations** | Git Commit Format, Workflow | Communication for PR descriptions |
| **Security audit** | Security, Error Handling | Monitoring for security events |
| **Documentation** | Documentation, Communication | Skip all coding standards |
| **Build issues** | Build, Dependencies, Security | Monitoring for production |
| **Architecture design** | Architecture, API Design, Observability | Concurrency, Performance |

## Integration with Global Settings

### Global Settings Control:
- Token usage display
- Conversation language (Korean)
- Git user identity

### Project Settings Control:
- Code and documentation language (English)
- Coding standards and conventions
- Commit message format (`type(scope): description`)
- Testing and security requirements

### Priority Rules:
1. **Project settings override global settings** when conflicts occur
2. **Both apply** when addressing different aspects
3. **Explicit in project** - Project guidelines take precedence

## Usage Notes

- **Token Efficiency**: Reference only relevant guidelines for your specific task
- **Language-Specific**: These are universal guidelines; defer to language-specific conventions (e.g., PEP 8 for Python, C++ Core Guidelines) when appropriate
- **Examples**: Each guideline includes detailed, language-specific examples
- **Progressive Depth**: Guidelines use collapsible sections for detailed examples
- **Output Token Limit**: File generation may be interrupted due to output token limits. Use these strategies for large files:
  1. Split files into logical sections and generate across multiple turns
  2. Create basic structure first, then add content section by section using Edit tool
  3. Generate within output token limit (~16,000 tokens) per response
  4. Use clear markers to continue writing if generation is interrupted

## Contributing

When adding new guidelines:
1. Follow the established format with collapsible example sections
2. Include examples for multiple languages (TypeScript, Python, Kotlin, C++)
3. Provide both good and bad examples
4. Update this index with the new guideline

## Version History

- **1.1.0** (2025-12-03): Refactored workflow.md into 5 focused sub-modules for token efficiency
- **1.0.0** (2025-12-03): Initial unified release with full guidelines

---

*These guidelines emphasize clear procedures, maintainability, and security while allowing language‑specific details to be handled by official language style guides (C++ Core Guidelines, Kotlin conventions, PEP 8, etc.).*
