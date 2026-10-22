# Use Cases and FAQ

Moved from the [README](../../README.md) so the entry page stays short. Korean: [USE_CASES.ko.md](USE_CASES.ko.md).

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
git clone YOUR_PROJECT_REPO_URL project
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

# Verify Git identity; edit only if missing or wrong
grep -E "^(name|email):" ~/.claude/git-identity.md
```

---

### Use Case D: Batch-Process Open Issues or Failing PRs

External orchestrators that spawn one fresh `claude` process per item.
Each process handles exactly one issue (or PR), so context state cannot
leak between items — item N+1 starts with the same CLAUDE.md / skill
attention pool as item 1. Complements the in-session batch mode of
`/issue-work` and `/pr-work` by pushing isolation to the OS process
boundary.

Use these wrappers when:

- You expect the batch to exceed the in-session safe cap (default 5, hard
  cap 10 without `--force-large`) and want stricter per-item isolation.
- You are running unattended (cron, CI, overnight) and want each item to
  start from a clean slate regardless of how long the batch runs.
- You need per-item logs on disk for post-run analysis rather than a
  single scrollback in a live terminal.

```bash
# Process up to 5 open issues in a repo (default limit)
./scripts/batch-issue-work.sh kcenon/claude-config

# Process up to 3 open issues
./scripts/batch-issue-work.sh kcenon/claude-config 3

# Process failing PRs instead
./scripts/batch-pr-work.sh kcenon/claude-config
```

```powershell
# PowerShell equivalents
.\scripts\batch-issue-work.ps1 -OrgProject kcenon/claude-config
.\scripts\batch-issue-work.ps1 -OrgProject kcenon/claude-config -Limit 3
.\scripts\batch-pr-work.ps1    -OrgProject kcenon/claude-config
```

Per-item logs are written to `~/.claude/batch-logs/<timestamp>/`:

- `issue-<number>.log` for each issue handled by `batch-issue-work`
- `pr-<number>.log` for each PR handled by `batch-pr-work`

On any item failure, the batch **pauses and exits non-zero**. Successful
items are not rolled back. Inspect the log for the failed item, fix the
underlying cause, and re-run the orchestrator — items already merged will
be skipped because they are no longer in the open list.

---

<details>
<summary><strong>Advanced Usage</strong> (GitHub Actions, Environment Variables)</summary>

## FAQ

### Q1: Why do I need to personalize Git identity?

**A:** `git-identity.md` contains personal information (name, email), so each installation must use the operator's own values. The installer auto-fills it from `git config --global user.name` and `git config --global user.email` when both values exist; edit the file only if those values are missing or wrong.

```bash
vi ~/.claude/git-identity.md
# Change name and email only when the installed values are missing or wrong
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

**A:** For a private fork, bootstrap needs the fork in two places:

1. Download `bootstrap.sh` from the fork with a Personal Access Token, as in
   [Private Repository](INSTALLATION.md#private-repository), with the fork's owner in the URL.
   Create the token under GitHub Settings > Developer settings > Personal access tokens.
2. Set `GITHUB_USER` to the fork's owner (and `GITHUB_REPO` if you renamed it), as in
   *Customize with Environment Variables* under Advanced Usage. Without them bootstrap
   clones `kcenon/claude-config`. Set `GITHUB_REF` too if the fork lacks the default release tag.

bootstrap clones the fork with a plain `git clone`; the token from step 1 is not passed on,
so git needs its own credentials for the fork (for example, a credential helper).

## Memory sync (multi-machine)

Memory sync keeps Claude Code's auto-memory consistent across all your machines via a private git store. See:

Scheduler automation is Unix-only: macOS uses `launchd`, Linux uses a `systemd` user timer, and Windows users should run the Linux path through WSL. Native PowerShell scheduling is not supported for memory sync.

- [Operations guide](../../docs/MEMORY_SYNC.md) - Daily ops, troubleshooting, rollback, conflict resolution
- [Threat model](../../docs/THREAT_MODEL.md) - Security analysis, 7 threat categories, 5-layer defense
- [Validation spec](../../docs/MEMORY_VALIDATION_SPEC.md) - Validator contract and frontmatter schema
- [Trust model](../../docs/MEMORY_TRUST_MODEL.md) - Trust tiers and lifecycle
