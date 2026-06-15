---
alwaysApply: true
---

# Session Resume State

Save workflow progress so interrupted sessions can be resumed seamlessly.

## When to Write

Write `.claude/resume.md` in the project directory when:
- A multi-step workflow (issue-work, pr-work) is in progress
- The user signals they need to leave or switch context
- A long-running CI check is pending and the session may end
- A batch workflow is running under `--auto-restart` and has reached a `CONFIRM_INTERVAL` boundary — the skill writes `resume.md` automatically and exits, so the next `claude` session resumes the batch from the next item (see `global/skills/_internal/issue-work/reference/batch-mode.md` B-4.1)

> Templates (single + batch format): see `.claude/reference/workflow/session-resume-templates.md`

## How to Resume

At session start, use the **Read tool** on `.claude/resume.md` to check for and
load saved state. A not-found error means there is no resume file — proceed
normally. Do **not** wrap the check in an `if`/`Test-Path` compound shell command:
it erodes the matchable command prefix and triggers a permission prompt (see
`core/environment.md`, "Compound commands erode the matchable prefix").

When the file is present:
1. Present the saved state to the user
2. If user confirms, proceed from the documented "Next Action"
3. After completing the workflow, delete the resume file

## Rules

- **One resume file per project** -- overwrite if a new workflow starts
- **Delete after completion** -- do not leave stale resume files
- **Include only actionable state** -- no verbose logs or exploration notes
- **Git-ignore the file** -- add `.claude/resume.md` to `.gitignore`
