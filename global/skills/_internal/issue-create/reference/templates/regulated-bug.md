# Regulated Bug Issue Template

Issue body template used when `$REGULATED_TRACK=true` (Phase 0a) and the user
selects `type/bug`. The opening fenced YAML block is the canonical regulated
metadata serialization defined in `../regulated-fields.md` "Embedded YAML block
format" -- preserve it verbatim. The 5W1H sections that follow match the standard
issue template (`workflow/reference/5w1h-examples.md`), with a Reproduction
sub-section under "How" because bugs need it.

> **Loading**: Loaded only when Phase 0a sets `$REGULATED_TRACK=true` and the
> chosen issue type is `type/bug`.

---

````markdown
```yaml
regulated:
  requirement_id: <SRS-CAT-NNN | null>
  risk_level: <acceptable | ALARP | unacceptable | null>
  clause_refs:
    - <STANDARD-NUMBER>
    - <STANDARD-NUMBER>
```

## What

<one-paragraph description of the defect: the observed behavior, the expected behavior, and the gap between them>

- Observed: <what the system does that is wrong>
- Expected: <what the system should do per requirement / standard>
- Severity context: <whether this defect can produce a hazard situation, and at what frequency>

## Why

<why this defect matters: the safety / compliance / functional impact>

- Impact: <e.g. "Range guard in SRS-CALC-014 fails open under specific input shape; can lead to over-dose hazard H-12">
- Standard: <clause refs that the defect violates; mirror the YAML block above when the bug is safety-relevant>
- Priority justification: <why this priority given the regulated context>

## Where

- Files / Components: <repository-relative paths>
- Standards in scope: <e.g. "IEC 62304 Class B software item SI-CALC; ISO 14971 hazard H-12">
- Affected version(s): <commit / tag range where the defect is reachable>
- Related issues / PRs: <#NNN cross-references>

## How

### Reproduction Steps

1. <step 1>
2. <step 2>
3. <step 3>

Minimum reproduction artifact: <command line, input file, or test case id>

### Root Cause Hypothesis

<one to three bullets if known; "unknown -- to be determined during triage" is acceptable>

### Acceptance Criteria

- [ ] A failing test exists that reproduces the defect on the current main commit (verify-fail-first per `core/principles.md` "Verify & Iterate")
- [ ] The fix makes that test pass without regressing the existing safety test suite
- [ ] Traceability matrix row for `<requirement_id>` is updated when the fix changes the code paths or test ids associated with the requirement
- [ ] Risk record(s) referenced in `clause_refs` are reviewed; if the defect created a residual-risk regression, the record's status moves back to `draft` until re-controlled

### Verification Notes

- Test ids that will verify the fix: <TC-CAT-NNN, ...>
- Risk-control link: <H-NN or R-NN, plus the control measure id `CM-NN` if applicable>
- Hazard escalation needed: <yes / no -- yes if this defect alters the residual-risk evaluation of a hazard>
````

---

## Notes for the skill body

1. The YAML block at the top is filled in from the Phase 0b prompts. Optional
   fields the operator left blank are written as the literal `null`, never
   omitted -- see `../regulated-fields.md` "Embedded YAML block format" rule 4.
2. The bug template's matrix row in `regulated-fields.md` is more permissive
   than the feature template: `requirement_id` and `risk_level` are
   `required-if-safety`, and `clause_refs` is `>=1 if safety`. Phase 0b decides
   which prompts to ask based on the safety-relevant detection rule (any path
   matched by a `paths:` glob in `compliance/<standard>.md`) before falling
   back to omission with `null`.
3. The "Reproduction Steps" sub-section is mandatory for bugs and absent from
   the feature template -- a bug without a reproduction is unreviewable, and
   the regulated track does not change that. Keep it under "How" so the issue
   structure stays consistent with the project's `workflow/github-issue-5w1h.md`.
4. The "Acceptance Criteria" section includes the verify-fail-first rule from
   `core/principles.md`. Do not strip it on edit -- the regulated track relies
   on it to keep test-first verification visible to auditors.
5. "Hazard escalation needed" is the new bullet that distinguishes a regulated
   bug from a regulated feature. When the answer is `yes`, the implementer
   knows to re-run `/risk-control evaluate` after the fix lands so the risk
   file's residual-risk evaluation is regenerated. When `no`, no extra step
   is required beyond the matrix update.
