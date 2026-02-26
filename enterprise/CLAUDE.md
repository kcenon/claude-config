# Organization Policy

Enterprise-level Claude Code configuration. Highest priority in the settings hierarchy.

> **Note**: Place at `/Library/Application Support/ClaudeCode/CLAUDE.md` (macOS),
> `/etc/claude-code/CLAUDE.md` (Linux), or `C:\Program Files\ClaudeCode\CLAUDE.md` (Windows).

## Security

- No secrets, API keys, or credentials in source code
- Use environment variables or secret management tools for sensitive data

## Code Standards

- All code must pass linting before merge
- All changes require code review
- Code comments, documentation, commit messages: English

## Version Control

- Main branch is protected; force push is prohibited
- Squash merge preferred
- Conventional commits format required

---

*Customize according to your organization's policies.*
*Last updated: 2026-02-26*
