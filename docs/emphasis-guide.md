# Documentation Emphasis Guidelines

> **Version**: 1.0.0
> **Last Updated**: 2026-01-22
> **Reference**: [Claude Code Best Practices - Anthropic](https://www.anthropic.com/engineering/claude-code-best-practices)

This document defines standard emphasis expressions to improve Claude's instruction following in CLAUDE.md files and related documentation.

## Purpose

Anthropic's official guide recommends:

> "Add emphasis markers like 'IMPORTANT' or 'YOU MUST' when needed"

Proper use of emphasis expressions helps Claude:
- Identify critical instructions that must not be ignored
- Distinguish between mandatory rules and optional preferences
- Prioritize conflicting instructions appropriately

## Emphasis Levels

### CRITICAL Level (Must Follow)

Use for absolute requirements that should never be violated.

| Marker | Usage | Example |
|--------|-------|---------|
| **NEVER** | Absolute prohibition | **NEVER** commit secrets to version control |
| **ALWAYS** | Mandatory action | **ALWAYS** validate user input before processing |
| **YOU MUST** | Required behavior | **YOU MUST** handle all errors explicitly |

### IMPORTANT Level (Should Follow)

Use for key guidelines that significantly impact quality or security.

| Marker | Usage | Example |
|--------|-------|---------|
| **IMPORTANT** | Key guideline | **IMPORTANT**: All API responses must include error codes |
| **WARNING** | Potential issues | **WARNING**: This operation modifies global state |
| **NOTE** | Contextual information | **NOTE**: This applies only to production environments |

### PREFERRED Level (Nice to Have)

Use for best practices and suggestions.

| Marker | Usage | Example |
|--------|-------|---------|
| **RECOMMENDED** | Best practice | **RECOMMENDED**: Use dependency injection for testability |
| **PREFER** | Suggested approach | **PREFER** const over let when value won't change |
| **CONSIDER** | Optional suggestion | **CONSIDER** caching for frequently accessed data |

## Application Guidelines

### DO

1. **Use NEVER/ALWAYS for security-related requirements**
   ```markdown
   **NEVER** log passwords, tokens, or API keys.
   **ALWAYS** use parameterized queries to prevent SQL injection.
   ```

2. **Use YOU MUST for core coding rules**
   ```markdown
   **YOU MUST** validate all external input at system boundaries.
   **YOU MUST** handle all exceptions explicitly (no silent failures).
   ```

3. **Use IMPORTANT for context that affects behavior**
   ```markdown
   **IMPORTANT**: Project settings override global settings when conflicts occur.
   **IMPORTANT**: All user-facing messages must be in English.
   ```

4. **Use WARNING for potential pitfalls**
   ```markdown
   **WARNING**: Modifying this configuration affects all services.
   **WARNING**: This operation cannot be undone.
   ```

### DON'T

1. **Don't overuse emphasis in every sentence**
   ```markdown
   # BAD
   **IMPORTANT**: Use clear names. **IMPORTANT**: Follow conventions.
   **IMPORTANT**: Write tests. **IMPORTANT**: Document APIs.

   # GOOD
   **IMPORTANT**: Follow these naming conventions:
   - Use clear, descriptive names
   - Follow language-specific conventions
   - Write tests for all public APIs
   ```

2. **Don't use MUST for preferences**
   ```markdown
   # BAD
   **YOU MUST** use tabs for indentation.

   # GOOD
   **PREFER** tabs for indentation (configurable via .editorconfig).
   ```

3. **Don't nest or combine emphasis expressions**
   ```markdown
   # BAD
   **VERY IMPORTANT**: Do this thing.
   **CRITICAL WARNING**: Avoid this.

   # GOOD
   **IMPORTANT**: Do this thing.
   **WARNING**: Avoid this.
   ```

4. **Don't use emphasis for obvious statements**
   ```markdown
   # BAD
   **IMPORTANT**: Functions should have names.

   # GOOD (no emphasis needed)
   Functions should have descriptive names that indicate their purpose.
   ```

## Formatting Standards

### Bold with Double Asterisks

Always use `**MARKER**` format (not `*MARKER*` or `__MARKER__`):

```markdown
**NEVER** do this.
**IMPORTANT**: Remember this.
```

### Colon Placement

- Use colon after IMPORTANT, WARNING, NOTE, RECOMMENDED
- No colon after NEVER, ALWAYS, YOU MUST (they flow into the sentence)

```markdown
**IMPORTANT**: This is a key point.
**NEVER** skip input validation.
**YOU MUST** follow this rule.
```

### Paragraph Placement

Place emphasis at the start of paragraphs or list items:

```markdown
**IMPORTANT**: All commits must follow the Conventional Commits format.

Guidelines:
- **NEVER** include AI attribution in commit messages
- **ALWAYS** use English for commit messages
- **PREFER** present tense ("add" not "added")
```

## Security Rules Emphasis

Security-related rules should always use CRITICAL level markers:

```markdown
# Security Guidelines

**NEVER** commit secrets (API keys, passwords, tokens) to version control.

**NEVER** trust user input without validation. **ALWAYS**:
- Sanitize HTML to prevent XSS
- Use parameterized queries for SQL
- Validate file paths to prevent traversal attacks

**YOU MUST** encrypt sensitive data at rest and in transit.

**WARNING**: Authentication changes require security team review.
```

## Error Handling Emphasis

Error handling rules should use appropriate levels:

```markdown
# Error Handling

**YOU MUST** handle all errors explicitly. Silent failures are prohibited.

**NEVER** use empty catch blocks:
```cpp
// BAD
try { operation(); } catch (...) { }

// GOOD
try { operation(); } catch (const std::exception& e) {
    logger.error("Operation failed", e.what());
    throw;
}
```

**IMPORTANT**: Include sufficient context when propagating errors.

**RECOMMENDED**: Use structured error types for domain-specific errors.
```

## Commit and PR Rules Emphasis

Attribution rules should use CRITICAL level:

```markdown
# Commit Message Format

**IMPORTANT**: Use the Conventional Commits format: `type(scope): description`

**NEVER** include:
- AI/Claude attribution
- Emojis
- Co-Authored-By: Claude lines

**ALWAYS** use English for commit messages.
```

## Verification Checklist

Before finalizing documentation, verify:

- [ ] Security requirements use NEVER/ALWAYS/YOU MUST
- [ ] Core coding rules use YOU MUST
- [ ] Supporting guidelines use IMPORTANT/WARNING/NOTE
- [ ] Preferences use RECOMMENDED/PREFER/CONSIDER
- [ ] No overuse of emphasis (emphasize only essentials)
- [ ] No nested emphasis expressions
- [ ] Consistent formatting throughout

## References

- [Claude Code Best Practices - Anthropic](https://www.anthropic.com/engineering/claude-code-best-practices)
- Related Issue: #65

---

*This guide is part of the claude-config documentation optimization initiative.*
