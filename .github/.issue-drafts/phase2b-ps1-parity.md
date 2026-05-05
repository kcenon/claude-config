## What

Port the routing-only audit and skill frontmatter drift checks added to `scripts/validate_skills.sh` in #441 to its PowerShell sibling `scripts/validate_skills.ps1`. Windows users who run validation locally currently miss both new checks; CI runs on Ubuntu so only the bash path is exercised.

Scope: only `scripts/validate_skills.ps1`. No behavioral change to bash, CI, or docs.

## Why

`scripts/validate_skills.ps1` (403 lines) is a hand-ported sibling of `validate_skills.sh`. The two scripts share the same contract (exit code 0 on pass, non-zero on fail, warnings are non-fatal) and are expected to agree on what constitutes a violation.

After #441, the bash script enforces a routing-only discipline on `global/CLAUDE.md`, `project/CLAUDE.md`, `enterprise/CLAUDE.md` and warns on skill frontmatter drift. Without PS1 parity:

- Windows authors editing harness or skill files locally do not see the same failures they will hit in CI.
- The pre-push/pre-commit value of local validation is asymmetric across platforms.
- Future drift detection cannot rely on "one validator ran" — it has to be "both ran".

## Who

- Owner: @kcenon
- Reviewers: harness / skill-system maintainers

## When

phase-2b of #439 (harness-optimization epic). Unblocks epic closure.

## Where

- `scripts/validate_skills.ps1` (extend; parallel to the bash extensions in #441)

No other file should change. CI workflow paths already include `scripts/validate_skills.sh`; PS1 is covered by the same path filter implicitly because any change to the PS1 file is accompanied by a bash change under the same trigger, and Windows users run it locally.

## How

### Technical Approach

Mirror the three bash extensions from #441:

1. **`Test-ClaudeMd` function**: same classification rules as bash `validate_claude_md`:
   - Treat the first `---` as a footer separator and stop scanning body.
   - Classify each non-blank, non-heading line: bullets / table rows / `@./` imports / blockquotes => routing; inside a heading matching `[Ii]nvariant` => routing; anything else => prose.
   - Fail if `prose / (prose + routing) > AUDIT_PROSE_RATIO` (default 0.30, overridable via env var).
2. **Frontmatter drift checks in `Test-SkillFile`**: same rules as bash:
   - If `max_iterations` or `halt_condition` declared in frontmatter, body must mention `loop|retry|iteration|poll` (warning).
   - If `loop_safe: false` declared, body must have a heading matching side-effect / idempoten / loop-safety (warning).
3. **Main-loop invocation**: add a `CLAUDE.md 라우팅 감사` section that iterates the three harness files.

### Acceptance Criteria

- [ ] `scripts/validate_skills.ps1` gains the three extensions listed above.
- [ ] Current tree passes: `pwsh scripts/validate_skills.ps1` reports the same prose ratios (15.4% / 25.7% / 0.0%) and exits 0.
- [ ] Injecting 5 prose lines into a test file triggers a non-zero exit with a readable report (matching bash's 62.5% > 30% output).
- [ ] No regressions in existing PS1 behavior (same YAML check, same spec_lint delegation, same summary output).

### Non-goals

- Do not change bash behavior (the contract is fixed).
- Do not add `bootstrap`/`sync` wiring (documented as intentionally skipped in #439).
- Do not attempt `tiers.ref_docs` alias validation (requires a convention design not yet agreed).

## Related

- Part of #439 (harness-optimization epic)
- Parity with #441 (phase-2a)
- Unblocks epic closure once merged
