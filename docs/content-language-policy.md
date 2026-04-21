# Content-Language Policy

> Introduced by epic #409 (sub-issues #410 Phase 1, #411 Phase 2).
> Deferred from default context via `.claudeignore` — this document ships
> for human readers but does not consume Claude's context budget.

This repository's content-language enforcement is configurable per install.
The `CLAUDE_CONTENT_LANGUAGE` environment variable selects one of three
policies; the installer writes the chosen value into
`~/.claude/settings.json` and renders the corresponding policy phrase into
the three rule documents that describe the rule to humans and to Claude.

## Policies

| Value | Validator behavior | Rule document phrase |
|-------|--------------------|----------------------|
| `english` (default, unset, empty) | ASCII printable + whitespace only | `English` |
| `korean_plus_english` | ASCII + Hangul Syllables / Jamo / Compat Jamo | `English or Korean` |
| `any` | Skip language validation entirely | `any language` |

Attribution enforcement is **not** governed by this env var.
`attribution-guard.{sh,ps1}` and the attribution checks inside
`commit-message-guard` remain active for every policy value.

## Install-time Substitution

Three rule documents ship with a `.tmpl` twin containing the
`{{CONTENT_LANGUAGE_POLICY}}` placeholder:

- `global/commit-settings.md.tmpl`
- `project/.claude/rules/core/communication.md.tmpl`
- `project/.claude/rules/workflow/git-commit-format.md.tmpl`

`scripts/install.sh` (bash) and `scripts/install.ps1` (PowerShell) render
the `.tmpl` files into their `.md` siblings at the install destination,
replacing the placeholder with the phrase for the chosen policy. If a
`.tmpl` is absent, the installer falls back to copying the pre-rendered
canonical `.md` as-is.

The canonical `.md` files in the repo are always pre-rendered to `english`
so a direct clone remains coherent. `tests/scripts/test-language-policy-drift.sh`
guards against drift between each canonical `.md` and its `.tmpl`.

## Enterprise Conflict Detection

Enterprise-managed policies live at the highest precedence tier
(`install.sh:122-124`). When the deployed enterprise `CLAUDE.md` mandates
`english` but the operator selects a more permissive policy during
install, the installer prints a warning and asks for confirmation before
proceeding. The warning cites the enterprise path so the operator can
reconcile the conflict before the installation completes.

## Drift Test

`tests/scripts/test-language-policy-drift.sh` runs two checks per rule
document:

1. Canonical `.md` equals `.tmpl` rendered with the `english` phrase.
2. Each of the three policies produces output containing the expected
   phrase.

The test is wired into `tests/hooks/test-runner.sh` via the standard
`test-*.sh` glob and runs in CI alongside the hook test suite.

## Changing Policy After Install

Edit `~/.claude/settings.json` directly:

```json
{
  "env": {
    "CLAUDE_CONTENT_LANGUAGE": "korean_plus_english"
  }
}
```

Restart the Claude Code session so the hooks re-inherit the env var.
Rule documents on disk stay at the previously rendered phrase - re-run
the installer to re-render them, or edit the `.md` files in place.

## Sources of Truth

| Concern | File |
|---------|------|
| Validator dispatch (bash) | `hooks/lib/validate-language.sh` |
| Rule 2 branching (bash) | `hooks/lib/validate-commit-message.sh` |
| Validator dispatch (PowerShell) | `global/hooks/lib/LanguageValidator.psm1` |
| Phrase table (bash installer) | `scripts/install.sh` - `get_policy_phrase` |
| Phrase table (PowerShell installer) | `scripts/install.ps1` - `Get-PolicyPhrase` |
| Phrase table (drift test) | `tests/scripts/test-language-policy-drift.sh` |

Keeping the three phrase tables in sync is part of the drift-test
invariant. Any edit to one must edit the others.
