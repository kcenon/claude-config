---
alwaysApply: false
paths:
  - "scripts/gh/**"
---

# GitHub CLI Scripts

Scripts in `scripts/gh/`. ALWAYS use `--json` flag for programmatic calls.
All scripts support: `--json`, `--quiet`, `-r owner/repo`, `-h`.

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

## Quick Reference

```bash
./scripts/gh/gh_issue_create.sh -r owner/repo -t "Title" -b "Body" -l "bug" --json
./scripts/gh/gh_issue_read.sh -r owner/repo -n 42 --json
./scripts/gh/gh_pr_create.sh -r owner/repo -t "Title" -b "Body" --json
./scripts/gh/gh_pr_read.sh -r owner/repo -n 10 --json
./scripts/gh/gh_issues.sh -u username --json
./scripts/gh/gh_issue_comment.sh -r owner/repo -n 42 -b "Comment" --json
./scripts/gh/cleanup_branches.sh ~/Sources --json
```

## Error Handling

Errors always go to stderr regardless of mode.
