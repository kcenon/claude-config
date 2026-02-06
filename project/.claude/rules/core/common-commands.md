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

## GitHub CLI Scripts (scripts/gh/)

> Use `--json` flag when calling programmatically. See `.claude/rules/tools/gh-cli-scripts.md` for full reference.

- `./scripts/gh/gh_issue_create.sh -r REPO -t "Title" --json`: Create issue → `{"url":"...","number":N}`
- `./scripts/gh/gh_issue_read.sh -r REPO -n NUM --json`: Read issue → structured JSON
- `./scripts/gh/gh_issue_comment.sh -r REPO -n NUM -b "Text" --json`: Comment → `{"url":"..."}`
- `./scripts/gh/gh_issues.sh -r REPO --json`: List issues → JSON array
- `./scripts/gh/gh_pr_create.sh -r REPO -t "Title" --json`: Create PR → `{"url":"...","number":N}`
- `./scripts/gh/gh_pr_read.sh -r REPO -n NUM --json`: Read PR → structured JSON
- `./scripts/gh/gh_pr_comment.sh -r REPO -n NUM -b "Text" --json`: Comment → `{"url":"..."}`
- `./scripts/gh/cleanup_branches.sh [PATH] --json`: Clean branches → summary JSON

## Quick Checks

- `wc -l project/CLAUDE.md`: Check CLAUDE.md line count
- `find . -name "*.md" | wc -l`: Count markdown files in project
