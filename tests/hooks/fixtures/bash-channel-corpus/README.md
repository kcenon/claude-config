# Bash-channel guard fixtures

Mirrors the `dcg-corpus/` structure used by `test-dangerous-command-guard-golden.sh`.

| Directory | Hook under test | Expected decision |
|-----------|----------------|-------------------|
| `deny-read/` | `bash-sensitive-read-guard.sh` | `deny` |
| `deny-write/` | `bash-write-guard.sh` | `deny` |
| `allow/` | both hooks | `allow` |

Each fixture is a single JSON file with shape:

```json
{ "tool_name": "Bash", "tool_input": { "command": "..." } }
```

The companion runner is `test-bash-sensitive-read-guard.sh` /
`test-bash-write-guard.sh` — these inline-assertion suites generate
fixtures programmatically (via `jq -n --arg cmd ...`) so backslashes,
heredocs, and embedded quotes survive the JSON layer unchanged. The
on-disk fixtures here cover the Issue #477 acceptance-criteria minimum
and serve as a living reference for the documented attack classes.
