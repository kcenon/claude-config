# Regulated Feature Issue Template

Issue body template used when `$REGULATED_TRACK=true` (Phase 0a) and the user
selects `type/feature`. The opening fenced YAML block is the canonical regulated
metadata serialization defined in `../regulated-fields.md` "Embedded YAML block
format" -- preserve it verbatim. The 5W1H sections that follow match the standard
issue template (`workflow/reference/5w1h-examples.md`).

> **Loading**: Loaded only when Phase 0a sets `$REGULATED_TRACK=true` and the
> chosen issue type is `type/feature`.

---

````markdown
```yaml
regulated:
  requirement_id: <SRS-CAT-NNN>
  risk_level: <acceptable | ALARP | unacceptable | null>
  clause_refs:
    - <STANDARD-NUMBER>
    - <STANDARD-NUMBER>
```

## What

<one-paragraph description of the new functionality and the user-visible behavior change>

- Current: <what exists today, or "no equivalent functionality">
- Expected: <what the feature delivers>
- Scope: <what is in / out of scope for this issue>

## Why

<motivation: the safety / compliance / functional driver>

- Driver: <e.g. "Risk-control measure for hazard H-12 requires an in-firmware range guard">
- Standard: <which clause refs this feature satisfies; mirror the YAML block above>
- Priority justification: <why this priority level given the regulated context>

## Where

- Files / Components: <repository-relative paths or component names>
- Standards in scope: <e.g. "IEC 62304 Class B software item SI-CALC; ISO 14971 hazard H-12">
- Related issues / PRs: <#NNN cross-references>

## How

### Technical Approach

<brief implementation outline; one to three bullets is enough at issue time>

### Acceptance Criteria

- [ ] <testable behavior 1>
- [ ] <testable behavior 2>
- [ ] Traceability matrix row for `<requirement_id>` is updated to include the new code paths and test ids
- [ ] Risk record(s) referenced in `clause_refs` remain in `controlled` status with no residual-risk regression

### Verification Notes

- Test ids that will verify this feature: <TC-CAT-NNN, ...>
- Risk-control link: <H-NN or R-NN, plus the control measure id `CM-NN` if applicable>
````

---

## Notes for the skill body

1. The YAML block at the top is filled in from the Phase 0b prompts. Optional
   fields the operator left blank are written as the literal `null`, never
   omitted -- see `../regulated-fields.md` "Embedded YAML block format" rule 4.
2. The angle-bracketed placeholders inside the block (`<SRS-CAT-NNN>`,
   `<STANDARD-NUMBER>`, etc.) are the literal placeholder shape shown to the
   operator during the interactive walk; the skill substitutes the operator's
   answers before calling `gh issue create`.
3. The "Acceptance Criteria" section deliberately includes two regulated-track
   bullets (matrix update, risk record status). Do not strip them on edit -- the
   `traceability` skill's `--check-only` validator looks for them as a heuristic
   for "the regulated track was followed when this feature was opened".
4. The `## Where` section names the standard scope so reviewers can pivot
   directly to the clause source. This is the only field where the standards
   list is repeated outside the YAML block (because human reviewers read the
   prose, machines read the block).
5. No section headings beyond the four 5W1H sections. The skill's later
   `## Output` summary table is appended by `gh issue create` consumers, not by
   this template.
