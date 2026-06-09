# Prerequisites

This document lists the tools required to install and run claude-config and its hooks. Verify each tool before running `bootstrap.sh` or `scripts/install.sh`; the bootstrap script will refuse to continue if a required tool is missing.

## Quick Check

```bash
for cmd in jq gh git perl pwsh; do
    if command -v "$cmd" >/dev/null 2>&1; then
        printf '  %-6s OK (%s)\n' "$cmd" "$(command -v "$cmd")"
    else
        printf '  %-6s MISSING\n' "$cmd"
    fi
done
```

## Required Tools

| Tool | Min version | Why claude-config needs it |
|------|------------:|----------------------------|
| `git` | 2.30+ | Repository operations, hook installation, worktrees |
| `jq` | 1.6+ | JSON parsing in `commit-message-guard`, `merge-gate-guard`, `attribution-guard`, `pr-language-guard`, `task-created-validator`, and other PreToolUse hooks |
| `gh` | 2.40+ | `merge-gate-guard` calls `gh pr checks`; the `/issue-work`, `/pr-work`, and `/release` skills shell out to `gh` for PR/issue lifecycle |
| `perl` | 5.20+ | `validate-hooks.yml` and `markdown-anchor-validator` use Perl regex; `lib/timeout-wrapper.sh` falls back to `perl alarm` when `timeout`/`gtimeout` are unavailable |
| `bash` | 4.0+ | `markdown-anchor-validator` requires associative arrays; macOS ships bash 3.2 — install GNU bash via Homebrew or use the Linux runner |

## Optional Tools

| Tool | Min version | Used by |
|------|------------:|---------|
| `pwsh` (PowerShell) | 7.0+ | Windows hook scripts (`global/hooks/*.ps1`); not needed on macOS/Linux unless you maintain the `.ps1` counterparts |
| `python3` | 3.8+ | Fallback JSON parser in `task-created-validator.sh`; `tests/scripts/*.py`; `scripts/spec_lint.py` |
| `shellcheck` | 0.7+ | Optional lint for `global/hooks/*.sh`; required only if running `validate-hooks.yml` locally |
| `coreutils` (`gtimeout`) | — | Faster `merge-gate-guard` timeout; the perl-alarm fallback in `lib/timeout-wrapper.sh` works without it |

## Auto-installed by bootstrap

`bootstrap.sh` and `bootstrap.ps1` detect a missing Claude Code CLI and offer to run the official Anthropic native installer (`https://claude.ai/install.sh` or `claude.ai/install.ps1`) on user consent. This places `claude` under `~/.local/bin/` (POSIX) or the equivalent user path (Windows) and supports background auto-update. If you decline at the prompt, install manually before running hook-dependent skills.

| Tool | How it is installed | Why claude-config needs it |
|------|---------------------|----------------------------|
| `claude` (Claude Code CLI) | Native installer via `bootstrap.{sh,ps1}` (consent prompt) or manual `curl -fsSL https://claude.ai/install.sh \| bash` | Hooks like `version-check`, batch scripts (`/issue-work`, `/pr-work`, `/release`), and the `claude --version` probe rely on the binary being on `PATH` |

## Install Commands by Platform

### macOS (Homebrew)

```bash
# Required
brew install git jq gh perl bash

# Optional
brew install --cask powershell        # pwsh
brew install python3 shellcheck coreutils
```

### Debian / Ubuntu (apt)

```bash
# Required
sudo apt-get update
sudo apt-get install -y git jq perl bash
# gh: install from official repo (see https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
type -p curl >/dev/null || sudo apt-get install -y curl
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
&& sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
&& sudo apt-get update \
&& sudo apt-get install -y gh

# Optional
sudo apt-get install -y python3 shellcheck
# pwsh: see https://learn.microsoft.com/powershell/scripting/install/install-ubuntu
```

### RHEL / Fedora / CentOS (yum/dnf)

```bash
# Required
sudo dnf install -y git jq perl bash
sudo dnf install -y 'dnf-command(config-manager)'
sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install -y gh

# Optional
sudo dnf install -y python3 ShellCheck
# pwsh: see https://learn.microsoft.com/powershell/scripting/install/install-rhel
```

### Windows (winget — preferred)

```powershell
# Required
winget install --id Git.Git -e
winget install --id jqlang.jq -e
winget install --id GitHub.cli -e
winget install --id StrawberryPerl.StrawberryPerl -e
winget install --id Microsoft.PowerShell -e         # pwsh

# Optional
winget install --id Python.Python.3.12 -e
```

### Windows (Chocolatey — alternative)

```powershell
choco install git jq gh strawberryperl powershell-core
choco install python3 shellcheck
```

## Per-Hook Tool Map

The table below shows which hook needs which tool, so an operator can decide whether a missing tool is critical for their workflow.

| Hook | Required tool(s) | Behavior if missing |
|------|------------------|---------------------|
| `commit-message-guard.sh` | `jq` | Hook fails open; `commit-msg` git hook still gates |
| `merge-gate-guard.sh` | `gh`, `jq` | Hook fails open; server-side branch protection still gates |
| `pr-language-guard.sh` | `jq` | Hook fails open; server-side review still catches |
| `attribution-guard.sh` | `jq` | Hook fails open; `commit-msg` hook still gates committed content |
| `markdown-anchor-validator.sh` | `bash` 4+, `perl` | Auto-skip on macOS bash 3.2 with a notice |
| `task-created-validator.sh` | `jq` or `python3` | Hook fails open |
| `pre-edit-read-guard.sh` | `jq` | Hook fails open |
| `instructions-loaded-reinforcer.sh` | `jq` (preferred), falls back to hand-escape | Hook still emits JSON, with reduced robustness |
| `post-compact-restore.sh` | `jq` (preferred) | Same as above |

## Verifying After Install

After installing the prerequisites, run:

```bash
bash bootstrap.sh         # refuses to continue if any required tool is missing
bash scripts/install.sh   # installs hooks; verifies via `scripts/check_versions.sh`
```

If `bootstrap.sh` reports a missing tool, install it from the table above and re-run. The list is intentionally short so a fresh contributor can be productive in under five minutes.
