# Security Rules

Organization-wide security rules that apply to all projects.

## Input Validation

> For detailed implementation patterns (SQL injection, XSS, path traversal), see `project/.claude/rules/security.md`.

- **MUST** validate all external input
- **MUST** sanitize data before database queries
- **MUST** encode output to prevent XSS

## Authentication

- **MUST** use organization-approved authentication methods
- **MUST NOT** store passwords in plain text
- **MUST** implement rate limiting on auth endpoints

## Secrets Management

- **MUST NOT** commit secrets to version control
- **MUST** use approved secret management tools
- **MUST** rotate secrets according to policy

## Dependencies

- **MUST** scan dependencies for vulnerabilities
- **MUST** keep dependencies updated
- **MUST NOT** use deprecated packages with known vulnerabilities

## Logging

- **MUST** log security-relevant events
- **MUST NOT** log sensitive data (passwords, tokens, PII)
- **MUST** use structured logging format

---

*Customize these rules according to your organization's security policy.*
