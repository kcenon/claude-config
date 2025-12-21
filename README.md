# Claude Configuration Backup & Deployment System

<p align="center">
  <strong>Easily share and sync CLAUDE.md settings across multiple systems</strong>
</p>

<p align="center">
  <a href="#-one-line-installation">Installation</a> •
  <a href="#-structure">Structure</a> •
  <a href="#-scripts">Scripts</a> •
  <a href="#-use-cases">Use Cases</a> •
  <a href="#-faq">FAQ</a> •
  <a href="README.ko.md">Korean</a>
</p>

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

---

## Structure

```
claude_config_backup/
├── global/                      # Global settings backup (~/.claude/)
│   ├── CLAUDE.md               # Main configuration file
│   ├── settings.json           # Hook settings (security, session)
│   ├── commit-settings.md      # Commit/PR attribution policy
│   ├── conversation-language.md # Conversation language settings
│   ├── git-identity.md         # Git user information
│   └── token-management.md     # Token management policy
│
├── project/                     # Project settings backup
│   ├── CLAUDE.md               # Project main configuration
│   ├── .claude/
│   │   ├── settings.json       # Hook settings (auto-formatting)
│   │   └── skills/             # Claude Code Skills
│   │       ├── coding-guidelines/
│   │       │   ├── SKILL.md    # Coding standards skill
│   │       │   └── reference/  # Symlinks to guidelines
│   │       ├── security-audit/
│   │       │   ├── SKILL.md    # Security audit skill
│   │       │   └── reference/  # Symlinks to guidelines
│   │       ├── performance-review/
│   │       │   ├── SKILL.md    # Performance review skill
│   │       │   └── reference/  # Symlinks to guidelines
│   │       ├── api-design/
│   │       │   ├── SKILL.md    # API and architecture skill
│   │       │   └── reference/  # Symlinks to guidelines
│   │       ├── project-workflow/
│   │       │   ├── SKILL.md    # Workflow and project management skill
│   │       │   └── reference/  # Symlinks to guidelines
│   │       └── documentation/
│   │           ├── SKILL.md    # Documentation standards skill
│   │           └── reference/  # Symlinks to guidelines
│   └── claude-guidelines/      # Guideline modules
│       ├── api-architecture/   # API & Architecture
│       │   ├── api-design.md
│       │   ├── architecture.md
│       │   ├── logging.md
│       │   └── observability.md
│       ├── coding-standards/   # Coding standards
│       │   ├── general.md
│       │   ├── quality.md
│       │   ├── error-handling.md
│       │   ├── concurrency.md
│       │   ├── memory.md
│       │   └── performance.md
│       ├── project-management/ # Project management
│       │   ├── build.md
│       │   ├── testing.md
│       │   └── documentation.md
│       ├── operations/         # Operations
│       │   ├── monitoring.md
│       │   └── cleanup.md
│       ├── communication.md
│       ├── environment.md
│       ├── git-commit-format.md
│       ├── problem-solving.md
│       ├── security.md
│       ├── workflow.md
│       └── conditional-loading.md
│
├── scripts/                     # Automation scripts
│   ├── install.sh              # Install to new system
│   ├── backup.sh               # Backup current settings
│   ├── sync.sh                 # Sync settings
│   └── verify.sh               # Verify backup integrity
│
├── bootstrap.sh                 # One-line install script
├── README.md                    # Detailed guide (English)
├── README.ko.md                 # Detailed guide (Korean)
├── QUICKSTART.md               # Quick start guide
└── HOOKS.md                    # Hook configuration guide
```

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

### Project Hooks (`project/.claude/settings.json`)

| Hook | Event | Description |
|------|-------|-------------|
| **Auto Formatting** | PostToolUse | Runs language-specific formatters after file edits |

**Supported Formatters:**
- Python: `black`, `isort`
- TypeScript/JavaScript: `prettier`
- C++: `clang-format`
- Kotlin: `ktlint`
- Go: `gofmt`
- Rust: `rustfmt`

For detailed configuration, see [HOOKS.md](HOOKS.md).

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

### Progressive Disclosure Pattern

Skills use the Progressive Disclosure pattern for token efficiency:

1. **SKILL.md**: Contains only essential information (~50 lines)
2. **reference/**: Symlinks to detailed guideline files
3. **On-Demand loading**: Claude reads reference files only when necessary

```
skills/coding-guidelines/
├── SKILL.md              # Core info (~37 lines)
└── reference/            # Symlinks to detailed guidelines
    ├── general.md        → claude-guidelines/coding-standards/general.md
    ├── quality.md        → claude-guidelines/coding-standards/quality.md
    ├── error-handling.md → claude-guidelines/coding-standards/error-handling.md
    └── ...
```

**Benefits:**
- Initial load tokens: ~5000 → ~1000 (80% reduction)
- 1-level deep references for reliable loading
- Simplified path maintenance

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

## Quick Reference
- [Link to guideline](reference/guideline.md)
```

---

## Quick Start

### Scenario 1: Install Settings on New System

```bash
# 1. Clone repository
git clone https://github.com/kcenon/claude-config.git ~/claude_config_backup

# 2. Run installation
cd ~/claude_config_backup
./scripts/install.sh

# 3. Personalize Git identity (Required!)
vi ~/.claude/git-identity.md

# 4. Restart Claude Code
```

### Scenario 2: Backup Current Settings

```bash
cd ~/claude_config_backup
./scripts/backup.sh

# Select type:
#  1) Global settings only
#  2) Project settings only
#  3) Both (recommended)
```

### Scenario 3: Sync Settings

```bash
cd ~/claude_config_backup
./scripts/sync.sh

# Select direction:
#  1) Backup → System
#  2) System → Backup
#  3) Compare only
```

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
cp -r ~/project/claude-guidelines ~/claude_config_backup/project/
```

### Customize with Environment Variables

```bash
# When using bootstrap.sh
GITHUB_USER=your-username \
GITHUB_REPO=your-repo \
INSTALL_DIR=~/my-claude-config \
bash -c "$(curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh)"
```

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

- **Version**: 1.0.0
- **Last Updated**: 2025-12-03

---

## Contributing

If you'd like to improve this backup system:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

---

**Happy Coding with Claude!**
