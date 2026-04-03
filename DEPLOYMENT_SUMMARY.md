# Claude Configuration Backup & Deployment System

**Version**: 1.6.0
**Last Updated**: 2026-04-03

---

## System Overview

### Project Statistics

| Category | Count | Details |
|----------|-------|---------|
| **Global files** | 59 | Settings, hooks, skills, scripts |
| **Project files** | 65 | Rules, skills, agents, commands |
| **Enterprise files** | 3 | Policies and security rules |
| **Hook scripts** | 32 | 16 `.sh` + 16 `.ps1` |
| **Global skills** | 8 | + `_policy.md` |
| **Project skills** | 10 | Context-based + user-invocable |
| **Project agents** | 6 | Specialized agent definitions |
| **Project rules** | 33 | 9 categories |

### Three-Tier Architecture

| Tier | Location | Scope |
|------|----------|-------|
| **Enterprise** | `/Library/Application Support/ClaudeCode/` | Organization-wide |
| **Global** | `~/.claude/` | All projects |
| **Project** | `.claude/` | Current project only |

---

## Deployment Scripts

| Script | Purpose | Platform |
|--------|---------|----------|
| `install.sh` | Install to new system | macOS/Linux |
| `install.ps1` | Install to new system | Windows |
| `backup.sh` | Save current settings | macOS/Linux |
| `sync.sh` | Bidirectional sync | macOS/Linux |
| `verify.sh` | Integrity check | macOS/Linux |

### Quick Usage

```bash
# New system (3 minutes)
./scripts/install.sh

# Backup
./scripts/backup.sh

# Sync
./scripts/sync.sh
```

---

## Key Features

- **16 hook scripts** with macOS `.sh` and Windows `.ps1` variants
- **8 global skills**: branch-cleanup, doc-review, harness, implement-all-levels, issue-create, issue-work, pr-work, release
- **6 specialized agents**: code-reviewer, codebase-analyzer, documentation-writer, qa-reviewer, refactor-assistant, structure-explorer
- **Agent Teams**: Experimental multi-agent collaboration framework
- **Token optimization**: 86% reduction in initial token usage
- **Cross-platform**: Full macOS, Linux, Windows PowerShell support
- **Auto-formatting**: PostToolUse hooks for Python, TypeScript, C++, Kotlin, Go, Rust

---

## Documentation

| Document | Description |
|----------|-------------|
| `README.md` | Detailed guide (English) |
| `README.ko.md` | Detailed guide (Korean) |
| `QUICKSTART.md` | 3-minute setup guide |
| `HOOKS.md` | Hook configuration reference |
| `docs/TOKEN_OPTIMIZATION.md` | Token optimization guide |
| `docs/SKILL_TOKEN_REPORT.md` | Per-skill token analysis |
| `docs/CUSTOM_EXTENSIONS.md` | Official vs custom features |

---

## Achievements

| Metric | Before | After |
|--------|--------|-------|
| Install time | 30+ min | 3 min |
| Consistency | Manual | 100% automated |
| Backup coverage | None | Complete |
| Token usage | ~30,500 | ~4,300 (86% reduction) |
