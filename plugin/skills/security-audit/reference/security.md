# Security and Sensitive Information

## Input Validation

**YOU MUST** validate all user input before processing.

- Validate all external inputs
- Use allowlist validation over blocklist
- Sanitize data before use
- Validate on the server, not just client

### Validate All External Input

**NEVER** trust data from external sources. **ALWAYS** validate and sanitize type,
length, format (email, URL, ...), and range at the boundary of the system.

### Prevent Injection Attacks

- **SQL injection**: parameterized queries only; never concatenate user input into a query
- **Command injection**: use safe library APIs (e.g. `std::filesystem`, argument-list process spawning) instead of shell execution with user input
- **XSS**: escape HTML entities or assign `textContent`; never write user input into `innerHTML`

### Path Traversal Prevention

Resolve user-supplied paths to an absolute path and reject any result that does not
stay inside the intended base directory.

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

## Secure Storage

### Never Hard-Code Credentials

**NEVER** hard-code credentials in source code. Load them from environment variables
or from a configuration file that is excluded from version control.

### Mask Sensitive Data in Logs

**NEVER** log passwords, tokens, or API keys in plain text. Replace the values of
sensitive fields with a mask before the message reaches the logger.

### Secure Password Handling

Hash passwords with a random per-user salt and a slow KDF (argon2, bcrypt, or PBKDF2
with at least 100,000 iterations); compare hashes, never plaintext.

## Dependency Scanning

### Regular Vulnerability Checks

Run the ecosystem's scanner regularly: `vcpkg upgrade` (C++), `safety check` /
`pip-audit` (Python), `npm audit` (Node.js), `gradle dependencyCheckAnalyze`
(Kotlin/Java).

### Pin Versions

**RECOMMENDED**: Pin dependency versions to prevent supply chain attacks. Use exact
versions for security-critical packages and commit lock files.

### Automated Scanning in CI/CD

Run a vulnerability scanner (e.g. Snyk, Trivy) on every push and pull request and
upload the results to the repository's code-scanning dashboard.

## Security Best Practices

**IMPORTANT**: Follow these security best practices for all code.

- **Principle of least privilege**: drop elevated privileges before performing sensitive operations
- **Secure defaults**: TLS on, weak ciphers off, empty CORS allowlist; insecure options require explicit opt-in and log a warning
- **Rate limiting**: limit requests per client on externally reachable endpoints

> Examples: see `.claude/reference/security-examples.md`
