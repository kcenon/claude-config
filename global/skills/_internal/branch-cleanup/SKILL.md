---
name: branch-cleanup
description: Clean up merged and stale branches from local and remote repositories. Use when branch list is cluttered or after merging PRs.
argument-hint: "[project-name] [--execute] [--include-remote]"
user-invocable: true
disable-model-invocation: true
context: fork
allowed-tools: "Bash(git *)"
loop_safe: false
iso_class: none
---

# Branch Cleanup Command

Clean up merged and stale branches from local and remote repositories.

## Usage

```
/branch-cleanup [<project-name>] [options]
/branch-cleanup [--execute] [--include-remote] [--stale-days <days>]
```

**Example**:
```
/branch-cleanup                                    # Dry-run preview (default), local only
/branch-cleanup --execute                          # Actually delete the previewed branches
/branch-cleanup hospital_erp_system                # Preview specific project
/branch-cleanup --execute --include-remote --stale-days 30  # Delete, include remote, 30-day threshold
```

## Arguments

- `<project-name>`: Optional project directory name (defaults to current directory)

## Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--execute` | flag | false | Actually delete branches. Without it, the command is a read-only dry-run preview. |
| `--include-remote` | flag | false | Also clean remote tracking branches |
| `--stale-days` | number | 90 | Days since last commit to consider stale |

By default (no `--execute`) the command performs a **read-only dry-run preview** and deletes nothing.
Confirmation happens at invocation time by adding `--execute` — there is no interactive mid-run prompt,
so the command is scriptable.

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

# List branches merged into develop, main, or master
MERGED_BRANCHES=$(
  { git branch --merged develop 2>/dev/null; \
    git branch --merged main 2>/dev/null; \
    git branch --merged master 2>/dev/null; } | sort -u
)

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

### 5. Gate Deletion on --execute

The default run is a read-only dry-run preview. Stop here unless `--execute` was passed —
the user confirms by re-invoking with the flag, so there is no interactive prompt.

```bash
# Without --execute, this is a preview only: report and exit without deleting.
if [[ "$EXECUTE" != "true" ]]; then
    echo "Dry-run preview only. Re-run with --execute to delete the above branches."
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

See [_policy.md](../_policy.md) for common rules.

### Command-Specific Rules

| Item | Rule |
|------|------|
| Protected branches | Never delete main, master, develop, release/*, hotfix/* |
| Current branch | Never delete the currently checked-out branch |
| Confirmation | Default run is a read-only dry-run preview; deletion requires the explicit --execute flag |
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
| inside git repo | "Not a git repository" | Navigate to a git repository |
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

## Side Effects and Loop-Safety

This skill is `loop_safe: false`. It deletes merged and stale local/remote branches. Repeated invocation is a destructive cascade with nothing left to do after the first pass, and could race against concurrent branch creation. Run it once per cleanup; do not wrap it in `/loop`.
