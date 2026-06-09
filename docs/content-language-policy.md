# Content-Language Policy

> Introduced by epic #409 (sub-issues #410 Phase 1, #411 Phase 2).
> Deferred from default context via `.claudeignore` — this document ships
> for human readers but does not consume Claude's context budget.

This repository's content-language enforcement is configurable per install.
The `CLAUDE_CONTENT_LANGUAGE` environment variable selects the active
policy; the installer writes the chosen value into
`~/.claude/settings.json` and renders the corresponding policy phrase into
the three rule documents that describe the rule to humans and to Claude.

## Installer UI (simplified)

Both `bootstrap.{sh,ps1}` and `scripts/install.{sh,ps1}` present a
two-option prompt that maps directly to a fixed-language guarantee for
artifacts (commits, PRs, issues, comments, generated documents):

| UI choice | `CLAUDE_CONTENT_LANGUAGE` value | Guarantee |
|-----------|----------------------------------|-----------|
| English | `english` | All artifacts in English (ASCII only, Hangul rejected) |
| Korean  | `exclusive_bilingual` | Each artifact is either English-only or Korean-only — no inline mixing |

The simplified UI lives in a single source of truth at
`scripts/lib/install-prompts.sh` (bash) and
`scripts/lib/InstallPrompts.psm1` (PowerShell). Both files mirror each
other byte-for-byte for prompt strings and value mappings; both bash
installers and both PowerShell installers `source` / `Import-Module`
this single library, so prompt edits cannot drift between the four
entry points.

### Asymmetric defaults

The Content Language prompt defaults to **English** (option 1), while the
Agent Conversation Language prompt defaults to **Korean** (option 2).
This asymmetry is intentional: the most common configuration for Korean
operators in this codebase is "Claude responds in Korean, but artifacts
ship in English." With these defaults, pressing Enter twice during a
fresh install lands directly on that combination, requiring no extra
keystrokes for the common case while still letting English-only
operators take the same path with two `1` keystrokes.

### Drift guards

Two regression tests enforce that the installer prompts and the policy
phrase table never drift:

- `tests/scripts/test-installer-prompt-drift.sh` — compares the bash lib
  and the PowerShell module on canonical policy values, the
  policy → phrase mapping, the legacy classification, and the prompt
  defaults. Wired into `.github/workflows/validate-hooks.yml`.
- `tests/scripts/test-language-policy-drift.sh` — verifies that each
  rule document `.md` matches its `.tmpl` rendered with the english
  phrase, and that every CLAUDE_CONTENT_LANGUAGE value renders
  deterministically. Sources `install-prompts.sh` so it cannot drift
  from the installer phrase table.

### Legacy migration warning

When the installer detects an existing `~/.claude/settings.json` whose
`CLAUDE_CONTENT_LANGUAGE` is one of the legacy values
(`korean_plus_english`, `any`), it prints an informational warning
explaining that the simplified UI no longer surfaces that value and
that the new selection will replace it. Operators who want to keep the
legacy value cancel the installer and edit `settings.json` directly.

## Hook coverage (gh artifact gate)

The `pr-language-guard.{sh,ps1}` PreToolUse hook intercepts every
`gh` invocation that would publish artifact text to GitHub, validating
the `--title`, `--body`, and `--notes` arguments against the resolved
policy before the command reaches the API.

| `gh` command surface | Validated argument(s) | Notes |
|-----------------------|------------------------|-------|
| `gh pr      create \| edit`           | `--title`, `--body`         | |
| `gh pr      comment`                  | `--body`                    | |
| `gh pr      review`                   | `--body`                    | review-thread comment |
| `gh issue   create \| edit`           | `--title`, `--body`         | |
| `gh issue   comment`                  | `--body`                    | |
| `gh release create \| edit`           | `--title`, `--notes`        | release notes |

Out-of-scope `gh` commands (no artifact text — `view`, `list`, `merge`,
`checkout`, `release delete`, `release upload`, etc.) bypass the hook.

### Parsing limits

The hook returns `allow` for arguments it cannot reliably parse at the
shell layer. These cases defer to other safeguards (server-side review,
the `commit-msg` hook for committed content):

- `$(...)` command substitution inside `--body`/`--title`/`--notes`
- Heredoc bodies
- File references: `--body-file`, `--notes-file`, `-F` (release notes file)

### Direct API bypass

`gh api` is not in the default `settings.json` allowlist. Calls to
`gh api` therefore require explicit per-invocation user permission,
which provides a stronger gate than the hook would. The hook does not
attempt to parse `gh api` arguments.

## Policies (full validator surface)

The validator continues to accept four values for backward compatibility
with existing installs and for advanced users. Two of them
(`korean_plus_english`, `any`) are **not surfaced in the installer UI**
and must be set by editing `~/.claude/settings.json` directly.

| Value | Surfaced in UI | Validator behavior | Rule document phrase |
|-------|----------------|--------------------|----------------------|
| `english` (default, unset, empty) | yes | ASCII printable + whitespace only | `English` |
| `exclusive_bilingual` | yes (Korean) | Per-document mode: English-only (if no Hangul) or Korean-only with ASCII permitted inside four allowed containers (if any Hangul syllable present) | `English or Korean (document-exclusive)` |
| `korean_plus_english` | no (advanced) | ASCII + Hangul Syllables / Jamo / Compat Jamo, inline mixing permitted | `English or Korean` |
| `any` | no (advanced) | Skip language validation entirely | `any language` |

The two advanced policies are retained because (a) `korean_plus_english`
preserves backward compatibility with installs that pre-date the
`exclusive_bilingual` rollout (issue #447), and (b) `any` is the
documented escape hatch for OSS repositories that accept contributions
in any language. Attribution enforcement is unaffected by both.

Attribution enforcement is **not** governed by this env var.
`attribution-guard.{sh,ps1}` and the attribution checks inside
`commit-message-guard` remain active for every policy value.

## The `exclusive_bilingual` Policy (issue #447)

`exclusive_bilingual` enforces **document-level language exclusivity**:
each title, body, or commit description is validated as either an
English-only document or a Korean-only document, never a mix of bare
Korean prose with inline English tokens.

### Mode selection

Mode is chosen per document, automatically:

- **English mode** — the text contains zero Hangul syllable characters
  (U+AC00 to U+D7A3). Validation is identical to the `english` policy:
  ASCII printable (0x20 to 0x7E) and whitespace only. Any accented
  Latin, CJK, or emoji is rejected.
- **Korean mode** — the text contains at least one Hangul syllable.
  After stripping the four allowed ASCII containers below, the residual
  text must contain zero `[A-Za-z]` characters.

### Allowed ASCII containers in Korean mode

The validator strips these in the order listed and then scans what
remains for bare English letters. Strip order matters: fenced blocks
are handled first so backticks inside a fence are not mis-stripped as
inline code, and the translation form is stripped last so nested
parentheses inside a code block are preserved inside the code.

1. **Fenced code blocks** — triple backticks, multi-line.
2. **Inline code** — single backticks, single-line.
3. **URLs** — `https?://` followed by non-whitespace.
4. **`한국어(English)` translation form** — a Hangul run followed by
   optional whitespace and a parenthesized ASCII expression on one
   line. Use this for unavoidable proper nouns that have an established
   Korean translation.

### Accept / reject matrix

Drawn from the original `#447` design. Reviewers can use this table to
reason about edge cases in PR descriptions and issue bodies.

| Input | Verdict | Remediation |
|-------|---------|-------------|
| `PR을 만든다` | reject | `` `PR`을 만든다 `` wrapped, or `풀 리퀘스트(PR)를 만든다` |
| `/pr-work 를 실행` | reject | `` `/pr-work` `` wrapped in backticks |
| `GitHub Actions에서` | reject | `깃허브 액션(GitHub Actions)에서` |
| `버전 v1.10.0 배포` | reject | `버전 1.10.0 배포` or `` `v1.10.0` `` wrapped |
| `훅(hook)을 설치` | accept | --- |
| `https://example.com 참조` | accept | --- |
| ``이슈 `#247` 참조`` | accept | `#` plus digits is ASCII-non-letter, no wrap required |

Pure-English documents under `exclusive_bilingual` behave identically
to `english` — there is no regression for existing English-only PRs.

### When to choose this policy

Pick `exclusive_bilingual` when:

- You author documentation, PRs, and issues in Korean but want to avoid
  drift into the loose mixed-language style that `korean_plus_english`
  permits.
- You want the translation form (`한국어(English)`) to be the single
  canonical remediation for unavoidable English terms, producing a
  consistent voice across the repository.

Pick `korean_plus_english` instead if:

- Your workflow routinely mixes Korean prose with bare English tokens
  (product names, CLI commands) and wrapping them all in backticks or
  translation forms would be disruptive.

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
2. Each of the four policies produces output containing the expected
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
