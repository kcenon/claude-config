# Claude Config Plugin

A Claude Code Plugin providing comprehensive development guidelines and best practices.

## Installation

### Via CLI (Recommended)

```bash
# Install from git repository (subdirectory source)
claude plugin install claude-config --source git-subdir --url https://github.com/kcenon/claude-config --subdir plugin

# Or install with scope
claude plugin install claude-config --source git-subdir --url https://github.com/kcenon/claude-config --subdir plugin -s project
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
- Block access to sensitive files (.env, .pem, .key, etc.)
- Prevent dangerous bash commands (rm -rf /, chmod 777)
- Auto-format code on save (if formatters are available)

## Directory Structure

```
plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
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
└── README.md
```

## Plugin Manifest Compatibility

Verified against Claude Code plugin system (April 2026). The `plugin.json` manifest
contains only the official schema fields (`name`, `version`, `description`, `author`,
`homepage`, `repository`, `license`, `compatibility`, `keywords`).

Component directories (`agents/`, `skills/`, `hooks/hooks.json`, `.mcp.json`, `.lsp.json`)
are auto-discovered by Claude Code at the plugin root — no explicit path fields are
declared in the manifest. Explicit path fields are only needed when overriding the
default discovery layout.

## Requirements

- Claude Code v2.1.0+

## License

BSD-3-Clause
