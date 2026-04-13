# Claude Configuration Backup & Deployment System

<p align="center">
  <a href="https://github.com/kcenon/claude-config/releases"><img src="https://img.shields.io/badge/version-1.7.0-blue.svg" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-green.svg" alt="License"></a>
  <a href="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml"><img src="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <strong>Easily share and sync CLAUDE.md settings across multiple systems</strong>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#what-you-get">What You Get</a> •
  <a href="#one-line-installation">Installation</a> •
  <a href="#token-optimization">Token Optimization</a> •
  <a href="#structure">Structure</a> •
  <a href="#use-cases">Use Cases</a> •
  <a href="#faq">FAQ</a> •
  <a href="README.ko.md">Korean</a>
</p>

---

## Quick Start

Get up and running in 3 minutes:

```bash
# 1. One-line installation
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash

# 2. Personalize Git identity (Required!)
vi ~/.claude/git-identity.md

# 3. Restart Claude Code - Done!
```

**Common Tasks:**

| Task | macOS/Linux | Windows (PowerShell) |
|------|-------------|----------------------|
| Install settings | `./scripts/install.sh` | `.\scripts\install.ps1` |
| Backup settings | `./scripts/backup.sh` | `.\scripts\backup.ps1` |
| Sync settings | `./scripts/sync.sh` | `.\scripts\sync.ps1` |
| Verify backup | `./scripts/verify.sh` | `.\scripts\verify.ps1` |

For detailed scenarios, see [Use Cases](#use-cases).

---

## What You Get

Install claude-config and Claude Code immediately gains these capabilities:

**Security** — `.env`, `.pem`, and credentials are automatically blocked from being read or written. Dangerous commands like `rm -rf /` are intercepted before execution.

**Auto-formatting** — Code is formatted on every save: Python (black), TypeScript (prettier), Go (gofmt), Rust (rustfmt), C++ (clang-format), Kotlin (ktlint).

**Workflow automation** — `/issue-work` takes a GitHub issue from open to merged PR in one command. `/release` generates changelogs and creates releases. `/pr-work` diagnoses and fixes CI failures.

**Commit quality** — Broken markdown links, AI attribution, and non-conventional commit messages are caught before they reach your repository.

**Code quality on demand** — `/security-audit`, `/performance-review`, `/code-quality`, and `/pr-review` provide specialized analysis when you need it.

**Agent team design** — `/harness` designs multi-agent architectures tailored to your project, with 6 architecture patterns and orchestrator templates.

**Cross-platform** — Everything works on macOS, Linux, and Windows (PowerShell).

---

## One-Line Installation

### Public Repository

```bash
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

### Private Repository

```bash
# Using GitHub Personal Access Token
curl -sSL -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

### Git Clone Method

```bash
# 1. Clone repository
git clone https://github.com/kcenon/claude-config.git ~/claude_config_backup

# 2. Run install script
cd ~/claude_config_backup
./scripts/install.sh

# 3. Personalize Git identity (Required!)
vi ~/.claude/git-identity.md
```

### Windows (PowerShell)

```powershell
# 1. Clone repository
git clone https://github.com/kcenon/claude-config.git ~\claude_config_backup

# 2. Run install script (PowerShell 7+ recommended)
cd ~\claude_config_backup
.\scripts\install.ps1

# 3. Personalize Git identity (Required!)
notepad $HOME\.claude\git-identity.md
```

> **Note**: Requires PowerShell 7+ (`pwsh`). Install via `winget install Microsoft.PowerShell`.
> If you get an execution policy error, run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

### Plugin Installation (Beta)

Install as a Claude Code Plugin for easy distribution and updates:

```bash
# Add marketplace
/plugin marketplace add kcenon/claude-config

# Install plugin
/plugin install claude-config@kcenon/claude-config
```

Or test locally:

```bash
# Load plugin directly (for development/testing)
claude --plugin-dir ./plugin
```

See [plugin/README.md](plugin/README.md) for more details.

### Lightweight Plugin (Behavioral Guardrails Only)

Want just the core behavioral corrections without the full suite?

```bash
# Install lite plugin
claude plugins add kcenon/claude-config-lite

# Or test locally
claude --plugin-dir ./plugin-lite
```

| Method | What You Get | Size |
|--------|-------------|------|
| Full plugin | Complete configuration with all skills, agents, and hooks | ~384KB |
| **Lite plugin** | Core behavioral guardrails for LLM coding mistakes | ~5KB |
| Bootstrap script | Full system configuration deployed to ~/.claude/ | Full repo |

See [plugin-lite/README.md](plugin-lite/README.md) for more details.

---

## Token Optimization

Rules and skills load on demand — only what's relevant to your current task is loaded into context. This is automatic and requires no configuration.

### Loading reference documents

Some detailed reference documents are excluded from initial context for efficiency. Load them when needed:

```markdown
# Ask Claude to load a specific reference
@load: reference/agent-teams

# Or reference the file directly
Can you review rules/workflow/reference/label-definitions.md?
```

For advanced customization, see [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md).

---

## Structure

<details>
<summary>Click to expand directory structure</summary>

```
claude_config_backup/
├── enterprise/                  # Enterprise settings (system-wide)
│   ├── CLAUDE.md               # Organization-wide policies
│   └── rules/                  # Enterprise rules
│       ├── security.md         # Security rules template
│       └── compliance.md       # Compliance rules template
│
├── global/                      # Global settings backup (~/.claude/)
│   ├── CLAUDE.md               # Main configuration file
│   ├── settings.json           # Hook settings (macOS/Linux)
│   ├── settings.windows.json   # Hook settings (Windows PowerShell)
│   ├── commit-settings.md      # Commit/PR attribution policy
│   ├── VERSION_HISTORY.md      # Global config version history
│   ├── tmux.conf               # tmux auto-logging configuration
│   ├── ccstatusline/           # Status line configuration
│   │   └── settings.json      # Status line display settings
│   ├── commands/               # Global command policies
│   │   └── _policy.md         # Shared policies for all commands
│   ├── hooks/                  # Hook scripts (macOS + Windows)
│   │   ├── sensitive-file-guard.sh/.ps1
│   │   ├── dangerous-command-guard.sh/.ps1
│   │   ├── github-api-preflight.sh/.ps1
│   │   ├── markdown-anchor-validator.sh/.ps1
│   │   ├── prompt-validator.sh/.ps1
│   │   ├── session-logger.sh/.ps1
│   │   ├── tool-failure-logger.sh/.ps1
│   │   ├── subagent-logger.sh/.ps1
│   │   ├── task-completed-logger.sh/.ps1
│   │   ├── config-change-logger.sh/.ps1
│   │   ├── pre-compact-snapshot.sh/.ps1
│   │   ├── worktree-create.sh/.ps1
│   │   ├── worktree-remove.sh/.ps1
│   │   ├── team-limit-guard.sh/.ps1
│   │   ├── version-check.sh/.ps1
│   │   ├── cleanup.sh/.ps1
│   │   └── lib/               # Shared libraries
│   │       ├── rotate.sh/.ps1
│   │       └── CommonHelpers.psm1  # PowerShell shared module
│   ├── scripts/                # Utility scripts
│   │   ├── statusline-command.sh/.ps1
│   │   ├── team-report.sh/.ps1
│   │   └── weekly-usage.sh/.ps1
│   └── skills/                 # Global skills (user-invocable)
│       ├── branch-cleanup/     # Clean merged/stale branches
│       ├── doc-index/          # Generate documentation index files
│       ├── doc-review/         # Markdown document review
│       ├── implement-all-levels/ # Enforce complete implementation
│       ├── issue-create/       # Create GitHub issues (5W1H)
│       ├── issue-work/         # GitHub issue workflow automation
│       ├── pr-work/            # Fix failed CI/CD for PRs
│       ├── release/            # Automated release with changelog
│       └── harness/            # Agent team & skill architecture design
│
├── project/                     # Project settings backup
│   ├── CLAUDE.md               # Project main configuration
│   ├── CLAUDE.local.md.template # Local settings template (not committed)
│   ├── VERSION_HISTORY.md      # Project config version history
│   ├── .mcp.json               # MCP server configuration template
│   ├── .mcp.json.example       # MCP configuration example
│   ├── claude-guidelines/      # Standalone guidelines (no .claude dependency)
│   └── .claude/
│       ├── settings.json       # Hook settings (auto-formatting)
│       ├── settings.local.json.template  # Local settings template
│       ├── rules/              # Consolidated guideline modules (auto-loaded)
│       │   ├── coding/         # Coding standards
│       │   │   ├── standards.md
│       │   │   ├── implementation-standards.md
│       │   │   ├── error-handling.md
│       │   │   ├── safety.md
│       │   │   ├── performance.md
│       │   │   ├── cpp-specifics.md
│       │   │   └── reference/anti-patterns.md
│       │   ├── api/            # API & Architecture
│       │   │   ├── api-design.md
│       │   │   ├── architecture.md
│       │   │   ├── observability.md
│       │   │   └── rest-api.md
│       │   ├── workflow/       # Workflow & GitHub guidelines
│       │   │   ├── git-commit-format.md
│       │   │   ├── github-issue-5w1h.md
│       │   │   ├── github-pr-5w1h.md
│       │   │   ├── build-verification.md
│       │   │   ├── ci-resilience.md
│       │   │   ├── performance-analysis.md
│       │   │   ├── session-resume.md
│       │   │   └── reference/  # Label definitions, automation, agent teams
│       │   ├── core/           # Core settings
│       │   │   ├── environment.md
│       │   │   ├── communication.md
│       │   │   └── principles.md
│       │   ├── project-management/
│       │   │   ├── build.md
│       │   │   ├── testing.md
│       │   │   └── documentation.md
│       │   ├── operations/
│       │   │   └── ops.md
│       │   ├── tools/
│       │   │   └── gh-cli-scripts.md
│       │   └── security.md     # Security guidelines
│       ├── commands/           # Custom slash commands
│       │   ├── _policy.md
│       │   ├── pr-review.md
│       │   ├── code-quality.md
│       │   └── git-status.md
│       ├── agents/             # Specialized agent configurations
│       │   ├── code-reviewer.md
│       │   ├── codebase-analyzer.md
│       │   ├── documentation-writer.md
│       │   ├── qa-reviewer.md
│       │   ├── refactor-assistant.md
│       │   └── structure-explorer.md
│       └── skills/             # Claude Code Skills
│           ├── coding-guidelines/
│           ├── security-audit/
│           ├── performance-review/
│           ├── api-design/
│           ├── project-workflow/
│           ├── documentation/
│           ├── ci-debugging/
│           ├── code-quality/   # User-invocable
│           ├── git-status/     # User-invocable
│           └── pr-review/      # User-invocable
│
├── scripts/                     # Automation scripts (all .sh have .ps1 counterparts)
│   ├── install.sh/.ps1         # Install to new system
│   ├── backup.sh/.ps1          # Backup current settings
│   ├── sync.sh/.ps1            # Sync settings
│   ├── verify.sh/.ps1          # Verify backup integrity
│   ├── validate_skills.sh/.ps1 # Validate SKILL.md files
│   └── gh/                     # GitHub CLI helper scripts (.sh/.ps1)
│       ├── cleanup_branches.sh/.ps1
│       ├── gh_issue_create.sh/.ps1
│       ├── gh_issue_comment.sh/.ps1
│       ├── gh_issue_read.sh/.ps1
│       ├── gh_issues.sh/.ps1
│       ├── gh_pr_create.sh/.ps1
│       ├── gh_pr_comment.sh/.ps1
│       └── gh_pr_read.sh/.ps1
│
├── hooks/                       # Git hooks
│   ├── pre-commit              # Pre-commit skill validation
│   ├── pre-push                # Pre-push protected branch guard
│   ├── pre-push.ps1            # Pre-push (PowerShell variant)
│   ├── commit-msg              # Commit message format validation
│   ├── install-hooks.sh/.ps1   # Hook installation script
│   └── lib/
│       └── validate-commit-message.sh  # Shared validation library
│
├── .github/
│   └── workflows/
│       ├── validate-skills.yml # CI skill validation (main-targeting PRs only)
│       └── validate-hooks.yml  # CI hook validation (main-targeting PRs only)
│
├── docs/                        # Design docs and guides
│   ├── branching-strategy.md   # Branch model, CI policy, release workflow
│   ├── TOKEN_OPTIMIZATION.md
│   ├── SKILL_TOKEN_REPORT.md
│   ├── CUSTOM_EXTENSIONS.md
│   ├── ad-sdlc-integration.md
│   └── design/                 # Architecture design docs
│       ├── optimization-discoveries.md
│       ├── optimization-phases.md
│       └── command-optimization.md
│
├── plugin/                      # Claude Code Plugin (Beta)
│   ├── .claude-plugin/
│   │   └── plugin.json         # Plugin manifest
│   ├── agents/                 # Bundled agent definitions
│   ├── skills/                 # Standalone skills (no symlinks)
│   └── hooks/                  # Plugin hooks
│
├── plugin-lite/                 # Lightweight Plugin (Guardrails Only)
│   ├── .claude-plugin/
│   │   └── plugin.json         # Plugin manifest
│   └── skills/
│       └── behavioral-guardrails/
│           └── SKILL.md        # Single behavioral guardrails skill
│
├── bootstrap.sh/.ps1            # One-line install script
├── README.md                    # Detailed guide (English)
├── README.ko.md                 # Detailed guide (Korean)
├── QUICKSTART.md               # Quick start guide
└── HOOKS.md                    # Hook configuration guide
```

</details>

---

## What Happens Automatically

These behaviors activate immediately after installation — no configuration needed.

### When you edit code
- Files are auto-formatted in your language (Python, TypeScript, Go, Rust, C++, Kotlin)
- Supported formatters: `black`, `prettier`, `gofmt`, `rustfmt`, `clang-format`, `ktlint`

### When you commit
- Markdown cross-reference anchors are validated — broken links block the commit
- Commit message format is checked (Conventional Commits)
- AI/Claude attribution is stripped automatically

### When Claude accesses files
- `.env`, `.pem`, `.key`, and `secrets/` directories are blocked
- Dangerous commands (`rm -rf /`, `chmod 777`, pipe execution) are intercepted
- GitHub API connectivity is validated before API calls

### When a session runs
- Session start/end times are logged to `~/.claude/session.log`
- Known problematic Claude Code versions trigger a warning
- Old temporary files are cleaned up on session end
- Context is snapshot before auto-compaction

### When using Agent Teams
- Concurrent team count is limited (configurable via `MAX_TEAMS`)
- Teammate idle events and task completions are logged
- Worktree creation and cleanup is managed automatically

> For full hook configuration details and customization, see [HOOKS.md](HOOKS.md).

---

## Enterprise Settings

Enterprise settings provide organization-wide policies that apply to all developers in your organization. These have the **highest priority** in Claude Code's memory hierarchy.

### Memory Hierarchy

| Level | Location | Scope | Priority |
|-------|----------|-------|----------|
| **Enterprise Policy** | System-wide | Organization | **Highest** |
| Project Memory | `./CLAUDE.md` | Team | High |
| Project Rules | `./.claude/rules/*.md` | Team | High |
| User Memory | `~/.claude/CLAUDE.md` | Personal | Medium |
| Project Local | `./CLAUDE.local.md` | Personal | Low |

### Enterprise Paths by OS

| OS | Path |
|----|------|
| **macOS** | `/Library/Application Support/ClaudeCode/CLAUDE.md` |
| **Linux** | `/etc/claude-code/CLAUDE.md` |
| **Windows** | `C:\Program Files\ClaudeCode\CLAUDE.md` |

### Installing Enterprise Settings

```bash
./scripts/install.sh

# Select option:
#   4) Enterprise settings only (admin required)
#   5) All (Enterprise + Global + Project)
```

**Note**: Enterprise installation requires administrator privileges (`sudo` on macOS/Linux).

### Enterprise Template Contents

The default enterprise template includes:
- **Security Requirements**: Commit signing, secret protection, access control
- **Compliance**: Data handling, audit requirements, regulatory compliance
- **Approved Tools**: Package registries, container images, dependencies
- **Code Standards**: Quality gates, review requirements, branch protection

Customize `enterprise/CLAUDE.md` according to your organization's policies before deployment.

---

## Personal Settings (CLAUDE.local.md)

For machine-specific settings that shouldn't be committed to version control, create `CLAUDE.local.md` in your project root.

```bash
# Copy the template
cp project/CLAUDE.local.md.template CLAUDE.local.md
```

Use it for local server URLs, machine-specific paths, and personal workflow preferences. Do **not** put credentials or API keys here — use environment variables instead.

This file is gitignored and has the lowest priority in Claude Code's memory hierarchy.

---

## Rules

Rules are modular configuration files in `.claude/rules/` that are conditionally loaded based on file paths.

### Available Rules

| Rule | Auto-loaded for | Description |
|------|-----------------|-------------|
| `coding.md` | `**/*.ts`, `**/*.py`, `**/*.go`, etc. | General coding standards |
| `testing.md` | `**/*.test.ts`, `**/test_*.py`, etc. | Testing conventions |
| `security.md` | All code files | Security best practices |
| `documentation.md` | `**/*.md`, `**/docs/**` | Documentation standards |
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

---

## Skills — What You Can Do

Invoke any skill by typing its command in Claude Code.

### Workflow Automation

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
| `/pr-review` | Comprehensive PR analysis covering quality, security, performance, tests |

### Design and Documentation

| Command | What it does |
|---------|-------------|
| `/harness` | Design agent teams and generate skills for any domain |
| `/doc-index` | Generate documentation index files (manifest, bundles, graph, router) |
| `/doc-review` | Review markdown documents for accuracy, anchors, cross-references |
| `/git-status` | Repository status with actionable insights |
| `/implement-all-levels` | Enforce complete implementation of all tiers for tiered features |

---

## Agents

Specialized agents in `.claude/agents/` provide focused assistance for specific tasks.

### Available Agents

| Agent | Description | Model |
|-------|-------------|-------|
| `code-reviewer` | Comprehensive code review | sonnet |
| `documentation-writer` | Technical documentation | sonnet |
| `refactor-assistant` | Safe code refactoring | sonnet |
| `codebase-analyzer` | Codebase architecture and pattern analysis | sonnet |
| `qa-reviewer` | Integration coherence verification | sonnet |
| `structure-explorer` | Project directory structure mapping | haiku |

### Agent Configuration

Agents use YAML frontmatter to define behavior:

```yaml
---
name: agent-name
description: What the agent does
model: sonnet
tools: Read, Edit
temperature: 0.3
---
```

---

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

### Key Controls

| Action | How |
|--------|-----|
| Cycle teammates | `Shift+Down` |
| Shared task list | `Ctrl+T` |
| Send message | `Enter` (to focused teammate) |
| Return to lead | `Escape` |

Keep teams to 2-3 teammates for optimal coordination. Assign distinct file sets to avoid conflicts.

For architecture patterns, display modes, hooks, and advanced configuration, see `rules/workflow/reference/agent-teams.md`.

---

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

---

## Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `install.sh` / `.ps1` | Install settings to a new system | `./scripts/install.sh` |
| `backup.sh` / `.ps1` | Save current settings to backup | `./scripts/backup.sh` |
| `sync.sh` / `.ps1` | Bidirectional sync between system and backup | `./scripts/sync.sh` |
| `verify.sh` / `.ps1` | Check backup integrity and completeness | `./scripts/verify.sh` |
| `validate_skills.sh` / `.ps1` | Validate SKILL.md format compliance | `./scripts/validate_skills.sh` |

After installation, you **must** edit `~/.claude/git-identity.md` with your personal info.
Existing files are automatically backed up with `.backup_YYYYMMDD_HHMMSS` format.

---

## Git Hooks

Install git hooks to enforce commit and push policies:

```bash
./hooks/install-hooks.sh
```

### Pre-commit Hook

- Detects changes to SKILL.md files
- Runs `validate_skills.sh` automatically
- Blocks commits with invalid SKILL.md files

### Pre-push Hook

- Blocks direct pushes to protected branches (`main`, `develop`)
- Requires pull request workflow for protected branches
- Cross-platform: `pre-push` (bash) and `pre-push.ps1` (PowerShell)

---

## Use Cases

### Use Case A: Sync Work + Home Computers

```bash
# At work (initial setup)
cd ~/claude_config_backup
./scripts/backup.sh
git add . && git commit -m "Update settings"
git push

# At home
cd ~/claude_config_backup
git pull
./scripts/sync.sh
# Select: 1 (Backup → System)
```

---

### Use Case B: Share Team Project Settings

```bash
# Project leader
cd project_root
git clone https://github.com/kcenon/claude-config.git .claude-config
cd .claude-config
./scripts/install.sh
# Type: 2 (Project only)

# Team member
git clone https://github.com/your-org/project.git
cd project/.claude-config
./scripts/install.sh
# Type: 2 (Project only)
```

---

### Use Case C: New Development Machine Setup

```bash
# One-line installation
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash

# Or manual installation
git clone https://github.com/kcenon/claude-config.git ~/claude_config_backup
cd ~/claude_config_backup
./scripts/install.sh
# Type: 3 (Both)

# Modify Git identity
vi ~/.claude/git-identity.md
```

---

<details>
<summary><strong>Advanced Usage</strong> (GitHub Actions, Environment Variables)</summary>

## Advanced Usage

### GitHub Actions Auto-Sync

Create `.github/workflows/sync.yml` file:

```yaml
name: Sync Claude Config

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 0 * * 0'  # Every Sunday

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify backup integrity
        run: ./scripts/verify.sh
```

### Backup Specific Files Only

```bash
# Backup global CLAUDE.md only
cp ~/.claude/CLAUDE.md ~/claude_config_backup/global/

# Backup project settings only
cp -r ~/project/.claude ~/claude_config_backup/project/
```

### Customize with Environment Variables

```bash
# When using bootstrap.sh
GITHUB_USER=your-username \
GITHUB_REPO=your-repo \
INSTALL_DIR=~/my-claude-config \
bash -c "$(curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh)"
```

</details>

---

## FAQ

### Q1: Why do I need to personalize Git identity?

**A:** `git-identity.md` contains personal information (name, email), so each user must modify it with their own information.

```bash
vi ~/.claude/git-identity.md
# Change name and email to your information
```

---

### Q2: How to manage backups across multiple locations?

**A:** Use Git for version control:

```bash
cd ~/claude_config_backup
git add .
git commit -m "Update settings"
git push
```

---

### Q3: I want different settings for each project

**A:** Separate by branches or use separate directories:

```bash
git checkout -b project-a
# Modify project A settings
git commit -m "Settings for project A"

git checkout -b project-b
# Modify project B settings
git commit -m "Settings for project B"
```

---

### Q4: Scripts won't run

**A:** Check execution permissions:

```bash
chmod +x scripts/*.sh bootstrap.sh

# Or run directly
bash scripts/install.sh
```

---

### Q5: I want to use a private repo

**A:** Use Personal Access Token during installation:

```bash
# Create token: GitHub Settings > Developer settings > Personal access tokens

# Installation
curl -sSL -H "Authorization: token YOUR_TOKEN" \
  https://raw.githubusercontent.com/your-user/claude-config/main/bootstrap.sh | bash
```

---

## Additional Resources

- **Configuration Examples**: See `global/` and `project/` directories
- **Branching Strategy**: [docs/branching-strategy.md](docs/branching-strategy.md) - Branch model, CI policy, and release workflow
- **Custom Extensions Guide**: [docs/CUSTOM_EXTENSIONS.md](docs/CUSTOM_EXTENSIONS.md) - Understand which features are official vs custom
- **Token Optimization**: [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md) - Rule optimization (86% reduction)
- **Skill Token Report**: [docs/SKILL_TOKEN_REPORT.md](docs/SKILL_TOKEN_REPORT.md) - Per-skill consumption analysis
- **AD-SDLC Integration**: [docs/ad-sdlc-integration.md](docs/ad-sdlc-integration.md) - AI agent-based SDLC integration
- **Troubleshooting**: Check error messages from each script

---

## Version

**Current**: 1.7.0 (2026-04-06)

<details>
<summary>Changelog</summary>

#### v1.7.0 (2026-04-06)
- **Full Windows PowerShell parity**: All 42 bash scripts now have PowerShell (.ps1) counterparts
  - All utility scripts: `install`, `verify`, `sync`, `backup`, `validate_skills`, `bootstrap`
  - All 16 hook scripts with identical security behavior (fail-closed model preserved)
  - All 8 GitHub CLI helper scripts (`scripts/gh/`)
  - All 3 global scripts (`statusline-command`, `team-report`, `weekly-usage`)
  - All 7 test scripts for hook validation
  - Git hooks installer (`hooks/install-hooks.ps1`)
- **Shared PowerShell module**: Added `CommonHelpers.psm1` with 20 exported functions
  - Message helpers, hook response builders, stdin JSON reader
  - Platform detection, version comparison, log rotation
  - Eliminates `jq` dependency on Windows (uses native `ConvertFrom-Json`)
  - Uses .NET `GZipStream` for log compression (no external `gzip` needed)

#### v1.6.0 (2026-04-03)
- **Harness meta-skill**: Added `/harness` for designing domain-specific agent team architectures
  - 6 architecture patterns: Pipeline, Fan-out/Fan-in, Expert Pool, Producer-Reviewer, Supervisor, Hierarchical
  - Generates `.claude/agents/` and `.claude/skills/` with orchestration
  - Reference docs: agent design patterns, orchestrator templates, skill writing/testing guides, QA agent guide
- **QA reviewer agent**: Added `qa-reviewer` agent for integration coherence verification
- **Version check hook**: Added SessionStart hook to warn about known Claude Code cache bugs
- **Batch processing**: Added batch mode to `/issue-work` and `/pr-work` skills (single-repo, cross-repo)
- **CI validation**: Extended skill validation with description quality and global skills checks
- **Skill descriptions**: Enhanced trigger accuracy across all skills
- **Third-party notices**: Added `THIRD_PARTY_NOTICES.md` for harness content attribution (Apache 2.0)

#### v1.5.0 (2026-03-21)
- **Skills migration**: Migrated all global commands to Skills format for context isolation and model override support
  - `/branch-cleanup`, `/release`, `/issue-create`, `/issue-work`, `/pr-work` are now skills
  - Added new global skills: `/doc-review`, `/implement-all-levels`
  - Added new project skills: `ci-debugging`, `code-quality`, `git-status`, `pr-review`
  - Skills support `argument-hint`, `model`, `allowed-tools`, and adaptive execution frontmatter
- **Agent Teams**: Added experimental multi-agent collaboration framework
  - Shared task lists, direct messaging, and team coordination
  - Teammates modes: `auto`, `in-process`, `tmux`
  - Team hooks: `TeammateIdle`, `TaskCompleted`
- **Windows PowerShell support**: Full cross-platform parity
  - Added `install.ps1` for Windows installation
  - All 16 hook scripts have `.ps1` variants
  - Added `settings.windows.json` for Windows-specific hook paths
- **New hooks** (8 new types):
  - `github-api-preflight`: GitHub API call validation
  - `markdown-anchor-validator`: Markdown anchor validation
  - `prompt-validator`: Commit message validation via LLM
  - `tool-failure-logger`: Tool execution failure tracking
  - `subagent-logger`: Subagent lifecycle tracking
  - `task-completed-logger`: Task completion tracking
  - `config-change-logger`: Configuration change tracking
  - `pre-compact-snapshot`: Context preservation before auto-compaction
  - `worktree-create`/`worktree-remove`: Worktree lifecycle hooks
- **tmux auto-logging**: Added `tmux.conf` for automatic session logging
- **Plugin enhancements**: Bundled agent definitions, updated manifests
- **GitHub helper scripts**: Added `scripts/gh/` with 8 helper scripts for issues and PRs
- **Rule files restructured**: Updated `coding/`, `core/`, `operations/`, `tools/` rules to match current best practices
- **Context optimization**: Reduced always-on context by 77% (485 → 112 lines) via SSOT refactoring

#### v1.4.0 (2026-01-22)
- Adopted Import syntax (`@path/to/file`) for modular references
  - Replaced markdown links with Import syntax for better token efficiency
  - Supports recursive imports up to 5 levels deep
- Updated all CLAUDE.md files (global and project) to use Import syntax
- Updated all SKILL.md files to use Import syntax for reference documents

#### v1.3.0 (2026-01-15)
- Added `/release` command for automated changelog generation
- Added `/branch-cleanup` command for merged and stale branches
- Added `/issue-create` command with 5W1H framework
- Added `/issue-work` and `/pr-work` commands for GitHub workflow automation
- Added common policy files (`_policy.md`) for shared command rules
- Updated all global commands to reference shared policy

#### v1.2.0 (2026-01-15)
- CLAUDE.md optimization for official best practices compliance
- Simplified project/CLAUDE.md (212 → ~85 lines)
- Added emphasis expressions for key rules
- Created common-commands.md
- Optimized conditional-loading.md
- Split github-issue-5w1h.md with Progressive Disclosure

#### v1.1.0 (2025-01-15)
- Added `.claude/rules/` directory with path-based conditional loading
- Added `.claude/commands/` for custom slash commands
- Added `.claude/agents/` for specialized agent configurations
- Added MCP configuration template (`.mcp.json`)
- Added local settings templates (`CLAUDE.local.md.template`, `settings.local.json.template`)
- Extended hooks with `UserPromptSubmit` and `Stop` events
- Added `alwaysThinkingEnabled` setting to all settings.json files
- Enhanced all SKILL.md files with `allowed-tools` and `model` options

#### v1.0.0 (2025-12-03)
- Initial release with global and project configurations
- Claude Code Skills with progressive disclosure pattern
- Hook settings for security and auto-formatting

</details>

---

## Contributing

If you'd like to improve this backup system:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## Related Projects

### AD-SDLC (Agent-Driven Software Development Lifecycle)

An AI agent-based software development automation platform. AD-SDLC agents can reference this project's Skills and Guidelines to improve code quality.

- **Repository**: [kcenon/claude_code_agent](https://github.com/kcenon/claude_code_agent)
- **Integration Guide**: [docs/ad-sdlc-integration.md](docs/ad-sdlc-integration.md)

---

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

This project includes third-party content. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

---

**Happy Coding with Claude!**
