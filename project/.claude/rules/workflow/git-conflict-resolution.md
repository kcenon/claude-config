---
alwaysApply: false
---

# Git Conflict Resolution

Strategies for handling merge conflicts, stash management, and branch integration.

## Conflict Resolution Strategy

Determine action based on file type:

| File Type | Action | Rationale |
|-----------|--------|-----------|
| Source code (`.ts`, `.py`, `.go`, etc.) | Always present to user | Semantic intent cannot be inferred |
| Lockfiles (`package-lock.json`, `go.sum`) | Auto re-generate (`npm install`, `go mod tidy`) | Generated output; re-running is authoritative |
| Config files (`.yml`, `.json`, `.toml`) | Show diff and ask user | Small changes with high impact |
| Test fixtures / snapshots | Prefer incoming (theirs) | Usually updated to match new behavior |
| Documentation (`.md`) | Show diff and ask user | May contain intentional prose changes |
| Build output / generated code | Re-generate from source | Never merge generated artifacts |

## Merge vs Rebase

| Branch Type | Strategy | Command |
|-------------|----------|---------|
| Feature branch (local only) | Rebase onto target | `git rebase main` |
| Feature branch (shared/pushed) | Merge from target | `git merge main` |
| Integration / release branch | Merge only | `git merge feature-branch` |
| Hotfix branch | Rebase if local, merge if pushed | Context-dependent |

**Rule of thumb**: Rebase private history, merge shared history. Never rebase commits
that others have based work on.

## Decision Tree: Abort vs Continue

Abort the merge and consult the user when:

1. **>3 files** have conflicts — high risk of inconsistent resolution
2. **Critical files** conflict — migrations, API schemas, security config
3. **Conflict markers are ambiguous** — both sides made substantial, overlapping changes
4. **Test files and source files** both conflict — indicates divergent feature work

Continue resolving when:

1. **1-2 files** with small, clearly scoped conflicts
2. **Only auto-generated files** conflict (resolve by re-generating)
3. **Whitespace or formatting** differences only

```bash
# Abort safely
git merge --abort    # or: git rebase --abort

# After aborting, report the conflict summary
git diff --name-only --diff-filter=U
```

## Conflict Marker Verification

After resolving all conflicts, verify no markers remain before committing:

```bash
# Check for conflict markers in staged files
git diff --check

# Scan working tree for any remaining markers
grep -rn '<<<<<<<' .
grep -rn '=======' .
grep -rn '>>>>>>>' .
```

**Never commit if any of these commands produce output.** Fix remaining markers first.

## Stash Management

### When to Stash

- Before switching branches with uncommitted work
- Before pulling or rebasing with local changes
- Before running destructive operations

### Naming Convention

Always use descriptive stash messages:

```bash
git stash push -m "context: description"
```

Examples:
- `git stash push -m "feat/auth: wip login validation"`
- `git stash push -m "debug: temporary logging for #142"`

### Cleanup Policy

- Apply and drop stashes promptly — do not accumulate
- Review stash list before creating new stashes: `git stash list`
- Stashes older than the current task are likely stale — verify before applying
- Prefer committing WIP to a branch over long-lived stashes
