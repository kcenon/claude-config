# Repository Structure

Moved from the [README](../../README.md) so the entry page stays short. Korean: [STRUCTURE.ko.md](STRUCTURE.ko.md).

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
│           ├── doc-update/     # User-invocable
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
│   └── workflows/              # PR validation, scheduled drift checks, release automation
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
