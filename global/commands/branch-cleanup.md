# Branch Cleanup Command

Clean up merged and stale branches from local and remote repositories.

## Usage

```
/branch-cleanup [<project-name>] [options]
/branch-cleanup [--dry-run] [--include-remote] [--stale-days <days>]
```

**Example**:
```
/branch-cleanup                                    # Clean current repo, local only
/branch-cleanup --dry-run                          # Preview what would be deleted
/branch-cleanup hospital_erp_system                # Clean specific project
/branch-cleanup --include-remote --stale-days 30  # Include remote, 30-day threshold
```

## Arguments

- `<project-name>`: Optional project directory name (defaults to current directory)

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--dry-run` | flag | false | Preview branches without deleting |
| `--include-remote` | flag | false | Also clean remote tracking branches |
| `--stale-days` | number | 90 | Days since last commit to consider stale |

## Protected Branches

The following branches are **never deleted**, regardless of their merge status:

| Branch Pattern | Rationale |
|----------------|-----------|
| `main` | Primary production branch |
| `master` | Legacy primary branch |
| `develop` | Development integration branch |
| `release/*` | Release preparation branches |
| `hotfix/*` | Emergency fix branches |

## Instructions

Execute the following workflow:

### 1. Navigate to Project

```bash
# If project name provided
cd <project-name> 2>/dev/null || { echo "Error: Project directory not found"; exit 1; }

# Fetch latest remote state
git fetch --prune origin
```

### 2. Identify Merged Branches

```bash
# Get current branch
CURRENT_BRANCH=$(git branch --show-current)

# List branches merged into main/master
MERGED_BRANCHES=$(git branch --merged main 2>/dev/null || git branch --merged master)

# Filter out protected branches and current branch
echo "$MERGED_BRANCHES" | grep -v -E "^\*|main|master|develop|release/|hotfix/"
```

### 3. Identify Stale Branches

```bash
# Find branches with no commits in the last N days
STALE_THRESHOLD=$(date -d "$STALE_DAYS days ago" +%s 2>/dev/null || date -v-${STALE_DAYS}d +%s)

for branch in $(git branch --format='%(refname:short)'); do
    LAST_COMMIT=$(git log -1 --format='%ct' "$branch" 2>/dev/null)
    if [[ -n "$LAST_COMMIT" && "$LAST_COMMIT" -lt "$STALE_THRESHOLD" ]]; then
        echo "$branch (stale: no commits in $STALE_DAYS days)"
    fi
done
```

### 4. Display Branches for Cleanup

Present categorized results:

```markdown
## Branches Identified for Cleanup

### Merged Branches (safe to delete)
- feat/issue-123-add-login
- fix/issue-456-null-check

### Stale Branches (no commits in 90+ days)
- feat/old-experiment (last commit: 2024-06-15)
- fix/abandoned-fix (last commit: 2024-05-20)

### Protected Branches (will NOT be deleted)
- main
- develop
- release/v2.0
```

### 5. Confirm Deletion

If `--dry-run` is NOT specified:

```bash
# Prompt for confirmation
echo "Delete the above branches? (y/N)"
read -r CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi
```

### 6. Delete Local Branches

```bash
for branch in $BRANCHES_TO_DELETE; do
    # Skip protected branches
    if [[ "$branch" =~ ^(main|master|develop|release/|hotfix/) ]]; then
        echo "Skipping protected branch: $branch"
        continue
    fi

    # Delete local branch
    git branch -d "$branch" 2>/dev/null || git branch -D "$branch"
    echo "Deleted local branch: $branch"
done
```

### 7. Delete Remote Branches (if --include-remote)

```bash
if [[ "$INCLUDE_REMOTE" == "true" ]]; then
    for branch in $REMOTE_BRANCHES_TO_DELETE; do
        # Skip protected branches
        if [[ "$branch" =~ ^(main|master|develop|release/|hotfix/) ]]; then
            echo "Skipping protected remote branch: $branch"
            continue
        fi

        git push origin --delete "$branch"
        echo "Deleted remote branch: $branch"
    done
fi
```

### 8. Report Results

Provide summary of actions taken.

## Policies

| Item | Rule |
|------|------|
| Protected branches | Never delete main, master, develop, release/*, hotfix/* |
| Current branch | Never delete the currently checked-out branch |
| Confirmation | Always require confirmation unless --dry-run |
| Remote deletion | Only with explicit --include-remote flag |

## Output

After completion, provide summary:

```markdown
## Branch Cleanup Summary

| Item | Value |
|------|-------|
| Project | <project-name> |
| Mode | Dry-run / Executed |
| Stale threshold | 90 days |

### Deleted Branches
| Branch | Type | Last Commit |
|--------|------|-------------|
| feat/issue-123 | merged | 2024-12-01 |
| fix/old-bug | stale | 2024-06-15 |

### Skipped Branches
| Branch | Reason |
|--------|--------|
| main | Protected |
| develop | Protected |
| feat/current-work | Current branch |

### Statistics
- Local branches deleted: N
- Remote branches deleted: N
- Total branches cleaned: N
```

## Error Handling

### Prerequisites Check

| Requirement | Error Message | Resolution |
|-------------|---------------|------------|
| git installed | "Git is not installed" | Install git from https://git-scm.com |
| Inside git repo | "Not a git repository" | Navigate to a git repository |
| Project directory exists | "Project directory not found: [path]" | Verify project path |

### Runtime Errors

| Error Condition | Behavior | User Action |
|-----------------|----------|-------------|
| No branches to clean | Report "No merged or stale branches found" | No action needed |
| Branch deletion failed | Report specific branch and error, continue with others | Check if branch has unmerged changes |
| Remote deletion failed | Report "Cannot delete remote branch: [name]" | Verify remote permissions |
| Protected branch in list | Skip automatically with warning | No action needed |
| Current branch selected | Skip automatically | Checkout different branch first |
| Network error (remote) | Report "Cannot reach remote - check connection" | Verify internet connection |
