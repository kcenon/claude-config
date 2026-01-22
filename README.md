# Claude Configuration Backup & Deployment System

<p align="center">
  <a href="https://github.com/kcenon/claude-config/releases"><img src="https://img.shields.io/badge/version-1.4.0-blue.svg" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-green.svg" alt="License"></a>
  <a href="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml"><img src="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <strong>Easily share and sync CLAUDE.md settings across multiple systems</strong>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#one-line-installation">Installation</a> •
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

| Task | Command |
|------|---------|
| Backup settings | `./scripts/backup.sh` |
| Sync settings | `./scripts/sync.sh` |
| Verify backup | `./scripts/verify.sh` |

For detailed scenarios, see [Use Cases](#use-cases).

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
│   ├── settings.json           # Hook settings (security, session, UserPromptSubmit, Stop)
│   ├── commit-settings.md      # Commit/PR attribution policy
│   ├── conversation-language.md # Conversation language settings
│   ├── git-identity.md         # Git user information
│   ├── token-management.md     # Token management policy
│   └── commands/               # Global slash commands
│       ├── _policy.md          # Shared policies for all commands
│       ├── branch-cleanup.md   # /branch-cleanup command
│       ├── issue-create.md     # /issue-create command
│       ├── issue-work.md       # /issue-work command
│       ├── pr-work.md          # /pr-work command
│       └── release.md          # /release command
│
├── project/                     # Project settings backup
│   ├── CLAUDE.md               # Project main configuration
│   ├── CLAUDE.local.md.template # Local settings template (not committed)
│   ├── .mcp.json               # MCP server configuration template
│   └── .claude/
│       ├── settings.json       # Hook settings (auto-formatting)
│       ├── settings.local.json.template  # Local settings template
│       ├── rules/              # Consolidated guideline modules (auto-loaded)
│       │   ├── coding/         # Coding standards
│       │   │   ├── general.md
│       │   │   ├── quality.md
│       │   │   ├── error-handling.md
│       │   │   ├── concurrency.md
│       │   │   ├── memory.md
│       │   │   └── performance.md
│       │   ├── api/            # API & Architecture
│       │   │   ├── api-design.md
│       │   │   ├── architecture.md
│       │   │   ├── logging.md
│       │   │   ├── observability.md
│       │   │   └── rest-api.md
│       │   ├── workflow/       # Workflow & GitHub guidelines
│       │   │   ├── git-commit-format.md
│       │   │   ├── github-issue-5w1h.md
│       │   │   ├── github-pr-5w1h.md
│       │   │   └── reference/  # Label definitions, automation patterns
│       │   ├── core/           # Core settings
│       │   │   ├── environment.md
│       │   │   ├── communication.md
│       │   │   ├── problem-solving.md
│       │   │   └── common-commands.md
│       │   ├── project-management/
│       │   │   ├── build.md
│       │   │   ├── testing.md
│       │   │   └── documentation.md
│       │   ├── operations/
│       │   │   ├── monitoring.md
│       │   │   └── cleanup.md
│       │   ├── coding.md       # Coding overview
│       │   ├── testing.md      # Testing overview
│       │   ├── security.md     # Security guidelines
│       │   ├── documentation.md
│       │   └── conditional-loading.md
│       ├── commands/           # Custom slash commands
│       │   ├── pr-review.md
│       │   ├── code-quality.md
│       │   └── git-status.md
│       ├── agents/             # Specialized agent configurations
│       │   ├── code-reviewer.md
│       │   ├── documentation-writer.md
│       │   └── refactor-assistant.md
│       └── skills/             # Claude Code Skills
│           ├── coding-guidelines/
│           │   └── SKILL.md
│           ├── security-audit/
│           │   └── SKILL.md
│           ├── performance-review/
│           │   └── SKILL.md
│           ├── api-design/
│           │   └── SKILL.md
│           ├── project-workflow/
│           │   └── SKILL.md
│           └── documentation/
│               └── SKILL.md
│
├── scripts/                     # Automation scripts
│   ├── install.sh              # Install to new system
│   ├── backup.sh               # Backup current settings
│   ├── sync.sh                 # Sync settings
│   ├── verify.sh               # Verify backup integrity
│   └── validate_skills.sh      # Validate SKILL.md files
│
├── hooks/                       # Git hooks
│   ├── pre-commit              # Pre-commit skill validation
│   └── install-hooks.sh        # Hook installation script
│
├── .github/
│   └── workflows/
│       └── validate-skills.yml # CI skill validation
│
├── plugin/                      # Claude Code Plugin (Beta)
│   ├── .claude-plugin/
│   │   └── plugin.json         # Plugin manifest
│   ├── skills/                 # Standalone skills (no symlinks)
│   └── hooks/                  # Plugin hooks
│
├── bootstrap.sh                 # One-line install script
├── README.md                    # Detailed guide (English)
├── README.ko.md                 # Detailed guide (Korean)
├── QUICKSTART.md               # Quick start guide
└── HOOKS.md                    # Hook configuration guide
```

</details>

---

## Hook Settings

This configuration includes automated Hook settings for enhanced security and productivity.

### Global Hooks (`global/settings.json`)

| Hook | Event | Description |
|------|-------|-------------|
| **Sensitive File Protection** | PreToolUse | Blocks access to `.env`, `.pem`, `.key`, `secrets/` |
| **Dangerous Command Block** | PreToolUse | Blocks `rm -rf /`, `chmod 777`, remote script execution |
| **Session Logging** | SessionStart/End | Logs session start/end times to `~/.claude/session.log` |
| **Temp File Cleanup** | SessionEnd | Removes old `/tmp/claude_*` files |
| **Dangerous Operation Warning** | UserPromptSubmit | Warns when dangerous operations (delete all, drop database) are requested |
| **Stop Logging** | Stop | Logs when Claude Code operations are stopped |

### Project Hooks (`project/.claude/settings.json`)

| Hook | Event | Description |
|------|-------|-------------|
| **Auto Formatting** | PostToolUse | Runs language-specific formatters after file edits |

### Settings Options

| Setting | Description | Default |
|---------|-------------|---------|
| `alwaysThinkingEnabled` | Enable extended thinking for complex tasks | `true` |

**Supported Formatters:**
- Python: `black`, `isort`
- TypeScript/JavaScript: `prettier`
- C++: `clang-format`
- Kotlin: `ktlint`
- Go: `gofmt`
- Rust: `rustfmt`

For detailed configuration, see [HOOKS.md](HOOKS.md).

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

## Commands

Custom slash commands in `.claude/commands/` provide shortcuts for common tasks.

### Available Commands

| Command | Description |
|---------|-------------|
| `/pr-review [NUMBER]` | Comprehensive PR review with security, performance, and quality analysis |
| `/code-quality [PATH]` | Analyze code quality and provide improvement suggestions |
| `/git-status` | Enhanced git status with actionable insights |

### Creating Custom Commands

1. Create a markdown file in `.claude/commands/`
2. Define usage, instructions, and output format
3. Use the command with `/command-name`

---

## Global Commands

Global commands are available across all projects when installed to `~/.claude/commands/`.

### Available Global Commands

| Command | Description | Example |
|---------|-------------|---------|
| `/branch-cleanup` | Clean merged and stale branches | `/branch-cleanup --dry-run` |
| `/release` | Create release with auto-generated changelog | `/release 1.2.0` |
| `/issue-create` | Create GitHub issues with 5W1H framework | `/issue-create myproject --type bug` |
| `/issue-work` | Automate GitHub issue workflow | `/issue-work myproject` |
| `/pr-work` | Analyze and fix failed CI/CD for PRs | `/pr-work myproject 42` |

### Command Details

#### `/branch-cleanup`
```bash
/branch-cleanup [<project-name>] [--dry-run] [--include-remote] [--stale-days <days>]
```
- `--dry-run`: Preview branches without deleting
- `--include-remote`: Also clean remote tracking branches
- `--stale-days`: Days since last commit to consider stale (default: 90)

#### `/release`
```bash
/release <version> [--draft] [--prerelease] [--org <organization>]
```
- Creates GitHub release with changelog from commits since last release
- Supports semantic versioning (e.g., 1.2.0, 2.0.0-beta.1)

#### `/issue-create`
```bash
/issue-create <project-name> [--type <type>] [--priority <priority>]
```
- Types: bug, feature, refactor, docs
- Priorities: critical, high, medium, low
- Uses 5W1H framework for structured issue creation

#### `/issue-work`
```bash
/issue-work <project-name> [--org <organization>]
```
- Lists open issues and guides through workflow
- Auto-detects organization from git remote

#### `/pr-work`
```bash
/pr-work <project-name> <pr-number> [--org <organization>]
```
- Analyzes failed CI/CD workflows
- Provides fix suggestions and implementation

---

## Agents

Specialized agents in `.claude/agents/` provide focused assistance for specific tasks.

### Available Agents

| Agent | Description | Model |
|-------|-------------|-------|
| `code-reviewer` | Comprehensive code review | sonnet |
| `documentation-writer` | Technical documentation | sonnet |
| `refactor-assistant` | Safe code refactoring | sonnet |

### Agent Configuration

Agents use YAML frontmatter to define behavior:

```yaml
---
name: agent-name
description: What the agent does
model: sonnet
allowed-tools:
  - Read
  - Edit
temperature: 0.3
---
```

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

## Skills

This configuration includes Claude Code Skills for auto-discovery of guidelines based on task context.

### Available Skills

| Skill | Description | Trigger Keywords |
|-------|-------------|------------------|
| **coding-guidelines** | Coding standards, quality, error handling | implement, add, create, fix, refactor, review |
| **security-audit** | Security guidelines, OWASP Top 10, input validation | auth, token, password, secret, security, XSS, CSRF |
| **performance-review** | Performance optimization, profiling, caching | slow, optimize, benchmark, profile, latency, cache |
| **api-design** | API design, architecture, logging, observability | REST, GraphQL, API, microservice, endpoint, SOLID |
| **project-workflow** | Workflow, git commits, issues, PRs, testing | commit, PR, issue, build, test, workflow, git |
| **documentation** | README, API docs, comments, cleanup | document, README, comment, changelog, format, lint |

### How Skills Work

1. Skills are auto-discovered from `.claude/skills/` directory
2. Each skill has a `SKILL.md` with YAML frontmatter defining name and description
3. Skills are activated based on trigger keywords in your request
4. Skills provide quick reference links to detailed guidelines

<details>
<summary>Progressive Disclosure Pattern & Skill Structure</summary>

### Progressive Disclosure Pattern

Skills use the Progressive Disclosure pattern with Import syntax for token efficiency:

1. **SKILL.md**: Contains only essential information (~50 lines)
2. **reference/**: Symlinks to detailed guideline files
3. **Import Syntax**: Use `@path/to/file` for on-demand loading (supports up to 5 levels deep)
4. **On-Demand loading**: Claude reads reference files only when necessary

```
skills/coding-guidelines/
├── SKILL.md              # Core info (~37 lines)
└── reference/            # Symlinks to detailed guidelines
    ├── general.md        → .claude/rules/coding/general.md
    ├── quality.md        → .claude/rules/coding/quality.md
    ├── error-handling.md → .claude/rules/coding/error-handling.md
    └── ...
```

**Benefits:**
- Initial load tokens: ~5000 → ~1000 (80% reduction)
- 1-level deep references for reliable loading
- Simplified path maintenance
- Import syntax provides intuitive file references

### Import Syntax

The `@path/to/file` Import syntax (introduced in v1.4.0) provides:
- More intuitive file references than traditional markdown links
- Support for up to 5 levels of recursive Import
- Both relative and absolute path support
- Automatic ignoring within code blocks

**Example:**
```markdown
# CLAUDE.md
## Core Guidelines
@.claude/rules/core/environment.md
@.claude/rules/workflow/workflow.md
@.claude/rules/coding/general.md
```

### Skill Structure

```yaml
---
name: skill-name
description: Description for auto-discovery (max 1024 chars)
allowed-tools: Read, Grep, Glob  # Optional: restrict tools
---

# Skill Title

## When to Use
- Use case 1
- Use case 2

## Reference Documents (Import Syntax)
@reference/guideline.md
```

</details>

---

## Scripts

### 1. install.sh

**Purpose:** Install backed up settings to a new system

**Features:**
- Install global settings (`~/.claude/`)
- Install project settings (specified directory)
- Install skills directory (`.claude/skills/`)
- Auto-backup existing files
- Select installation type (global/project/both)

**Usage:**
```bash
./scripts/install.sh
```

**Notes:**
- ⚠️ After installation, you MUST modify `git-identity.md` with your personal info!
- Existing files are backed up with `.backup_YYYYMMDD_HHMMSS` format

---

### 2. backup.sh

**Purpose:** Save current system settings to backup

**Features:**
- Backup global settings
- Backup project settings
- Backup skills directory (`.claude/skills/`)
- Create timestamped backups
- Option to replace existing backup

**Usage:**
```bash
./scripts/backup.sh
```

**When to use:**
- Before deploying current settings to another system
- After modifying settings to update backup
- Regular settings backup

---

### 3. sync.sh

**Purpose:** Synchronize settings between system and backup

**Features:**
- Bidirectional sync (backup ↔ system)
- Skills directory sync support
- Compare file differences
- Preview changes
- Safe backup creation

**Usage:**
```bash
./scripts/sync.sh
```

**Sync directions:**
- 1: Backup → System (apply backup settings to system)
- 2: System → Backup (save system settings to backup)
- 3: Compare only (no changes)

---

### 4. verify.sh

**Purpose:** Check backup integrity and completeness

**Features:**
- Directory structure verification
- Required files existence check
- Skills directory and SKILL.md validation
- Script execution permission check
- Statistics display

**Usage:**
```bash
./scripts/verify.sh
```

---

### 5. validate_skills.sh

**Purpose:** Validate SKILL.md files for format compliance

**Features:**
- YAML frontmatter validation
- Name field check (lowercase, numbers, hyphens, max 64 chars)
- Description field check (non-empty, max 1024 chars)
- File line count check (warning if > 500 lines)
- Reference directory existence check
- Optional PyYAML syntax validation

**Usage:**
```bash
./scripts/validate_skills.sh
```

**Validation Rules:**
| Field | Rule |
|-------|------|
| Frontmatter | Must start and end with `---` |
| name | `[a-z0-9-]+`, max 64 characters |
| description | Non-empty, max 1024 characters |
| File length | Warning if > 500 lines |

---

## Pre-commit Hook

Install the pre-commit hook to automatically validate SKILL.md files before commit:

```bash
./hooks/install-hooks.sh
```

The hook will:
- Detect changes to SKILL.md files
- Run `validate_skills.sh` automatically
- Block commits with invalid SKILL.md files

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

- **Claude Code User Guide**: `CLAUDE_CODE_REAL_GUIDE.md` in project
- **Configuration Examples**: See `global/` and `project/` directories
- **Troubleshooting**: Check error messages from each script

---

## Important Notes

1. **Personal Information Protection**
   - `git-identity.md` contains personal information
   - Be careful when using public repositories!

2. **Pre-Backup Verification**
   - Always backup before important changes
   - Check differences before overwriting

3. **Project Settings**
   - Customize appropriately for each project
   - Reach agreement when sharing with team

---

## Version

- **Version**: 1.4.0
- **Last Updated**: 2026-01-22

### Changelog

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

---

**Happy Coding with Claude!**
