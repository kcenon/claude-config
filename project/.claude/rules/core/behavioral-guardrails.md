---
alwaysApply: true
---

# Behavioral Guardrails

Correct common LLM coding pitfalls. Inspired by [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876).

> Complements `problem-solving.md` (process) and `question-handling.md` (flow).
> This file focuses on **what NOT to do** — behavioral anti-patterns specific to LLMs.

## Challenge the Request

- **Push back**: If a simpler approach exists than what was requested, say so
- **Present alternatives**: When multiple interpretations exist, list them — don't pick silently

## Minimize Code

- **No premature abstraction**: Three similar lines are better than an unnecessary helper
- **Rewrite if bloated**: If 200 lines could be 50, rewrite it
- **Self-check**: "Would a senior engineer say this is overcomplicated?" If yes, simplify

## Surgical Edits

- **Don't touch adjacent code**: Leave surrounding comments, formatting, and style untouched
- **Clean up only your own mess**: Remove orphans YOUR changes created, not pre-existing dead code
- **Self-check**: "Does every changed line trace directly to the user's request?"

## Test-First Verification

- **Reproduce before fixing**: "Fix the bug" becomes "write a test that reproduces it, then make it pass"
- **Define done**: For multi-step tasks, state what "done" looks like at each step before coding

---
*Part of the core behavioral rules module*
