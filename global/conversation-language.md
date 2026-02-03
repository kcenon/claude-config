# Conversation Language Settings

> **Scope**: This file controls Claude's **conversation language only**.
> **For code/documentation languages**: See project-specific `communication.md`

## Official Setting

Language is now configured via official `settings.json`:

```json
{
  "language": "korean"
}
```

This setting is applied in both `global/settings.json` and `project/.claude/settings.json`.

## Core Principle

Claude communicates with users in their preferred language while maintaining technical accuracy.

## Language Configuration

### User Interaction
- **Default response language**: Korean (via `settings.json`)
- **YOU MUST** respond in Korean unless the user explicitly requests English
- **Language switching**: Honor explicit user requests to change language
- **Consistency**: Maintain chosen language throughout session

### Input Processing
- **Internal translation**: Translate non-English questions to English for better comprehension
- **Translation transparency**: Show English translation when it aids understanding
- **Context preservation**: Keep original question's nuance and intent

## Boundaries and Relationships

### What This File Controls ✅
- Claude's spoken/written responses to users
- Error message explanations and clarifications
- General discussion and Q&A language

### What This File Does NOT Control ❌
- Source code comments → See `project/communication.md`
- Documentation files → See `project/communication.md`
- Variable/function naming → See `project/coding-standards/`
- Git commit messages → See `project/git-commit-format.md`

## Special Cases

### Technical Communication
- **Mixed mode**: Use English terms with Korean explanations when clearer
- **Example format**:
  ```
  "Implemented a thread-safe singleton pattern"
  (Uses English technical terms with native language explanation when needed)
  ```

### Error Handling
- Show original error in English
- Provide Korean explanation/solution
- Example:
  ```
  Error: ENOENT: no such file or directory
  → File not found. Please check the path.
  ```

## Priority Rules

1. User's explicit language request > Default setting
2. Project `communication.md` > This file (for code/docs)
3. Technical accuracy > Language preference (when conflict exists)

---
*Part of Claude's global configuration. Version 1.2.0*