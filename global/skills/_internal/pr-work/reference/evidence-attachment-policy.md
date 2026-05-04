# Evidence-Attachment Policy

Per-issue-type, per-iso-class evidence requirement matrix used by the
`pr-work` skill's Phase 9b (Evidence-attachment gate). The matrix defines
exactly what evidence a regulated PR must carry to merge, the formal
"within the last 24h" freshness check, the override mechanism, and the
failure-message format. The skill body delegates the per-row enforcement
to this document so the policy lives in one place.

> **Loading**: Loaded only when Phase 9b runs (which requires Phase 0a's
> `$REGULATED_TRACK=true`). Skip when the consumer project has no
> `compliance/` directory.

## Required Fields by Issue Type

The first dimension is the GitHub issue `type/*` label on the issue the PR
closes (parsed from `Closes #N` / `Fixes #N` / `Resolves #N` keywords in
the PR body). The second dimension is the `iso_class` declared in the
SKILL.md frontmatter of any skill the PR's diff edits, OR `none` when the
diff edits no SKILL.md. When the PR closes multiple issues, the strictest
row applies. When the diff touches multiple SKILLs at different classes,
the highest class applies.

| Issue type           | `iso_class: none`        | `iso_class: A`                                              |
|----------------------|--------------------------|-------------------------------------------------------------|
| `type/feature`       | (no requirement)         | `manifest.yaml` + `risk-file.yaml` excerpt + test reports   |
| `type/bug` (safety)  | (no requirement)         | `manifest.yaml` + `risk-file.yaml` excerpt + regression test report |
| `type/bug` (other)   | (no requirement)         | (no requirement)                                            |
| `type/security`      | `manifest.yaml`          | `manifest.yaml` + full evidence pack                        |
| `type/refactor` (safety) | (no requirement)     | `manifest.yaml` + `risk-file.yaml` excerpt                  |
| `type/chore`         | (no requirement)         | (no requirement)                                            |
| `type/docs`          | (no requirement)         | (no requirement)                                            |
| `type/test`          | (no requirement)         | (no requirement)                                            |

**"Safety-relevant" detection.** A `type/bug` or `type/refactor` issue is
considered safety-relevant when its "Where" section names any path matched
by a `paths:` glob in `compliance/iec-62304.md`, `compliance/iso-13485.md`,
or `compliance/iso-14971.md` (e.g. `risk-file/**`, `docs/risk-management/**`,
`tests/safety/**`, `src/medical/**`). This rule is the same one
`issue-create`'s `reference/regulated-fields.md` applies; the two
extensions share one definition so their behavior is consistent across the
issue and PR lifecycle.

**Per-cell artifact mapping.** When a cell requires `manifest.yaml`, the
PR must reference an `evidence/<version>/manifest.yaml` whose freshness
check passes (see "Within the last 24h" below). When it requires the
`risk-file.yaml` excerpt, the manifest must include an entry with
`kind: risk_file` and `status: collected` (per
`evidence-pack/reference/manifest-schema.md` "Allowed kind values"). When
it requires "test reports" or "regression test report", the manifest must
include `kind: ci_run_log` with `status: collected`. "Full evidence pack"
means every `kind` listed in the manifest schema is `collected` or
`skipped: source_absent` -- no `failed` entries are tolerated for
`type/security` PRs at `iso_class: A`.

## "Within the Last 24h" Definition

The 24-hour window is a freshness check on the manifest itself, not on the
underlying source artifacts the manifest references. The check is:

```
NOW_UTC - manifest._meta.generated  <  86400 seconds
```

Where `NOW_UTC` is the wall-clock UTC time at the moment Phase 9b runs.
The 86400-second budget is exact; a manifest generated 86399 seconds ago
passes, one generated 86401 seconds ago fails. Phase 9b uses
`date -u +%s` for `NOW_UTC` and parses the manifest's
`_meta.generated:` field (ISO 8601 UTC, second precision, `Z` suffix; see
`evidence-pack/reference/manifest-schema.md` "Timestamp Format").

**Why 24 hours.** A typical PR that survives review and CI for more than
a day has accumulated additional commits, additional risk-file edits, or
external test-report updates that the original manifest does not reflect.
Twenty-four hours is the operational cadence at which a Design History
File entry stays current without forcing a regeneration on every review
comment. Projects that need a tighter window can lower it via repository
configuration in a future iteration; the current implementation is fixed
at 24h.

**Remediation when stale.** Regenerate the manifest with
`/evidence-pack <version> --force` (see
`global/skills/_internal/evidence-pack/SKILL.md` Phase 0 -- the `--force`
flag is the documented way to overwrite an existing pack). The next push
or re-run of Phase 9b reads the fresh `_meta.generated` value and the
gate passes.

## Override Mechanism

The `pr-work` skill accepts `--skip-evidence-gate "<reason>"` to bypass
Phase 9b entirely. The flag exists for genuine emergencies -- a hotfix
that cleared a CI block where the audit trail will be backfilled in a
follow-up PR -- and is NOT a routine bypass. Default-mode runs without
the flag and the gate enforces the matrix above.

When the flag is set:

1. The skill posts a PR comment recording the bypass and the operator's
   reason. The comment is permanent (not deleted on subsequent runs) and
   serves as the audit trail entry for the bypass.
2. Phase 9b exits with status 0 immediately after posting the comment,
   without running checks (a) or (b).
3. The follow-up PR that backfills the audit trail must close a new
   issue and the gate runs normally on that PR.

The comment body uses the literal format below. Reviewers and external
auditors search for this exact string when reconstructing the audit trail
of a release.

```markdown
**Evidence-attachment gate bypassed via --skip-evidence-gate**

Reason: <verbatim operator-supplied string>
Operator: <gh actor login that ran pr-work>
Bypass timestamp: <UTC ISO 8601 timestamp>

This PR was merged without the manifest.yaml + linked-issue YAML block
checks Phase 9b normally enforces. A follow-up PR must backfill the
audit trail.
```

Operators must NOT use `--skip-evidence-gate` to silence a transient
freshness failure; the correct response in that case is to regenerate
the manifest. The bypass exists for cases where the operator has
already decided that the missing evidence will be supplied separately.

## Failure-Message Format

When a check fails, Phase 9b prints a structured message on stderr and
returns non-zero. The next push or manual re-run retries. The message
format is the same shape `evidence-pack` and `risk-control` use for
their own validation findings, so an operator reading multiple skill
outputs in a CI log sees consistent structure.

```
pr-work: Phase 9b -- evidence-attachment gate failed

  check       : (a) linked-issue YAML block | (b) manifest freshness
  rule        : <one-line rule from this document>
  pr_number   : <NNN>
  linked_issue: <#NNN | N/A>
  manifest    : <evidence/<version>/manifest.yaml | not referenced>
  generated   : <ISO 8601 timestamp | unparseable>
  age_seconds : <integer | not applicable>

Remediation:
  - For (a): run /issue-create on the linked issue with the regulated track,
    or edit the issue body to embed the YAML block per the six rules in
    issue-create/reference/regulated-fields.md "Embedded YAML block format".
  - For (b): regenerate via /evidence-pack <version> --force, then push.

To bypass (emergency only), re-run pr-work with --skip-evidence-gate "<reason>".
```

The `Remediation` section names the exact recovery commands so an operator
who has not memorized the regulated track can fix the gate without
re-reading three reference documents.

## Multi-Issue and Multi-Class PR Handling

When a PR closes more than one issue OR touches more than one SKILL.md,
the gate applies the strictest row of the matrix:

1. Determine the strictest issue type across all `Closes #N` keywords.
   Order: `type/security` > `type/feature` > `type/refactor` (safety) >
   `type/bug` (safety) > all others.
2. Determine the highest `iso_class` across all touched SKILL.md
   frontmatters. Order: `A` > `none` (the project does not yet ship `B`
   or `C`, so they are out of scope for this matrix).
3. Look up the cell. The cell's requirement applies to the entire PR.

Phase 9b prints which issue type and which class it selected so the
operator can audit the choice when the PR closes a heterogeneous set.

## Coordination with Phase 5b

Phase 5b (traceability impact injection) and Phase 9b (this gate) are
independent. Phase 5b runs on every push that introduces commits and
modifies the PR body; Phase 9b runs once per merge attempt and reads
the PR body and the linked-issue body. The two phases share `$PROJECT_ROOT`
and `$REGULATED_TRACK` from Phase 0a but otherwise do not interact:

| Property | Phase 5b | Phase 9b |
|----------|----------|----------|
| Trigger | After Step 8 (push) | Before Step 10 (auto-merge) |
| Reads | `git diff`, `docs/.index/graph.yaml`, `hooks/lib/validate-traceability.sh` | PR body, linked-issue bodies, `evidence/<version>/manifest.yaml` |
| Writes | PR body (between sentinel comments) | PR comment (only on `--skip-evidence-gate`) |
| Failure mode | Warn and continue (does not block) | Return non-zero (blocks merge) |
| Override | None (informational) | `--skip-evidence-gate "<reason>"` |

The two gate semantics are deliberate: Phase 5b is informational
documentation, Phase 9b is a merge-blocking enforcement. A PR can
legitimately have a stale or empty Phase 5b table while still passing
Phase 9b (the cascade is computed from the diff, the gate is computed
from the audit-trail metadata).

## Cross-references

- Issue-create extension that produces the YAML block Phase 9b reads:
  `../../issue-create/reference/regulated-fields.md` "Embedded YAML
  block format".
- Evidence-pack manifest schema referenced by the freshness check:
  `../../evidence-pack/reference/manifest-schema.md`.
- Risk-control schema that defines the `risk-file.yaml` shape an
  excerpt must conform to:
  `../../risk-control/reference/risk-record-schema.md`.
- Sister phase that injects the impact narrative:
  `traceability-impact-template.md`.
- Skill body that calls into this policy: `../SKILL.md` Phase 9b.
- ISO 14971 clauses on residual-risk acceptability and design-output
  verification that motivate the matrix:
  `compliance/iso-14971.md` (consumer project, when present).
