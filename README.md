# Claude Configuration Backup & Deployment System

<p align="center">
  <a href="https://github.com/kcenon/claude-config/releases"><img src="https://img.shields.io/badge/version-1.10.0-blue.svg" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-green.svg" alt="License"></a>
  <a href="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml"><img src="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <strong>Easily share and sync CLAUDE.md settings across multiple systems</strong>
</p>

<p align="center">
  <em>Docs note (2026): Claude Code documentation moved to <code>code.claude.com/docs/en/*</code>. All documentation links use the new URLs; older hosts appear only in migration and version-history notes. See <a href="COMPATIBILITY.md#settings-field-inventory-and-stability">COMPATIBILITY.md</a> for settings field stability classification.</em>
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

# 2. Verify Git identity (auto-filled from git config when available)
grep -E "^(name|email):" ~/.claude/git-identity.md

# 3. Restart Claude Code - Done!
```

**Common Tasks:**

| Task | macOS/Linux | Windows (PowerShell) |
|------|-------------|----------------------|
| Install settings | `./scripts/install.sh` | `.\scripts\install.ps1` |
| Backup settings | `./scripts/backup.sh` | `.\scripts\backup.ps1` |
| Sync settings | `./scripts/sync.sh` | `.\scripts\sync.ps1` |
| Verify backup | `./scripts/verify.sh` | `.\scripts\verify.ps1` |
| Batch open issues | `./scripts/batch-issue-work.sh <org/repo>` | `.\scripts\batch-issue-work.ps1 -OrgProject <org/repo>` |
| Batch failing PRs | `./scripts/batch-pr-work.sh <org/repo>` | `.\scripts\batch-pr-work.ps1 -OrgProject <org/repo>` |

For detailed scenarios, see [Use Cases](#use-cases).

---

## What You Get

Install claude-config and Claude Code immediately gains these capabilities:

**Security** — `.env`, `.pem`, and credentials are automatically blocked from being read or written. Dangerous commands like `rm -rf /` are intercepted before execution.

**Auto-formatting** — Code is formatted on every save: Python (black), TypeScript (prettier), Go (gofmt), Rust (rustfmt), C++ (clang-format), Kotlin (ktlint).

**Workflow automation** — `/issue-work` takes a GitHub issue from open to merged PR in one command. `/release` generates changelogs and creates releases. `/pr-work` diagnoses and fixes CI failures.

**Commit quality** — Broken markdown links, AI attribution, and non-conventional commit messages are caught before they reach your repository.

**Configurable content language** — Pick at install time whether commit messages, PR bodies, and documentation are written in English (ASCII only) or Korean (per-artifact strict, no inline mixing). The three-option preset installer prompt maps to `CLAUDE_CONTENT_LANGUAGE=english|exclusive_bilingual`; advanced legacy values (`korean_plus_english`, `any`) remain available via direct `settings.json` edit.

**Code quality on demand** — `/security-audit`, `/performance-review`, `/code-quality`, and `/pr-review` provide specialized analysis when you need it.

**Agent team design** — `/harness` designs multi-agent architectures tailored to your project, with 6 architecture patterns and orchestrator templates.

**Cross-platform** — Everything works on macOS, Linux, and Windows (PowerShell). The memory sync scheduler is the Unix-only exception; see [`COMPATIBILITY.md`](COMPATIBILITY.md#cross-platform-notes).

---

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

> **See also**: [`docs/CLAUDE_DOCKER_CONTRACT.md`](docs/CLAUDE_DOCKER_CONTRACT.md) —
> formal contract between claude-config and claude-docker covering directory
> layout, hook command grammar, dual-variant pairing, the `.full-suite-active`
> probe, and CRLF normalization guarantees.

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

Detailed reference documents live in `.claude/reference/`, outside the auto-loaded `.claude/rules/` tree, so they never enter initial context. Load them when needed:

```markdown
# Ask Claude to load a specific reference
@load: reference/agent-teams

# Or reference the file directly
Can you review .claude/reference/workflow/label-definitions.md?
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
│   ├── hooks/                  # Hook scripts, each in .sh + .ps1 — authoritative catalog: HOOKS.md
│   │   └── lib/               # Shared libraries
│   │       ├── AttributionValidator.psm1
│   │       ├── CommonHelpers.psm1  # PowerShell shared module
│   │       ├── LanguageValidator.psm1
│   │       ├── path-utils.sh
│   │       ├── rotate.sh/.ps1
│   │       ├── timeout-wrapper.sh
│   │       └── tokenize-shell.sh
│   ├── scripts/                # Utility scripts
│   │   ├── statusline-command.sh/.ps1
│   │   ├── team-report.sh/.ps1
│   │   └── weekly-usage.sh/.ps1
│   └── skills/                 # Global skills (user-invocable)
│       └── _internal/          # claude-config-owned skills (strict-validated)
│           ├── _shared/        # Cross-skill helpers (invariants.md)
│           ├── branch-cleanup/ # Clean merged/stale branches
│           ├── ci-fix/         # CI failure remediation workflow
│           ├── doc-index/      # Generate documentation index files
│           ├── doc-review/     # Markdown document review
│           ├── evidence-pack/  # Assemble per-release evidence packages
│           ├── fleet-orchestrator/ # Fleet orchestration patterns
│           ├── harness/        # Agent team & skill architecture design
│           ├── implement-all-levels/ # Enforce complete implementation
│           ├── issue-create/   # Create GitHub issues (5W1H)
│           ├── issue-work/     # GitHub issue workflow automation
│           ├── memory-review/  # Review stale/flagged/duplicate memories
│           ├── pr-work/        # Fix failed CI/CD for PRs
│           ├── preflight/      # Pre-push CI preflight checks
│           ├── release/        # Automated release with changelog
│           ├── research/       # Research/literature review
│           ├── risk-control/   # Manage hazard/risk records (regulated track)
│           ├── sonar-fix/      # SonarCloud finding triage and fixes
│           ├── soup-inventory/ # Maintain SOUP (third-party) register
│           └── traceability/   # Bidirectional traceability matrix
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
│       │   │   └── cpp-specifics.md
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
│       │   │   └── session-resume.md
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
│       ├── reference/          # On-demand reference docs (outside rules/, never auto-loaded)
│       │   ├── coding/         # anti-patterns.md
│       │   └── workflow/       # 5W1H examples, labels, automation, agent teams
│       ├── skills/             # 11 project skills (migrated from slash commands) — e.g. pr-review, code-quality, git-status, security-audit
│       ├── agents/             # Specialized agent configurations
│       │   ├── code-reviewer.md
│       │   ├── codebase-analyzer.md
│       │   ├── dependency-auditor.md
│       │   ├── documentation-writer.md
│       │   ├── qa-reviewer.md
│       │   ├── refactor-assistant.md
│       │   ├── structure-explorer.md
│       │   └── test-strategist.md
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
│       ├── InstallerFetch.psm1
│       ├── installer-fetch.sh
│       ├── validate-commit-message.sh  # Shared validation library
│       ├── validate-language.sh
│       └── validate-traceability.sh
│
├── .github/
│   └── workflows/
│       ├── validate-skills.yml     # CI skill validation (main-targeting PRs only)
│       ├── validate-hooks.yml      # CI hook validation (main-targeting PRs only)
│       └── validate-pr-target.yml  # Enforce develop-only merges to main
│
├── docs/                        # Design docs and guides
│   ├── branching-strategy.md   # Branch model, CI policy, release workflow
│   ├── CLAUDE_DOCKER_CONTRACT.md  # Integration contract with claude-docker (SSOT)
│   ├── install.md              # Installer flow, manifests, post-install verification
│   ├── SANDBOX_TLS.md          # Sandbox-aware TLS troubleshooting (gh, curl)
│   ├── TOKEN_OPTIMIZATION.md
│   ├── SKILL_TOKEN_REPORT.md
│   ├── CUSTOM_EXTENSIONS.md
│   ├── ad-sdlc-integration.md
│   ├── plugin-vs-global.md
│   ├── hooks-ownership.md
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
├── tests/                       # Hook + skill golden corpus, regression runners
├── bootstrap.sh/.ps1            # One-line install script (also auto-installs Claude Code CLI)
├── VERSION_MAP.yml              # Single Source of Truth for component SemVers (see "Versioning" below)
├── COMPATIBILITY.md             # settings.json field stability matrix vs Claude Code releases
├── ENFORCEMENT.md               # Three-layer attribution / commit guard enforcement model
├── PREREQUISITES.md             # Tool list and per-platform install commands
├── THIRD_PARTY_NOTICES.md       # Upstream attribution for vendored snippets
├── README.md                    # Detailed guide (English)
├── README.ko.md                 # Detailed guide (Korean)
├── QUICKSTART.md                # Quick start guide
└── HOOKS.md                     # Hook configuration guide
```

</details>

---

## Versioning

claude-config does **not** carry a single repo-wide version. Each shipped artifact has its own SemVer line that bumps independently, recorded in `VERSION_MAP.yml`:

| Field | Tracked artifact | Consumer files |
|-------|------------------|----------------|
| `suite` | The end-user "release" identifier surfaced by the README badge | `README.md`, `README.ko.md` shields URL |
| `plugin` | Marketplace plugin version | `plugin/.claude-plugin/plugin.json` |
| `plugin-lite` | Lite plugin (behavioral guardrails) | `plugin-lite/.claude-plugin/plugin.json` |
| `settings-schema` | Hook-emitting `settings.json` schema | `global/settings.json`, `global/settings.windows.json` |
| `hooks` | Shipping hook-bundle label (bumped per rollout) | _none — SemVer-validated by `check_versions`, no consumer file; bump via `/release --target hooks` (tag `hooks-v<version>`)_ |

`scripts/check_versions.sh` verifies each consumer file matches the field declared in `VERSION_MAP.yml`. Use `/release <field> <new-version>` (or `scripts/sync_versions.sh`) to bump exactly one field at a time — synchronizing all five fields would defeat the design and produce noisy "compatible-with-X.Y" badges that change for unrelated reasons. See [`docs/CLAUDE_DOCKER_CONTRACT.md`](docs/CLAUDE_DOCKER_CONTRACT.md) for how `suite` couples to claude-docker's tag line.

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

> For full hook configuration details and customization, see [HOOKS.md](HOOKS.md).

### Content Language Policy

Both installers (`install.sh` and `install.ps1`) prompt for a content-language policy after the installation-type selection. The simplified UI offers two choices that map to fixed-language guarantees for artifacts:

| UI choice | `CLAUDE_CONTENT_LANGUAGE` value | Validator accepts | Rule-document phrase |
|-----------|----------------------------------|-------------------|----------------------|
| English (default) | `english` | ASCII printable + whitespace only | `English` |
| Korean | `exclusive_bilingual` | Per-artifact: English-only OR Korean-only with limited ASCII containers, no inline mixing | `English or Korean (document-exclusive)` |

The validator additionally accepts two legacy values that are **not surfaced in the UI** — set them via direct `settings.json` edit if needed:

| Legacy value | When to use | Validator accepts |
|--------------|-------------|-------------------|
| `korean_plus_english` | Pre-issue-#447 installs that rely on inline mixing | ASCII + Hangul Syllables / Jamo / Compat Jamo |
| `any` | OSS repositories accepting any language | Skip language validation entirely |

The installer substitutes the chosen phrase into three rule-document templates (`global/commit-settings.md.tmpl`, `project/.claude/rules/core/communication.md.tmpl`, `project/.claude/rules/workflow/git-commit-format.md.tmpl`) so the documented rule matches the validator behavior.

**Scope boundary**: AI/Claude attribution enforcement is **not** governed by this env var — `attribution-guard` and the attribution checks in `commit-message-guard` remain active for every policy.

**Enterprise conflict detection**: When the deployed enterprise `CLAUDE.md` requires English and the operator selects a more permissive policy, the installer prints a warning and asks for confirmation before proceeding.

For the full design rationale, phrase tables, and drift-test invariants, see [`docs/content-language-policy.md`](docs/content-language-policy.md).

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
| `/pr-review` | Comprehensive PR analysis covering quality, security, performance, tests |

### Design and Documentation

`/git-status` is a slash-catalog skill; the rest in this table are keyword-aliased.

| Command | Mode | What it does |
|---------|------|-------------|
| `/harness` | keyword | Design agent teams and generate skills for any domain |
| `/doc-index` | keyword | Generate documentation index files (manifest, bundles, graph, router) |
| `/doc-review` | keyword | Review markdown documents for accuracy, anchors, cross-references |
| `/git-status` | slash | Repository status with actionable insights |
| `/implement-all-levels` | keyword | Enforce complete implementation of all tiers for tiered features |

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

For architecture patterns, display modes, hooks, and advanced configuration, see `.claude/reference/workflow/agent-teams.md`.

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

After installation, `~/.claude/git-identity.md` is auto-filled from `git config --global user.name` and `git config --global user.email` when both values exist. Edit it only if the values are missing or wrong.
Existing files are automatically backed up with `.backup_YYYYMMDD_HHMMSS` format.

---

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
GITHUB_REF=v1.10.0 \
INSTALL_DIR=~/my-claude-config \
bash -c "$(curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh)"
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITHUB_USER` | `kcenon` | GitHub user/org owning the repo |
| `GITHUB_REPO` | `claude-config` | Repository name |
| `GITHUB_REF` | latest release tag (e.g. `v1.10.0`) | Tag, branch, or commit to clone. Pinning to a tag is SLSA-aligned supply-chain hardening — the install is reproducible and resistant to a transient compromise of `main`. Override with `develop` only for development testing. |
| `INSTALL_DIR` | `~/claude_config_backup` | Where to clone the repo |

> **Deprecated**: `GITHUB_BRANCH` is preserved as a one-release alias for `GITHUB_REF` and emits a stderr deprecation warning when set. Migrate to `GITHUB_REF` before the next major release.

</details>

---

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

**A:** Use Personal Access Token during installation:

```bash
# Create token: GitHub Settings > Developer settings > Personal access tokens

# Installation
curl -sSL -H "Authorization: token YOUR_TOKEN" \
  https://raw.githubusercontent.com/your-user/claude-config/main/bootstrap.sh | bash
```

---

## Memory sync (multi-machine)

Memory sync keeps Claude Code's auto-memory consistent across all your machines via a private git store. See:

Scheduler automation is Unix-only: macOS uses `launchd`, Linux uses a `systemd` user timer, and Windows users should run the Linux path through WSL. Native PowerShell scheduling is not supported for memory sync.

- [Operations guide](docs/MEMORY_SYNC.md) - Daily ops, troubleshooting, rollback, conflict resolution
- [Threat model](docs/THREAT_MODEL.md) - Security analysis, 7 threat categories, 5-layer defense
- [Validation spec](docs/MEMORY_VALIDATION_SPEC.md) - Validator contract and frontmatter schema
- [Trust model](docs/MEMORY_TRUST_MODEL.md) - Trust tiers and lifecycle

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

**Current**: tracked in [`VERSION_MAP.yml`](VERSION_MAP.yml) (single source of truth — `suite` field). The shields.io badge at the top of this README is generated from the same field by `scripts/sync_versions.sh`. Do not hardcode version numbers in this document; bump them with `/release <field> <new-version>` instead.

Historical release notes now live in [`CHANGELOG.md`](CHANGELOG.md).

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
