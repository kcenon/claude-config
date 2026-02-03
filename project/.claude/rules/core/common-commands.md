---
alwaysApply: true
---

# Common Commands

> Quick reference for frequently used commands in this project

## Validation Scripts

- `./scripts/verify.sh`: Verify backup integrity and directory structure
- `./scripts/validate_skills.sh`: Validate SKILL.md files for format compliance

## Installation & Deployment

- `./scripts/install.sh`: Install settings to system (~/.claude/ and project)
- `./scripts/backup.sh`: Backup current system settings to repository
- `./scripts/sync.sh`: Synchronize settings between system and backup

## Hook Management

- `./hooks/install-hooks.sh`: Install pre-commit hooks for SKILL.md validation

## Git Operations

- `git status`: Check working tree status
- `git diff`: View unstaged changes
- `git add . && git commit -m "message"`: Stage and commit changes
- `git log --oneline -10`: View recent commit history

## GitHub CLI Commands

- `gh issue list --state open`: List open GitHub issues
- `gh issue view <number>`: View specific issue details
- `gh pr create --title "title" --body "body"`: Create pull request
- `gh pr list`: List pull requests

## Quick Checks

- `wc -l project/CLAUDE.md`: Check CLAUDE.md line count
- `find . -name "*.md" | wc -l`: Count markdown files in project
