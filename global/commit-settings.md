# Commit, Issue, and PR Settings

No AI/Claude attribution in commits, issues, or PRs.
Enforced by `settings.json` (`attribution: ""`), the `commit-message-guard` PreToolUse hook (Claude-side feedback loop), and the `commit-msg` git hook installed by `hooks/install-hooks.sh` (terminal-side gate).

Filename references to project root config files (`CLAUDE.md`, `CLAUDE.local.md`) and narrative mentions of the config (e.g. "the CLAUDE config loader") are allowed in commit subjects — only attribution patterns (`Co-Authored-By:` trailers, bot emoji adjacent to Claude/Anthropic, "generated/created/authored {with|by|using} {Claude|Anthropic}" prose) are rejected. See the three-pattern design comment in `hooks/lib/validate-commit-message.sh` for the exact rules.

All GitHub Issues and Pull Requests must be written in English.
