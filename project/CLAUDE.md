# Universal Development Guidelines

Version: 1.4.0
Last Updated: 2026-01-22

These guidelines define general conventions and practices for working in this repository. They emphasize clear procedures, maintainability, and security while allowing language‑specific details to be handled by the appropriate official guidelines.

> **Note**: This project configuration works together with global settings in `~/.claude/CLAUDE.md`. When conflicts occur, project settings take precedence.

## Core Guidelines (Import Syntax)

**CRITICAL:** Always consult environment settings first for timezone and locale context.

### Environment & Workflow
@claude-guidelines/environment.md
@claude-guidelines/workflow.md
@claude-guidelines/problem-solving.md
@claude-guidelines/communication.md
@claude-guidelines/git-commit-format.md
@claude-guidelines/common-commands.md

### Code Standards
@claude-guidelines/coding-standards/general.md
@claude-guidelines/coding-standards/quality.md
@claude-guidelines/coding-standards/error-handling.md
@claude-guidelines/operations/cleanup.md

### Technical
@claude-guidelines/coding-standards/concurrency.md
@claude-guidelines/coding-standards/memory.md
@claude-guidelines/coding-standards/performance.md

### Project Management
@claude-guidelines/project-management/build.md
@claude-guidelines/project-management/testing.md
@claude-guidelines/project-management/documentation.md

### Security & Operations
@claude-guidelines/security.md
@claude-guidelines/operations/monitoring.md

### API & Architecture
@claude-guidelines/api-architecture/api-design.md
@claude-guidelines/api-architecture/logging.md
@claude-guidelines/api-architecture/observability.md
@claude-guidelines/api-architecture/architecture.md

## Module Loading

Modules are auto-loaded via conditional loading based on task keywords and file types.
@claude-guidelines/conditional-loading.md

**Manual override:** `@load: security, performance` | `@skip: documentation` | `@focus: memory`

## Global vs Project Settings

| Scope | Controls |
|-------|----------|
| **Global** (`~/.claude/CLAUDE.md`) | Token display, conversation language, git identity |
| **Project** (this file) | Code standards, commit format, testing requirements |

**Priority:** Project settings override global settings when conflicts occur.

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

- **1.4.0** (2026-01-22): Adopted Import syntax (`@path/to/file`) for modular references
  - Replaced markdown links with Import syntax for better token efficiency
  - Supports recursive imports up to 5 levels deep
- **1.3.0** (2026-01-15): Split github-issue-5w1h.md (1,214 → 225 lines) with reference/ directory
- **1.2.1** (2026-01-15): Optimized conditional-loading.md (309 → 209 lines) for token efficiency
- **1.2.0** (2026-01-15): Simplified CLAUDE.md (212 → ~85 lines) for token efficiency
- **1.1.0** (2025-12-03): Refactored workflow.md into 5 focused sub-modules for token efficiency
- **1.0.0** (2025-12-03): Initial unified release with full guidelines

---

*These guidelines emphasize clear procedures, maintainability, and security while allowing language‑specific details to be handled by official language style guides (C++ Core Guidelines, Kotlin conventions, PEP 8, etc.).*
