---
alwaysApply: true
---

# Work Environment and Conditions

## Timezone Awareness

- **Standard timezone**: All dates and times must be expressed in **Asia/Seoul (KST/UTC+9)** timezone
- **Absolute dates**: Convert relative phrases (e.g., "today", "next week", "in 3 days") into absolute dates to avoid ambiguity
- **Example**: Instead of "tomorrow", use "2025-11-03" or "2025-11-03 14:00 KST"

## Current Information

- **Knowledge cutoff awareness**: When information may be newer than the model's knowledge cutoff, verify via web search
- **Explicit acknowledgment**: If no relevant up-to-date data is available, state this explicitly
- **Source citation**: When using web-fetched information, cite the source and date

## Default Locale

- **Location**: Unless specified otherwise, assume the user is located in **Uijeongbu-si, Gyeonggi-do, Republic of Korea**
- **Implications**:
  - Use Korean holidays and business hours when relevant
  - Consider local infrastructure and services
  - Apply Korean regulatory and compliance standards when applicable

## Environment Setup Considerations

When configuring development environments:

- **Time-sensitive operations**: Use Asia/Seoul timezone for logs, timestamps, and scheduled tasks
- **Localization**: Default to Korean (ko-KR) locale settings unless project requires otherwise
- **Regional services**: Prefer Korean cloud regions (e.g., ap-northeast-2 for AWS) for lower latency

## Common Commands

> Quick reference for frequently used commands in this project

### Project Scripts

- `./scripts/verify.sh`: Verify backup integrity and directory structure
- `./scripts/validate_skills.sh`: Validate SKILL.md files for format compliance
- `./scripts/install.sh`: Install settings to system (~/.claude/ and project)
- `./scripts/backup.sh`: Backup current system settings to repository
- `./scripts/sync.sh`: Synchronize settings between system and backup
- `./hooks/install-hooks.sh`: Install pre-commit hooks for SKILL.md validation

### Git Operations

- `git status`: Check working tree status
- `git diff`: View unstaged changes
- `git add . && git commit -m "message"`: Stage and commit changes
- `git log --oneline -10`: View recent commit history

### GitHub CLI Scripts

> Use `--json` flag when calling programmatically. See `tools/gh-cli-scripts.md` for full reference.

- `./scripts/gh/gh_issue_create.sh -r REPO -t "Title" --json`: Create issue
- `./scripts/gh/gh_issue_read.sh -r REPO -n NUM --json`: Read issue
- `./scripts/gh/gh_pr_create.sh -r REPO -t "Title" --json`: Create PR
- `./scripts/gh/gh_pr_read.sh -r REPO -n NUM --json`: Read PR
- `./scripts/gh/cleanup_branches.sh [PATH] --json`: Clean branches
