# Universal Development Guidelines

Universal conventions for this repository. Works with global settings in `~/.claude/CLAUDE.md`.

Rules use YAML frontmatter (`alwaysApply`, `paths`) for automatic loading.
Reference docs in `rules/*/reference/` are excluded via `.claudeignore` — load with `@load:`.
Defer to language-specific conventions (PEP 8, C++ Core Guidelines, etc.).

## MCP Server Configuration

Use `.mcp.json` at the project root for team-shared MCP server definitions (committed to Git).
See `.mcp.json.example` for transport examples (HTTP, stdio, SSE) and environment variable patterns.
Never hardcode secrets — use `${VAR}` references and store values in `.env` (not committed).
