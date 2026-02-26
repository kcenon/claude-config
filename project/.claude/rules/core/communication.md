---
alwaysApply: true
---

# Code and Documentation Language

All code and technical documentation must use **English**.

## Scope

- Variable/function/class names, comments, error messages, log messages → English
- README, API docs, architecture docs, PR descriptions, issue templates → English
- Commit messages → English (see `git-commit-format.md`)

## Relationship with Conversation Language

Claude responds to users in Korean (via `settings.json` `language: "korean"`).
Code and documentation remain in English regardless of conversation language.

## Special Cases

- Korean company names in code: romanize (e.g., `class SamsungAPI`)
- Localization files: keep original strings
- Korean project override: create `CLAUDE_KO.md` in project root
