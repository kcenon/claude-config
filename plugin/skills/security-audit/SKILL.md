---
name: security-audit
description: "Comprehensive security audit covering OWASP Top 10, input validation, authentication, authorization, secret management, dependency vulnerabilities, and injection attack prevention. Use when reviewing security posture, implementing auth flows, handling user input, auditing dependencies, conducting penetration test prep, or before production deployment."
allowed-tools: Read, Grep, Glob
model: sonnet
context: fork
agent: Explore
argument-hint: "<file-or-directory>"
---

# Security Audit Skill

## When to Use

- Implementing authentication/authorization
- Handling user input
- Working with sensitive data (passwords, tokens, keys)
- Security review requests
- Designing API endpoints

## Security Checklist

### Input Validation

- [ ] Validate all user input
- [ ] Prevent SQL Injection
- [ ] Prevent XSS
- [ ] Prevent Command Injection

### Authentication

- [ ] Secure password hashing
- [ ] Session management
- [ ] JWT security settings

### Authorization

- [ ] Permission verification
- [ ] Resource access control

## Reference Documents (Import Syntax)
@./reference/security.md
@./reference/error-handling.md
@./reference/api-design.md

## OWASP Top 10 Reference

1. Injection
2. Broken Authentication
3. Sensitive Data Exposure
4. XML External Entities (XXE)
5. Broken Access Control
6. Security Misconfiguration
7. Cross-Site Scripting (XSS)
8. Insecure Deserialization
9. Using Components with Known Vulnerabilities
10. Insufficient Logging & Monitoring

## Output

This skill runs in a forked context (`context: fork`) using the read-only `Explore` agent. It does not have access to the calling conversation's history — operate entirely from the supplied `<file-or-directory>` argument.

Return a structured report at the end of analysis:

```markdown
## Security Audit Report

| Category | Findings |
|----------|----------|
| Critical | N items |
| High | N items |
| Medium | N items |
| Low | N items |

### Critical Findings
1. `file.ext:line` — finding + recommended fix
2. ...

### High Findings
1. ...

### Coverage
- Files inspected: N
- OWASP categories evaluated: 1, 2, 3, ...
- Categories not applicable: ...
```
