---
alwaysApply: true
---

# GitHub CLI Scripts

> Shell script wrappers for GitHub CLI operations.
> Location: `scripts/gh/`

## Usage Rule

**IMPORTANT**: When calling these scripts programmatically, ALWAYS use `--json` flag.
This ensures clean stdout (JSON only) with errors on stderr.

```bash
# Correct: JSON mode for programmatic use
./scripts/gh/gh_issue_read.sh -r owner/repo -n 42 --json

# Wrong: TTY mode outputs ANSI colors and decorative boxes
./scripts/gh/gh_issue_read.sh -r owner/repo -n 42
```

## Available Scripts

### Issue Operations

| Script | Purpose | JSON Output |
|--------|---------|-------------|
| `gh_issue_create.sh` | Create a GitHub issue | `{"url":"...","number":N}` |
| `gh_issue_read.sh` | Read issue details + comments | `{number,title,state,author,labels,assignees,body,created,updated,comments}` |
| `gh_issue_comment.sh` | Add comment to an issue | `{"url":"..."}` |
| `gh_issues.sh` | List issues across repos | `[{repo,issues:[{number,title,state,labels,created}]}]` |

### PR Operations

| Script | Purpose | JSON Output |
|--------|---------|-------------|
| `gh_pr_create.sh` | Create a pull request | `{"url":"...","number":N}` |
| `gh_pr_read.sh` | Read PR details + reviews | `{number,title,state,author,...,comments,reviews}` |
| `gh_pr_comment.sh` | Add comment to a PR | `{"url":"..."}` |

### Repository Maintenance

| Script | Purpose | JSON Output |
|--------|---------|-------------|
| `cleanup_branches.sh` | Clean local branches + pull main | `{success:[],failed:[],skipped:[],counts:{}}` |

## Common Flags

All scripts support:
- `--json` — Output structured JSON to stdout (errors to stderr)
- `--quiet` — Suppress decorative output, show only essential result
- `-r, --repo owner/repo` — Target repository (auto-detects if omitted)
- `-h, --help` — Show usage help

## Quick Reference

```bash
# Create issue and capture number
./scripts/gh/gh_issue_create.sh -r owner/repo -t "Title" -b "Body" -l "bug" --json
# → {"url":"https://github.com/owner/repo/issues/42","number":42}

# Read issue as structured data
./scripts/gh/gh_issue_read.sh -r owner/repo -n 42 --json
# → {number,title,state,...,comments:[{author,created,body}]}

# Read PR with reviews
./scripts/gh/gh_pr_read.sh -r owner/repo -n 10 --json
# → {number,title,...,reviews:[{author,state,body,submitted}]}

# List all open issues for a user
./scripts/gh/gh_issues.sh -u username --json
# → [{repo:"...",issues:[...]}]

# Add comment and get URL
./scripts/gh/gh_issue_comment.sh -r owner/repo -n 42 -b "Comment text" --json
# → {"url":"https://github.com/owner/repo/issues/42#issuecomment-..."}

# Clean branches across repos
./scripts/gh/cleanup_branches.sh ~/Sources --json
# → {"success":["repo1"],"failed":[],"skipped":[],"counts":{...}}
```

## Error Handling

Errors always go to stderr regardless of mode:
```bash
# Errors on stderr, JSON on stdout
result=$(./scripts/gh/gh_issue_read.sh -r owner/repo -n 999 --json 2>/dev/null)
# $result is empty if the issue doesn't exist
```
