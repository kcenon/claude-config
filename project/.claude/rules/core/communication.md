---
alwaysApply: true
---

# Code and Documentation Language

Prose (comments, documentation, PR/issue bodies, commit descriptions) uses **English**.
Code identifiers (variables, functions, classes, files) always use **English** due to language syntax requirements.

## Scope

- Variable/function/class/file names → English (language syntax requirement)
- Comments, error messages, log messages → English
- README, API docs, architecture docs, PR descriptions, issue templates → English
- Commit messages → English (see `git-commit-format.md`)

## Relationship with Conversation Language

Claude responds to users in Korean (via `settings.json` `language: "korean"`).
Prose content remains in English regardless of conversation language.

## Special Cases

- Korean company names in code: romanize (e.g., `class SamsungAPI`)
- Localization files: keep original strings
- Korean project override: create `CLAUDE_KO.md` in project root
