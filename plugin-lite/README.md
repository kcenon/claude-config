# Claude Config Lite

A lightweight plugin containing only the essential behavioral guardrails for LLM coding.

## What's Included

A single skill (`behavioral-guardrails`) with 4 principles:

| Principle | What It Corrects |
|-----------|-----------------|
| **Challenge the Request** | Silently assuming scope, format, or intent |
| **Minimize Code** | Over-engineering with premature abstractions |
| **Surgical Edits** | Drive-by refactoring and style drift |
| **Test-First Verification** | Vague execution without success criteria |

## Installation

```bash
claude plugins add kcenon/claude-config-lite
```

Or test locally:

```bash
claude --plugin-dir ./plugin-lite
```

## Comparison with Full Plugin

| Component | Full Plugin | Lite Plugin |
|-----------|-------------|-------------|
| Skills | 7 | 1 |
| Hooks | Yes | No |
| .claudeignore | Yes | No |
| Total size | ~360KB | ~5KB |

Want the full suite? See the [main plugin](../plugin/).

## License

BSD-3-Clause - See [LICENSE](../LICENSE) for details.
