# Organization Policy

This is the enterprise-level Claude Code configuration that applies to all users
in the organization. Settings here have the highest priority in the memory hierarchy.

> **Note**: This file should be placed in the system-wide location:
> - **macOS**: `/Library/Application Support/ClaudeCode/CLAUDE.md`
> - **Linux**: `/etc/claude-code/CLAUDE.md`
> - **Windows**: `C:\Program Files\ClaudeCode\CLAUDE.md`

## Security Requirements

### Code Security
- All commits must be signed with GPG keys
- No secrets, API keys, or credentials in source code
- Use environment variables or secret management tools for sensitive data
- Required: security review for authentication-related changes

### Access Control
- Follow principle of least privilege
- Document all permission requirements
- Regular access audits required

## Compliance

### Data Handling
- Follow organization's data classification policy
- GDPR compliance for personal data
- Audit logging for sensitive operations
- Data retention policies must be followed

### Documentation
- All public APIs must be documented
- Security-relevant decisions require ADR (Architecture Decision Records)
- Change logs must be maintained

## Approved Tools and Libraries

### Package Management
- Use only approved package registries
- All dependencies must pass security scanning
- Version pinning required for production dependencies

### Container Images
- Docker images must be from approved registry
- Base images must be scanned and approved
- No `latest` tags in production

## Code Standards

### Quality Gates
- All code must pass linting before merge
- Test coverage minimum: 80%
- No high/critical security vulnerabilities

### Review Requirements
- All changes require code review
- Security-sensitive changes require security team approval
- Breaking changes require architecture review

## Communication

### Language Policy
- Code comments: English
- Documentation: English
- Commit messages: English

## Version Control

### Branch Protection
- Main branch is protected
- Force push is prohibited
- Squash merge preferred

### Commit Standards
- Conventional commits format required
- Reference issue/ticket in commits
- Sign-off required

---

*This is a template. Customize according to your organization's policies.*
*Last updated: 2026-01-22*
