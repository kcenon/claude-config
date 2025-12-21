# Claude Config Plugin

A Claude Code Plugin providing comprehensive development guidelines and best practices.

## Installation

### Via Plugin System (Recommended)

```bash
# Add marketplace
/plugin marketplace add kcenon/claude-config

# Install plugin
/plugin install claude-config@kcenon/claude-config
```

### Via Direct Loading (Development)

```bash
claude --plugin-dir ./plugin
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
│   └── documentation/
├── hooks/
│   └── hooks.json            # Security and formatting hooks
└── README.md
```

## Requirements

- Claude Code with Plugin support (v1.0.0+)

## License

BSD-3-Clause
