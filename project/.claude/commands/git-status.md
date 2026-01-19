# Git Status Command

Comprehensive git repository status with actionable insights.

## Usage

```
/git-status
```

## Arguments

None (operates on current repository)

## Options

| Option | Default | Description |
|--------|---------|-------------|
| --commits | 5 | Number of recent commits to show |
| --verbose | false | Include file diff stats |
| --check-remote | true | Check remote sync status |

## Instructions

Analyze the current git state and provide:

### 1. Working Directory Status
- Modified files
- Untracked files
- Staged changes
- Deleted files

### 2. Branch Information
- Current branch name
- Ahead/behind remote
- Last commit info
- Branch age

### 3. Recent Activity
- Last 5 commits summary
- Contributors this week
- Files most changed recently

### 4. Potential Issues
- Uncommitted changes warning
- Large file warnings
- Merge conflict detection
- Stale branch detection

## Output Format

```markdown
## Git Status Report

### Current State
- Branch: `[BRANCH_NAME]`
- Status: [CLEAN / HAS_CHANGES]
- Remote: [UP_TO_DATE / AHEAD / BEHIND]

### Changes
#### Staged (X files)
- [file list]

#### Modified (X files)
- [file list]

#### Untracked (X files)
- [file list]

### Recent Commits
1. [hash] [message] - [author] ([time])
2. ...

### Recommendations
- [Actionable suggestions]
```

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| git installed | "Git is not installed" | Install git from https://git-scm.com |
| In git repository | "Not a git repository" | Navigate to a git repo or run `git init` |
| Valid git state | "Corrupted git repository" | Run `git fsck` to diagnose |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| No remote configured | Report "No remote configured - showing local status only" | Add remote with `git remote add origin <url>` |
| Remote unreachable | Report "Cannot reach remote - showing cached status" | Check network connection |
| Detached HEAD | Report current commit hash and warn about detached state | Create branch with `git checkout -b <name>` |
| Merge in progress | Report merge status and conflicting files | Complete or abort merge |
| Rebase in progress | Report rebase status and current step | Continue or abort rebase |
| Lock file exists | Report "Repository locked by another process" | Wait or remove `.git/index.lock` |
