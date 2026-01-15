---
paths:
  - "**/*.ts"
  - "**/*.js"
  - "**/*.py"
  - "**/*.go"
  - "**/*.java"
  - "**/*.rs"
  - "**/auth/**"
  - "**/security/**"
---

# Security Standards

## Input Validation

- Validate all external inputs
- Use allowlist validation over blocklist
- Sanitize data before use
- Validate on the server, not just client

## Authentication

- Use established libraries (never roll your own)
- Implement proper session management
- Use secure password hashing (bcrypt, argon2)
- Support multi-factor authentication

## Authorization

- Implement principle of least privilege
- Check authorization at every layer
- Use role-based access control (RBAC)
- Never expose internal IDs in URLs without validation

## Sensitive Data

- Never log sensitive information
- Use environment variables for secrets
- Encrypt data at rest and in transit
- Implement proper key management

## Common Vulnerabilities

### SQL Injection
- Use parameterized queries
- Never concatenate user input into queries

### XSS (Cross-Site Scripting)
- Escape output in HTML context
- Use Content Security Policy headers
- Sanitize HTML input

### CSRF
- Implement anti-CSRF tokens
- Verify Origin/Referer headers
- Use SameSite cookie attribute

## Dependencies

- Keep dependencies updated
- Audit for known vulnerabilities
- Use lockfiles for reproducibility
- Review new dependencies before adding
