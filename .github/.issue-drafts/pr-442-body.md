Closes #442

## What

Port the routing-only audit and frontmatter drift checks from `scripts/validate_skills.sh` (#441) to its PowerShell sibling `scripts/validate_skills.ps1`. No bash, CI, or documentation changes.

## Why

After #441, the bash validator enforces routing-only discipline on the three harness files and warns on skill frontmatter drift. The PS1 sibling is hand-ported from bash (403 lines, matches the bash contract of exit 0 pass / non-zero fail / non-fatal warnings) and had diverged from the new bash behavior.

Without parity, Windows authors editing harness or skill files locally do not see the failures CI enforces on Ubuntu, and the pre-push value of local validation is asymmetric.

## How

Three additions that mirror the bash changes in #441:

1. **`Test-ClaudeMd` function** — same classification rules as bash `validate_claude_md`:
   - Treat the first `---` as a footer separator.
   - Classify each non-blank, non-heading line: bullets / table rows / `@./` imports / blockquotes -> routing. Lines inside a heading matching `[Ii]nvariant` -> routing. Anything else -> prose.
   - Fail if `prose / (prose + routing) > AUDIT_PROSE_RATIO` (default `0.30`, overridable via env var).
2. **Frontmatter drift checks in `Test-SkillFile`** — same rules as bash:
   - If `max_iterations` or `halt_condition` declared, body must mention `loop|retry|iteration|poll` (warning).
   - If `loop_safe: false` declared, body must have a heading matching side-effect / idempoten / loop-safety (warning).
3. **Main-loop invocation** — iterate the three harness files under a new `CLAUDE.md 라우팅 감사` section.

## Verification

Parity with the bash output on the current tree:

| File | bash (#441) | pwsh (this PR) |
|------|-------------|----------------|
| `global/CLAUDE.md` | prose=2, routing=11, 15.4% | prose=2, routing=11, 15.4% |
| `project/CLAUDE.md` | prose=9, routing=26, 25.7% | prose=9, routing=26, 25.7% |
| `enterprise/CLAUDE.md` | prose=0, routing=3, 0.0% | prose=0, routing=3, 0.0% |

PR summary counts: bash 222/222 + 12 warnings (exit 0), pwsh 253/253 + 13 warnings (exit 0). The PS1 delta is the pre-existing "YAML required fields" checks which bash delegates to PyYAML when available.

Failure-injection test (5 prose lines in a test harness file):

```
❌ 산문 비율 초과: 62.5% > 30% (prose=5, routing/invariant=3)
ℹ️  힌트: 절차 규칙은 docs/, global/skills/, 또는 프로젝트 rule 파일로 이동
EXIT=1
```

Matches bash byte-for-byte on the classification numbers and exit code.

## Non-goals

- No bash changes (contract already final in #441).
- No `bootstrap`/`sync` wiring (documented as intentionally skipped in #439).
- No `tiers.ref_docs` alias validation (requires convention design).

## Related

- Part of #439 (harness-optimization epic). This PR is the last actionable sub-issue; epic closure follows.
- Parity with #441 (phase-2a bash).
