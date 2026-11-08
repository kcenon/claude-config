---
alwaysApply: false
paths:
  - "**/docs/**"
  - "**/README*"
  - "**/CHANGELOG*"
---

# Documentation Standards

## API Documentation

Provide clear documentation for all public APIs and modules, using the language's
standard tool (Doxygen for C++, KDoc for Kotlin, docstrings for Python, TSDoc for
TypeScript). Cover purpose, parameters, return value, thrown errors, preconditions,
and thread-safety notes.

## README Files

Every project should have a comprehensive README covering: description, features,
prerequisites, installation (quick start), usage, configuration, API documentation,
development (build, tests, code style, contributing), architecture, license,
authors, acknowledgments, and support channels.

## CHANGELOG

Maintain a changelog following [Semantic Versioning](https://semver.org/) and the
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format: an `[Unreleased]`
section plus one section per version, each grouped into Added / Changed /
Deprecated / Removed / Fixed / Security, with compare links at the bottom.

### Version Number Guidelines

Given a version number `MAJOR.MINOR.PATCH`:

- **MAJOR**: Incompatible API changes
- **MINOR**: Backward-compatible functionality additions
- **PATCH**: Backward-compatible bug fixes

## Architecture Documentation

Provide a high-level architecture overview: a system diagram plus, per component,
its responsibility, technologies, and key classes or schemas.

## Inline Documentation

### When to Write Comments

**Do comment**:
- Complex algorithms or business logic
- Non-obvious design decisions
- Workarounds for bugs or limitations
- Public API interfaces

**Don't comment**:
- Obvious code that explains itself
- What the code does (code should be self-explanatory)
- Redundant information

Explain *why*, not *what*; when documenting a workaround, state the condition under
which it can be removed.

> Templates: see `.claude/reference/project-management/documentation-templates.md`
