# Escalation Template

Used when sonar-fix finds at least one finding outside the whitelist.
The skill posts this body as a single PR comment, replacing any
previous escalation comment from the same skill.

```markdown
## Sonar findings outside auto-fix whitelist

The following findings require manual review and cannot be auto-fixed
by this skill:

| File:Line | Rule | Severity | Message |
|-----------|------|----------|---------|
| <path>:<line> | <rule_id> | <severity> | <message> |

Source: <sonarcloud[bot] summary comment URL>

After resolving manually, re-trigger sonar-fix or wait for the next
sonarcloud[bot] re-scan.
```

## Idempotency
The skill marks its comment with an HTML marker comment so subsequent
runs replace rather than append:

```html
<!-- sonar-fix:escalation -->
```
