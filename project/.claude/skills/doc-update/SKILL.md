---
name: doc-update
description: "Update documentation files with an execution-first approach: read source, plan briefly, edit immediately, summarize changes, and commit. Use when updating docs, syncing documentation with code changes, or batch-editing markdown files."
argument-hint: "<file-or-directory> [--commit] [--dry-run]"
user-invocable: true
disable-model-invocation: true
context: fork
allowed-tools:
  - Bash
  - Grep
  - Glob
  - Read
  - Edit
  - Write
---

# Document Update Command

Update documentation files with an execution-first workflow.

## Usage

```
/doc-update README.md                    # Update a single file
/doc-update docs/                        # Update all docs in directory
/doc-update docs/api.md --commit         # Update and commit
/doc-update docs/ --dry-run              # Show planned changes without applying
```

## Arguments

- `<file-or-directory>`: Target to update (required)
  - Single file: update that file directly
  - Directory: find and update all `.md` files recursively

- `[--commit]`: Commit changes after applying edits (optional)
  - Without `--commit`: Edit files but do not commit
  - With `--commit`: Edit files, then create a commit with a one-line summary per file

- `[--dry-run]`: Preview mode (optional)
  - Show what would change without modifying any files

## Instructions

Follow this execution-first workflow strictly.

### Anti-Pattern

Do NOT spend more than 2 minutes on analysis before starting edits. If you find yourself reading a third file without having made any edits, stop and start editing immediately.

### Step 1: Read Source (max 1 minute)

Read the target file(s) to understand current content. For directories, scan file names first, then read files as you edit them — not all upfront.

### Step 2: Plan (max 5 bullet points)

Write a brief plan of changes. Maximum 5 bullet points. Do not create detailed outlines, change matrices, or impact analyses.

Example:
```
Plan:
- Update API endpoint table with new /users/search route
- Fix outdated install command (npm → pnpm)
- Remove deprecated config section
- Add missing environment variable docs
- Update version references to 3.2.0
```

### Step 3: Edit Immediately

Start making changes file by file. Use the Edit tool for surgical modifications. Use Write only for new files or complete rewrites.

Rules:
- Edit one file at a time
- After each file, move to the next — do not re-read files you just edited
- Match existing formatting, heading levels, and style conventions
- Do not add unrelated improvements or reformatting

### Step 4: Summarize Changes

After all edits are complete, provide a one-line summary per modified file:

```
Changes:
- docs/api.md: added /users/search endpoint documentation
- docs/install.md: updated package manager from npm to pnpm
- docs/config.md: removed deprecated v1 configuration section
```

### Step 5: Commit (if --commit)

If `--commit` flag is set, create a single commit with type `docs`:

```
docs(scope): brief description of changes
```

Include the file-level summary as the commit body.

## Error Handling

| Condition | Behavior |
|-----------|----------|
| File not found | Report error, skip file, continue with remaining targets |
| Binary file | Skip with warning |
| No changes needed | Report "No updates required" and exit |
| Read-only file | Report error and skip |
| Dry-run mode | Show diff preview for each file, make no modifications |

## Quality Checks

Before finishing, verify:
- [ ] No broken markdown links introduced
- [ ] Heading hierarchy is consistent (no skipped levels)
- [ ] Code blocks have language annotations
- [ ] No trailing whitespace added
