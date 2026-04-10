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

> Templates (single + batch format): see `reference/session-resume-templates.md`

## How to Resume

At session start, if `.claude/resume.md` exists:
1. Read and present the saved state to the user
2. If user confirms, proceed from the documented "Next Action"
3. After completing the workflow, delete the resume file

## Rules

- **One resume file per project** -- overwrite if a new workflow starts
- **Delete after completion** -- do not leave stale resume files
- **Include only actionable state** -- no verbose logs or exploration notes
- **Git-ignore the file** -- add `.claude/resume.md` to `.gitignore`
