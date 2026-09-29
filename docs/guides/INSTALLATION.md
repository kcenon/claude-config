# Installation Guide

Moved from the [README](../../README.md) so the entry page stays short. Korean: [INSTALLATION.ko.md](INSTALLATION.ko.md).

## One-Line Installation

### Public Repository

```bash
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.ps1 | iex
```

> **What bootstrap does for you.** It checks for the Claude Code CLI and, on consent, runs Anthropic's native installer (`https://claude.ai/install.sh`) so the `claude` binary lands in `~/.local/bin/` and supports background auto-update. The npm package `@anthropic-ai/claude-code` is no longer used. PowerShell uses the parallel `claude.ai/install.ps1`. See [PREREQUISITES.md → Auto-installed by bootstrap](https://github.com/kcenon/claude-config/blob/develop/PREREQUISITES.md#auto-installed-by-bootstrap).

### Non-interactive install

For CI or unattended setups, pre-select answers with the same environment
variables `scripts/install.sh` uses (no prompts), or force every default with
`--yes`:

```bash
# Unattended: pick the install type via env, accept every other default
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | INSTALL_TYPE=3 bash

# Force defaults for every prompt
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash -s -- --yes
```

```powershell
# Unattended: pick the install type via env, accept every other default
$env:INSTALL_TYPE = '3'; irm https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.ps1 | iex

# Force defaults for every prompt
$env:FORCE_MODE = '1'; irm https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.ps1 | iex
```

Recognized overrides: `INSTALL_TYPE`, `PROJECT_DIR`, `INSTALL_NPM`, `OVERWRITE`,
`AGENT_LANGUAGE`, `CONTENT_LANGUAGE`. PowerShell also accepts `FORCE_MODE=1`
for the same default-accepting unattended path that Bash exposes as `--yes`.
When a prompt is reached interactively over `curl | bash`, bootstrap reads your
answer from `/dev/tty` instead of consuming the piped script body.

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

# 3. Verify Git identity (edit only if missing or wrong)
grep -E "^(name|email):" ~/.claude/git-identity.md
```

### Windows (PowerShell)

```powershell
# 1. Clone repository
git clone https://github.com/kcenon/claude-config.git ~\claude_config_backup

# 2. Run install script (PowerShell 7+ recommended)
cd ~\claude_config_backup
.\scripts\install.ps1

# 3. Verify Git identity (edit only if missing or wrong)
Get-Content $HOME\.claude\git-identity.md | Select-String '^(name|email):'
```

> **Note**: Requires PowerShell 7+ (`pwsh`). Install via `winget install Microsoft.PowerShell`.
> If you get an execution policy error, run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

Windows installs `global/settings.windows.json`; CI parity gates keep it aligned
with the Unix profile except for documented Windows-only PowerShell allowances.

#### Docker-compatible dual-variant install

`install.ps1` deploys **both** PowerShell (`.ps1`) and bash (`.sh`) variants of
every hook and utility script into `~/.claude/hooks/` and `~/.claude/scripts/`.
The `.sh` files are written with LF line endings (UTF-8, no BOM).

This matters when the Windows host's `~/.claude/` is bind-mounted into a Linux
Claude Code container (e.g. via the companion [claude-docker](https://github.com/kcenon/claude-docker)
project): the container entrypoint rewrites `pwsh ... -File foo.ps1` hook
commands to `foo.sh`, which only works if the matching `.sh` file exists on
the mount. The installer also runs a pairing audit and warns about any `.ps1`
without a `.sh` sibling (or vice versa) so Docker-side rewrites do not silently
resolve to missing files.

> **See also**: [`docs/CLAUDE_DOCKER_CONTRACT.md`](../../docs/CLAUDE_DOCKER_CONTRACT.md) —
> formal contract between claude-config and claude-docker covering directory
> layout, hook command grammar, dual-variant pairing, the `.full-suite-active`
> probe, and CRLF normalization rules.

### Plugin Installation (Beta)

Install as a Claude Code Plugin for easy distribution and updates:

```bash
# Add marketplace
/plugin marketplace add kcenon/claude-config

# Install plugin (marketplace: kcenon-plugins)
/plugin install claude-config@kcenon-plugins
```

Or test locally:

```bash
# Load plugin directly (for development/testing)
claude --plugin-dir ./plugin
```

See [plugin/README.md](../../plugin/README.md) for more details.

### Lightweight Plugin (Behavioral Guardrails Only)

Want just the core behavioral corrections without the full suite?

```bash
# Install lite plugin (marketplace: kcenon-plugins)
claude plugin marketplace add kcenon/claude-config
claude plugin install claude-config-lite@kcenon-plugins

# Or test locally
claude --plugin-dir ./plugin-lite
```

| Method | What You Get |
|--------|-------------|
| Full plugin | Complete configuration with all skills, agents, and hooks |
| **Lite plugin** | Core behavioral guardrails for LLM coding mistakes |
| Bootstrap script | Full system configuration deployed to ~/.claude/ |

See [plugin-lite/README.md](../../plugin-lite/README.md) for more details.

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

Both installers record a SHA-256 manifest for this tree at `<enterprise-dir>/.install-manifest.json`. A re-install then keeps a locally edited policy file instead of overwriting it, and a drift check can tell a stale deployment apart from an edited one. Set `BOOTSTRAP_FORCE=1` to overwrite without the prompt. On POSIX the copies and the manifest placement run through `sudo` when the enterprise root is not writable; the manifest itself is left readable so an audit needs no elevation. Retired rules are not deleted. See [docs/install.md](../../docs/install.md).

## Personal Settings (CLAUDE.local.md)

For machine-specific settings that shouldn't be committed to version control, create `CLAUDE.local.md` in your project root.

```bash
# Copy the template
cp project/CLAUDE.local.md.template CLAUDE.local.md
```

Use it for local server URLs, machine-specific paths, and personal workflow preferences. Do **not** put credentials or API keys here — use environment variables instead.

This file is gitignored and has the lowest priority in Claude Code's memory hierarchy.

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
GITHUB_REF=v1.14.0 \
INSTALL_DIR=~/my-claude-config \
bash -c "$(curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh)"
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITHUB_USER` | `kcenon` | GitHub user/org owning the repo |
| `GITHUB_REPO` | `claude-config` | Repository name |
| `GITHUB_REF` | latest release tag (e.g. `v1.14.0`) | Tag, branch, or commit to clone. Pinning to a tag is SLSA-aligned supply-chain hardening — the install is reproducible and resistant to a transient compromise of `main`. Override with `develop` only for development testing. |
| `INSTALL_DIR` | `~/claude_config_backup` | Where to clone the repo |

> **Deprecated**: `GITHUB_BRANCH` is preserved as a one-release alias for `GITHUB_REF` and emits a stderr deprecation warning when set. Migrate to `GITHUB_REF` before the next major release.

</details>
