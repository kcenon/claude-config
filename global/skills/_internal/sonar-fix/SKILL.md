---
name: sonar-fix
description: Parse sonarcloud[bot] PR comments, classify findings, codify whitelisted auto-fixes, escalate the rest.
argument-hint: "<pr-number> [--dry-run]"
user-invocable: true
disable-model-invocation: true
allowed-tools: "Bash(gh *)"
max_iterations: 3
halt_conditions:
  - { type: success,  expr: "sonarcloud[bot] reports Quality Gate PASS" }
  - { type: fallback, expr: "no rule matches whitelist after 3 attempts" }
  - { type: limit,    expr: "3 identical re-scan failures" }
loop_safe: false
severity: S2
finding_levels: [S1, S2, S3]
iso_class: none
---

# sonar-fix

## Overview

The `sonar-fix` skill processes PR decoration emitted by SonarQube Cloud
via the `sonarcloud[bot]` GitHub account. It parses the bot's summary
and inline review comments, classifies each finding by rule and
severity, and follows a `classify -> fix -> escalate` flow. Whitelisted
rules (see `reference/auto-fixable-rules.md`) are eligible for codified
auto-fixes in later phases; everything else is escalated back to the
PR author as a single consolidated comment. No SonarQube REST API
tokens are required; the bot's PR comments are the only data source.

## Classify

The skill reads two channels from the PR conversation:

1. The single `sonarcloud[bot]` **summary comment**, which carries the
   Quality Gate verdict (`PASS` or `FAIL`).
2. The `sonarcloud[bot]` **inline review comments**, one per finding,
   anchored to a diff line.

For every inline comment, the parser extracts `rule_id`, `severity`,
`file:line`, and `message`, producing a `(rule_id, severity)` mapping
keyed by location. The parsing contract is captured in
`reference/comment-format.md` and must be treated as the single source
of truth for regex and field layout.

## Summary

After classification the skill posts a single comment to the PR with a
breakdown table: total findings, count per rule, count per severity,
and which findings are eligible for auto-fix versus escalation. The
comment is idempotent across runs so re-scans replace rather than
append.

## Escalate

Findings that do not match an entry in the auto-fix whitelist are
reported using the body in `reference/escalation-template.md`. The
escalation comment is also idempotent: a single HTML marker comment
identifies prior escalations from this skill so subsequent runs update
the existing comment instead of stacking new ones.

## Halt Conditions

The skill stops in three cases, paraphrased from the frontmatter:

- **Success**: the latest `sonarcloud[bot]` summary reports Quality
  Gate PASS, meaning no further action is needed.
- **Fallback**: after three classification attempts no remaining
  finding matches the auto-fix whitelist, so the skill escalates and
  exits.
- **Limit**: three identical re-scan failures in a row (same
  rule + same location) indicate the codified fix is not converging,
  so the skill stops to avoid a tight loop.

## Out of Scope

- Codified fix logic for the six whitelisted rules: deferred to P2
  (S1481, S1128) and P4 (S1854, S1192, S125, S1116).
- Integration with the `pr-work` and `release` skills: deferred to P3.
- Registration in the global `Skill Aliases` table in
  `global/CLAUDE.md`: deferred to P5.
- SonarQube REST API access, token management, or non-PR sources of
  findings: out of scope by design (the bot comment channel is
  authoritative).

## References

- [reference/auto-fixable-rules.md](reference/auto-fixable-rules.md)
- [reference/comment-format.md](reference/comment-format.md)
- [reference/escalation-template.md](reference/escalation-template.md)
