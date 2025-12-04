# Git Identity Configuration

## User Information

Use the git identity configured on your system. Claude Code will automatically detect and use your system's git configuration.

## How It Works

Claude Code reads your git identity from the system configuration:

```bash
# Check current git identity
git config user.name
git config user.email
```

## Configuration Commands

If you need to set up git identity on a new system:

```bash
# Local repository configuration
git config user.name "Your Name"
git config user.email "your.email@example.com"

# Global configuration (recommended)
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## Relationship with Project Settings

This file defines the policy for **who** makes the commits:
- Claude Code uses your system's git configuration
- No hardcoded values - respects each user's identity
- For commit message format, refer to project-specific `git-commit-format.md`

## Verification

To verify your current git configuration:

```bash
git config user.name
git config user.email
```

The output should show your configured name and email.

## Priority Order

Git identity is resolved in the following order:
1. Repository-level config (`.git/config`)
2. Global user config (`~/.gitconfig`)
3. System config (`/etc/gitconfig`)

---

*Version: 1.0.0*
