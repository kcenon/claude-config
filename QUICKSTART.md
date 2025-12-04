# Quick Start Guide

A 3-minute guide to easily deploy CLAUDE.md settings to another system.

---

## Contents

```
claude_config_backup/
├── global/          # Global CLAUDE settings
├── project/         # Project CLAUDE settings
├── scripts/         # Automation scripts
├── README.md        # Detailed guide
└── QUICKSTART.md    # This file
```

---

## 3-Minute Installation

### Step 1: Copy (30 seconds)

```bash
# Copy via USB, cloud, or network
cp -r claude_config_backup ~/

# Or
git clone https://github.com/kcenon/claude-config.git ~/claude_config_backup
```

### Step 2: Install (1 minute)

```bash
cd ~/claude_config_backup
./scripts/install.sh
```

**Selection:**
```
Select installation type:
  1) Global settings only (~/.claude/)
  2) Project settings only (current directory)
  3) Both (recommended)

Selection (1-3) [default: 3]: 3
```

### Step 3: Personalize (1 minute)

```bash
# Change Git identity to your information
vi ~/.claude/git-identity.md
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

```bash
chmod +x scripts/*.sh
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

**Installation complete! Now enjoy Claude Code!**
