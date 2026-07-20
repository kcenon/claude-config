# Claude Config Plugin

A Claude Code Plugin providing comprehensive development guidelines and best practices.

## Installation

### Via Marketplace (Recommended)

This repository ships a marketplace manifest at `.claude-plugin/marketplace.json`,
so the plugins install through the standard marketplace flow. Add the marketplace
once, then install:

```bash
# Add this repo as a marketplace (GitHub owner/repo shorthand)
claude plugin marketplace add kcenon/claude-config

# Install the plugin
claude plugin install claude-config@kcenon-plugins

# Or install at project scope (shared with the team via .claude/settings.json)
claude plugin install claude-config@kcenon-plugins --scope project
```

Inside an interactive Claude Code session, use the slash-command equivalents:

```
/plugin marketplace add kcenon/claude-config
/plugin install claude-config@kcenon-plugins
```

### Via Direct Loading (Development)

```bash
claude --plugin-dir ./plugin
```

Multiple plugins can be loaded simultaneously:

```bash
claude --plugin-dir ./plugin --plugin-dir ./plugin-lite
```

## Skills Included

| Skill | Description |
|-------|-------------|
| `coding-guidelines` | Comprehensive coding standards for quality, naming, error handling |
| `api-design` | API design guidelines for REST, GraphQL, architecture |
| `security-audit` | Security best practices and vulnerability prevention |
| `performance-review` | Performance optimization and monitoring guidelines |
| `project-workflow` | Git, testing, build, and workflow management |
| `documentation` | Documentation and communication standards |
| `ci-debugging` | Systematic CI/CD failure diagnosis and resolution |

## Hooks

The plugin includes security hooks that:
- Block access to sensitive files: the `.env.*` family and `.envrc`,
  credential containers (.pem, .key, .p12, .pfx), SSH private keys, and
  AWS credential files. `.env.example` / `.env.sample` / `.env.template`
  stay allowed. See `docs/plugin-vs-global.md` for the limits of the
  inline check.
- Prevent dangerous bash commands (rm -rf /, chmod 777)
- Auto-format code on save (if formatters are available)

### Standalone-Only Behavior

When the full claude-config suite is installed (via `scripts/install.sh`
or `scripts/install.ps1`), the plugin's security guards detect this via
`~/.claude/.full-suite-active` and exit early — the canonical hooks from
the global suite perform the actual checks. When the plugin is installed
standalone, its simplified guards are the active defense.

The detection is per-hook: if the probe advertises some canonical hooks
but not others, the plugin keeps its fallback active only for the hooks
that are not covered. Any probe state that cannot be parsed (missing,
malformed, unknown schema) falls back to the plugin guard as a safe
default.

See [`docs/plugin-vs-global.md`](../docs/plugin-vs-global.md) for the
probe file format, behavior matrix, and failure modes.

## Directory Structure

```
plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── agents/                   # Bundled agent definitions
├── skills/                   # Agent Skills
│   ├── coding-guidelines/
│   │   ├── SKILL.md
│   │   └── reference/
│   ├── api-design/
│   ├── security-audit/
│   ├── performance-review/
│   ├── project-workflow/
│   ├── documentation/
│   └── ci-debugging/
├── hooks/
│   └── hooks.json            # Security and formatting hooks
├── .lsp.json                 # LSP server registration
├── .claudeignore             # Token-optimization ignore list
└── README.md
```

## Plugin Manifest Compatibility

Verified against Claude Code plugin system (May 2026). The `plugin.json` manifest
contains only the official schema fields (`$schema`, `name`, `version`, `description`,
`author`, `homepage`, `repository`, `license`, `keywords`). The minimum Claude Code
version is documented in prose under "Requirements" below, since the manifest schema
has no version-gating field.

Component directories (`agents/`, `skills/`, `hooks/hooks.json`, `.mcp.json`, `.lsp.json`)
are auto-discovered by Claude Code at the plugin root — no explicit path fields are
declared in the manifest. Explicit path fields are only needed when overriding the
default discovery layout.

## Requirements

- Claude Code v2.1.0+

## License

BSD-3-Clause
