# Features and Configuration

Moved from the [README](../../README.md) so the entry page stays short. Korean: [FEATURES.ko.md](FEATURES.ko.md).

## Token Optimization

Rules and skills load on demand — only what's relevant to your current task is loaded into context. This is automatic and requires no configuration.

### Loading reference documents

Detailed reference documents live in `.claude/reference/`, outside the auto-loaded `.claude/rules/` tree, so they never enter initial context. Load them when needed:

```markdown
# Ask Claude to load a specific reference
@load: reference/agent-teams

# Or reference the file directly
Can you review .claude/reference/workflow/label-definitions.md?
```

For advanced customization, see [docs/TOKEN_OPTIMIZATION.md](../../docs/TOKEN_OPTIMIZATION.md).

## What Happens Automatically

These behaviors activate immediately after installation — no configuration needed.

### When you edit code
- Files are auto-formatted in your language (Python, TypeScript, Go, Rust, C++, Kotlin)
- Supported formatters: `black`, `prettier`, `gofmt`, `rustfmt`, `clang-format`, `ktlint`

### When you commit
- Markdown cross-reference anchors are validated — broken links block the commit
- Commit message format is checked (Conventional Commits)
- AI/Claude attribution is stripped automatically
- Commit / PR / issue content is validated against the selected `CLAUDE_CONTENT_LANGUAGE` policy (see [Content Language Policy](#content-language-policy))

### When Claude accesses files
- `.env`, `.pem`, `.key`, and `secrets/` directories are blocked
- Dangerous commands (`rm -rf /`, `chmod 777`, pipe execution) are intercepted
- GitHub API connectivity is validated before API calls

### When a session runs
- Session start/end times are logged to `~/.claude/session.log`
- Known problematic Claude Code versions trigger a warning
- Old temporary files are cleaned up on session end
- Context is snapshot before auto-compaction

### When you create PRs
- PRs targeting `main` from non-`develop` branches are blocked (PreToolUse hook)
- Server-side: GitHub Actions auto-closes violating PRs with an explanatory comment
- Release PRs (`develop` → `main`) are allowed through the `/release` skill

### When using Agent Teams
- Concurrent team count is limited (configurable via `MAX_TEAMS`)
- Teammate idle events and task completions are logged
- Worktree creation and cleanup is managed automatically

> For full hook configuration details and customization, see [HOOKS.md](../../HOOKS.md).

### Content Language Policy

Both installers (`install.sh` and `install.ps1`) prompt for a three-option Language Profile Preset after the installation-type selection. The artifact half maps to these fixed languages:

| UI choice | `CLAUDE_CONTENT_LANGUAGE` value | Validator accepts | Rule-document phrase |
|-----------|----------------------------------|-------------------|----------------------|
| English (default) | `english` | ASCII printable + whitespace, plus allowlisted English typographic punctuation | `English` |
| Korean | `exclusive_bilingual` | Per-artifact: English-only OR Korean-only with limited ASCII containers, no inline mixing | `English or Korean (document-exclusive)` |

The validator additionally accepts two legacy values that are **not surfaced in the UI** — set them via direct `settings.json` edit if needed:

| Legacy value | When to use | Validator accepts |
|--------------|-------------|-------------------|
| `korean_plus_english` | Pre-issue-#447 installs that rely on inline mixing | ASCII + Hangul Syllables / Jamo / Compat Jamo |
| `any` | OSS repositories accepting any language | Skip language validation entirely |

The installer substitutes the chosen phrase into three rule-document templates (`global/commit-settings.md.tmpl`, `project/.claude/rules/core/communication.md.tmpl`, `project/.claude/rules/workflow/git-commit-format.md.tmpl`) so the documented rule matches the validator behavior.

On reinstall, the prompt defaults are seeded from the existing `settings.json` so the prior `.language` and `CLAUDE_CONTENT_LANGUAGE` choices are preserved. Explicit `AGENT_LANGUAGE` and `CONTENT_LANGUAGE` environment overrides still win.

**Scope boundary**: AI/Claude attribution enforcement is **not** governed by this env var — `attribution-guard` and the attribution checks in `commit-message-guard` remain active for every policy.

**Enterprise conflict detection**: When the deployed enterprise `CLAUDE.md` requires English and the operator selects a more permissive policy, the installer prints a warning and asks for confirmation before proceeding.

For the full design rationale, phrase tables, and drift-test invariants, see [`docs/content-language-policy.md`](../../docs/content-language-policy.md).

## Rules

Rules are modular configuration files in `.claude/rules/` that are conditionally loaded based on file paths.

### Available Rules

| Rule | Auto-loaded for | Description |
|------|-----------------|-------------|
| `coding.md` | `**/*.ts`, `**/*.py`, `**/*.go`, etc. | General coding standards |
| `testing.md` | `**/*.test.ts`, `**/test_*.py`, etc. | Testing conventions |
| `security.md` | All code files | Security best practices |
| `documentation.md` | `**/docs/**`, `**/README*`, `**/CHANGELOG*` | Documentation standards |
| `api/rest-api.md` | `**/api/**`, `**/routes/**` | REST API design patterns |

### How Rules Work

Rules use YAML frontmatter with `paths` to define when they should be loaded:

```yaml
---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# Rule content here
```

When you work on files matching these patterns, the rule is automatically loaded.

## Skills — What You Can Do

Skills come in two invocation modes:

1. **Slash-catalog skills** (`/code-quality`, `/security-audit`, `/performance-review`, `/pr-review`, `/git-status` and the `plugin/` skills below) live as one-level folders in `~/.claude/skills/` and appear in Claude Code's `/`-autocomplete. Type the command and the harness dispatches it.
2. **Keyword-aliased skills** (`/issue-work`, `/pr-work`, `/release`, `/issue-create`, `/branch-cleanup`, `/harness`, `/doc-index`, `/doc-review`, `/implement-all-levels`) are intentionally hidden under `~/.claude/skills/_internal/` with `disable-model-invocation: true`. They are **not** in Claude Code's `/`-autocomplete. The model resolves them via the **Skill Aliases** table in `global/CLAUDE.md` when you start your message with the keyword (the leading `/` is optional). Both `issue-work` and `/issue-work` work; tab-completion will not suggest them.

The tables below mark each command's mode.

### Workflow Automation

All commands in this group are **keyword-aliased** (no slash-autocomplete; resolved by the alias table).

| Command | What it does |
|---------|-------------|
| `/issue-work` | Pick a GitHub issue, create branch, implement, test, create PR |
| `/pr-work` | Diagnose failed CI checks, fix, retry, escalate if needed |
| `/release` | Generate changelog from commits, create tagged release |
| `/issue-create` | Create well-structured GitHub issues using 5W1H framework |
| `/branch-cleanup` | Remove merged and stale branches from local and remote |

### Code Analysis

| Command | What it does |
|---------|-------------|
| `/code-quality` | Analyze complexity, code smells, SOLID violations, maintainability |
| `/security-audit` | OWASP Top 10, input validation, auth, dependency vulnerabilities |
| `/performance-review` | Profiling, caching, memory leaks, concurrency patterns |
| `/pr-review` | PR analysis covering quality, security, performance, tests |

### Design and Documentation

`/git-status` is a slash-catalog skill; the rest in this table are keyword-aliased.

| Command | Mode | What it does |
|---------|------|-------------|
| `/harness` | keyword | Design agent teams and generate skills for any domain |
| `/doc-index` | keyword | Generate documentation index files (manifest, bundles, graph, router) |
| `/doc-review` | keyword | Review markdown documents for accuracy, anchors, cross-references |
| `/git-status` | slash | Repository status with actionable insights |
| `/implement-all-levels` | keyword | Enforce complete implementation of all tiers for tiered features |

## Agents

Specialized agents in `.claude/agents/` provide focused assistance for specific tasks.

### Available Agents

| Agent | Description | Model |
|-------|-------------|-------|
| `code-reviewer` | Code review covering quality, security, performance, and maintainability | sonnet |
| `documentation-writer` | Technical documentation | sonnet |
| `refactor-assistant` | Safe code refactoring | sonnet |
| `codebase-analyzer` | Codebase architecture and pattern analysis | sonnet |
| `qa-reviewer` | Integration coherence verification | sonnet |
| `structure-explorer` | Project directory structure mapping | haiku |
| `dependency-auditor` | Dependency CVE and license audit | sonnet |
| `test-strategist` | Test coverage and strategy analysis | sonnet |

### Agent Configuration

Agents use YAML frontmatter to define behavior:

```yaml
---
name: agent-name
description: What the agent does
model: sonnet
tools: Read, Edit
---
```

## Agent Teams

Agent Teams enable multiple Claude instances to work in parallel, coordinating via shared task lists and direct messaging.

> **Status**: Experimental. Already enabled in this configuration.

### Quick Start

Launch a team in natural language:

```
Create a team to implement the notification system:
- Teammate "backend": API endpoints
- Teammate "frontend": UI components
- Teammate "tests": Integration tests
```

Key bindings and display modes are defined by Claude Code, not by this repository; see the official [agent teams documentation](https://code.claude.com/docs/en/agent-teams).

Keep teams to 2-3 teammates for optimal coordination. Assign distinct file sets to avoid conflicts.

For architecture patterns, display modes, hooks, and advanced configuration, see `.claude/reference/workflow/agent-teams.md`.

## MCP Configuration

The `.mcp.json` template provides common MCP server configurations.

### Available Servers

| Server | Description |
|--------|-------------|
| `filesystem` | File system access |
| `github` | GitHub integration |
| `postgres` | PostgreSQL database access |
| `slack` | Slack messaging |
| `memory` | Persistent memory storage |

### Setup

1. Copy `.mcp.json` to your project root
2. Configure environment variables for tokens
3. Remove unused servers

## Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `install.sh` / `.ps1` | Install settings to a new system | `./scripts/install.sh` |
| `backup.sh` / `.ps1` | Save current settings to backup | `./scripts/backup.sh` |
| `sync.sh` / `.ps1` | Bidirectional sync between system and backup | `./scripts/sync.sh` |
| `verify.sh` / `.ps1` | Check backup integrity and completeness | `./scripts/verify.sh` |
| `validate_skills.sh` / `.ps1` | Validate SKILL.md format compliance | `./scripts/validate_skills.sh` |

After installation, `~/.claude/git-identity.md` is auto-filled from `git config --global user.name` and `git config --global user.email` when both values exist. Edit it only if the values are missing or wrong.
On reinstall, the installer keeps the existing language policy defaults from `~/.claude/settings.json` unless `AGENT_LANGUAGE` or `CONTENT_LANGUAGE` is explicitly set.
Reinstalls also prune removed managed files when their local hash still matches the install manifest; locally edited removed files are preserved and reported. See [docs/install.md](../../docs/install.md) for the manifest and prune rules.
Existing files are automatically backed up with `.backup_YYYYMMDD_HHMMSS` format.

## Git Hooks

Install git hooks to enforce commit and push policies:

```bash
./hooks/install-hooks.sh
```

The installer deploys `pre-commit`, `commit-msg`, and `pre-push` into
`.git/hooks/`.

### Pre-commit Hook

- Detects changes to SKILL.md files
- Runs `validate_skills.sh` automatically
- Blocks commits with invalid SKILL.md files

### Commit-msg Hook

- Validates Conventional Commits format
- Blocks attribution trailers/prose and emojis
- Uses the shared `hooks/lib/validate-commit-message.sh` validator

### Pre-push Hook

- Blocks direct pushes to protected branches (`main`, `develop`)
- Requires pull request workflow for protected branches
- Installed as `.git/hooks/pre-push`; `pre-push.ps1` is the PowerShell parity implementation
