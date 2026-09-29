# Claude Configuration Backup & Deployment System

Status: active · Release: [v1.14.0](https://github.com/kcenon/claude-config/releases/tag/v1.14.0) · [Korean](README.ko.md)

<p align="center">
  <a href="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml"><img src="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <strong>Easily share and sync CLAUDE.md settings across multiple systems</strong>
</p>

Claude Code documentation moved to `code.claude.com/docs/en/*`; the links here use the new hosts. [COMPATIBILITY.md](COMPATIBILITY.md#settings-field-inventory-and-stability) classifies the stability of each settings field.

---

## Quick Start

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

For detailed scenarios, see [Use Cases and FAQ](docs/guides/USE_CASES.md).

---

## What You Get

Install claude-config and Claude Code immediately gains these capabilities:

**Security** — `.env`, `.pem`, and credentials are automatically blocked from being read or written. Dangerous commands like `rm -rf /` are intercepted before execution.

**Auto-formatting** — Code is formatted on every save: Python (black), TypeScript (prettier), Go (gofmt), Rust (rustfmt), C++ (clang-format), Kotlin (ktlint).

**Workflow automation** — `/issue-work` takes a GitHub issue from open to merged PR in one command. `/release` generates changelogs and creates releases. `/pr-work` diagnoses and fixes CI failures.

**Commit quality** — Broken markdown links, AI attribution, and non-conventional commit messages are caught before they reach your repository.

**Configurable content language** — Pick at install time whether commit messages, PR bodies, and documentation are written in English (ASCII plus allowlisted English typography) or Korean (per-artifact strict, no inline mixing). The three-option preset installer prompt maps to `CLAUDE_CONTENT_LANGUAGE=english|exclusive_bilingual`; advanced legacy values (`korean_plus_english`, `any`) remain available via direct `settings.json` edit.

**Code quality on demand** — `/security-audit`, `/performance-review`, `/code-quality`, and `/pr-review` provide specialized analysis when you need it.

**Agent team design** — `/harness` designs multi-agent architectures tailored to your project, with 6 architecture patterns and orchestrator templates.

**Cross-platform** — Everything works on macOS, Linux, and Windows (PowerShell). The memory sync scheduler is the Unix-only exception; see [`COMPATIBILITY.md`](COMPATIBILITY.md#cross-platform-notes).

**On-demand context** — Rules and skills load only when the current task needs them; detailed references stay in `.claude/reference/` until you ask for them. See [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md).

---

## Installation

bootstrap clones the release tag it pins, checks for the Claude Code CLI, and deploys the global layer to `~/.claude/` and, if you choose, a project layer.

```bash
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.ps1 | iex
```

To install as a Claude Code plugin from this repository's marketplace (`kcenon-plugins`):

```bash
claude plugin marketplace add kcenon/claude-config
claude plugin install claude-config@kcenon-plugins        # full suite
claude plugin install claude-config-lite@kcenon-plugins   # behavioral guardrails only
```

Non-interactive installs, private forks, Git clone, Windows notes, enterprise settings, `CLAUDE.local.md`, and environment variables are covered in the [Installation Guide](docs/guides/INSTALLATION.md).

---

## Documentation

| Topic | Page |
|-------|------|
| Installation, enterprise and personal settings, advanced usage | [docs/guides/INSTALLATION.md](docs/guides/INSTALLATION.md) |
| Repository layout | [docs/guides/STRUCTURE.md](docs/guides/STRUCTURE.md) |
| Automatic behavior, rules, skills, agents, MCP, scripts, git hooks | [docs/guides/FEATURES.md](docs/guides/FEATURES.md) |
| Use cases, FAQ, memory sync | [docs/guides/USE_CASES.md](docs/guides/USE_CASES.md) |
| Hooks reference | [HOOKS.md](HOOKS.md) |
| Prerequisites and compatibility | [PREREQUISITES.md](PREREQUISITES.md), [COMPATIBILITY.md](COMPATIBILITY.md) |
| Installer internals (manifest, prune, drift) | [docs/install.md](docs/install.md) |
| Branch model and release workflow | [docs/branching-strategy.md](docs/branching-strategy.md) |
| Official vs custom features | [docs/CUSTOM_EXTENSIONS.md](docs/CUSTOM_EXTENSIONS.md) |
| Context size and per-skill consumption | [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md), [docs/SKILL_TOKEN_REPORT.md](docs/SKILL_TOKEN_REPORT.md) |
| Memory sync operations and threat model | [docs/MEMORY_SYNC.md](docs/MEMORY_SYNC.md), [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) |
| README rules and the lint that enforces them | [docs/contributing/README_POLICY.md](docs/contributing/README_POLICY.md) |
| Release notes | [CHANGELOG.md](CHANGELOG.md) |

---

## Versioning

claude-config does **not** carry a single repo-wide version. Each shipped artifact has its own SemVer line that bumps independently, recorded in `VERSION_MAP.yml`:

| Field | Tracked artifact | Consumer files |
|-------|------------------|----------------|
| `suite` | The end-user release identifier shown in the status line and pinned by the one-line installers | Release link in `README.md` and `README.ko.md`; documented `GITHUB_REF` examples in `docs/guides/INSTALLATION.md` and `docs/guides/INSTALLATION.ko.md`; `bootstrap.sh`, `bootstrap.ps1` default `GITHUB_REF` pins |
| `plugin` | Marketplace plugin version | `plugin/.claude-plugin/plugin.json` |
| `plugin-lite` | Lite plugin (behavioral guardrails) | `plugin-lite/.claude-plugin/plugin.json` |
| `settings-schema` | Hook-emitting `settings.json` schema | `global/settings.json`, `global/settings.windows.json` |
| `hooks` | Shipping hook-bundle label (bumped per rollout) | _none — SemVer-validated by `check_versions`, no consumer file; bump via `/release --target hooks` (tag `hooks-v<version>`)_ |

`scripts/check_versions.sh` verifies each consumer file matches the field declared in `VERSION_MAP.yml`. Use `/release <field> <new-version>` (or `scripts/sync_versions.sh`) to bump exactly one field at a time. See [`docs/CLAUDE_DOCKER_CONTRACT.md`](docs/CLAUDE_DOCKER_CONTRACT.md) for how `suite` couples to claude-docker's tag line. Historical release notes live in [`CHANGELOG.md`](CHANGELOG.md).

---

## Contributing

1. Fork the repository
2. Create your feature branch from `develop` (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request against `develop`

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
