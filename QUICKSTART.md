# Quick Start Guide

A 3-minute guide to easily deploy CLAUDE.md settings to another system.

---

## Contents

```
claude_config_backup/
├── enterprise/      # Enterprise settings (system-wide)
├── global/          # Global CLAUDE settings (~/.claude/)
├── project/         # Project CLAUDE settings
├── plugin/          # Claude Code Plugin (Beta)
├── plugin-lite/     # Lightweight Plugin (Guardrails Only)
├── scripts/         # Automation scripts
├── docs/            # Design docs and guides
├── README.md        # Detailed guide
└── QUICKSTART.md    # This file
```

---

## 3-Minute Installation

### Step 1: Copy (30 seconds)

**macOS/Linux:**
```bash
# Copy via USB, cloud, or network
cp -r claude_config_backup ~/

# Or
git clone https://github.com/kcenon/claude-config.git ~/claude_config_backup
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/kcenon/claude-config.git ~\claude_config_backup
```

### Step 2: Install (1 minute)

**macOS/Linux:**
```bash
cd ~/claude_config_backup
./scripts/install.sh
```

**Windows (PowerShell 7+):**
```powershell
cd ~\claude_config_backup
.\scripts\install.ps1
```

**Selection:**
```
Select installation type:
  1) Global settings only (~/.claude/)
  2) Project settings only (current directory)
  3) Both (recommended)
  4) Enterprise settings only (admin required)
  5) All (Enterprise + Global + Project)

Selection (1-5) [default: 3]: 3
```

### Step 3: Personalize (1 minute)

**macOS/Linux:**
```bash
vi ~/.claude/git-identity.md
```

**Windows:**
```powershell
notepad $HOME\.claude\git-identity.md
```

**Example changes:**
```yaml
# Before
name: "Your Name"      # <- Change this
email: "you@email.com" # <- Change this
```

### Step 4: Restart (30 seconds)

```bash
# Quit and restart Claude Code
# Or open a new terminal
```

---

## Verification

```bash
# Check settings
cat ~/.claude/CLAUDE.md

# Verify files exist
ls ~/.claude/
```

---

## Daily Usage

### Backup (after settings change)

```bash
cd ~/claude_config_backup
./scripts/backup.sh
# Type: 3 (Both)
```

### Sync (between multiple systems)

```bash
cd ~/claude_config_backup
git pull
./scripts/sync.sh
# Direction: 3 (Compare only) -> 1 or 2 (Sync)
```

---

## Troubleshooting

### Scripts won't run

**macOS/Linux:**
```bash
chmod +x scripts/*.sh
```

**Windows (Execution Policy):**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### File not found

```bash
# Check path
ls -la ~/.claude/
ls -la ~/claude_config_backup/
```

### Worried about overwriting

```bash
# Check differences first
./scripts/sync.sh
# Select: 3 (Compare only)
```

---

## Learn More

See `README.md` for detailed information:
- Advanced usage
- Scenario-based guides
- FAQ

---

## What's Next

### Try a skill

> **Two invocation modes.** `/git-status`, `/code-quality`, `/security-audit`, `/performance-review`, `/pr-review` are slash-catalog skills — Claude Code's `/`-autocomplete will suggest them. The workflow-automation set (`issue-work`, `pr-work`, `release`, `issue-create`, `branch-cleanup`, `harness`, `doc-index`, `doc-review`, `implement-all-levels`) is intentionally hidden under `~/.claude/skills/_internal/` and resolved by the **Skill Aliases** table in `global/CLAUDE.md`. Type the keyword as the leading command — the leading `/` is optional, but `/`-autocomplete will not suggest these. See [README → Skills](README.md#skills--what-you-can-do).

````bash
# Slash-catalog skills (autocompleted)
/git-status                              # Check repo status
/code-quality src/                       # Review code quality

# Keyword-aliased skills (no autocomplete; alias table resolves them)
issue-create my-project --type feature   # leading slash optional
issue-work my-project 42                 # automate an issue from start to PR
````

### Choose your path

| I want to... | Go to |
|--------------|-------|
| Understand what I just installed | [What You Get](README.md#what-you-get) |
| See all available skills | [Skills](README.md#skills--what-you-can-do) |
| Customize hooks and settings | [HOOKS.md](HOOKS.md) |
| Set up for my team | [Enterprise Settings](README.md#enterprise-settings) |
| Understand token optimization | [Token Optimization](README.md#token-optimization) |
| Design multi-agent teams | Run `/harness` in Claude Code |

---

**Installation complete! Now enjoy Claude Code!**
