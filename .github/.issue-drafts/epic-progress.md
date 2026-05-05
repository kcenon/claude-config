## Progress update

Both planned sub-issues merged into develop:

| PR | Issue | What landed |
|----|-------|-------------|
| #440 | #437 (phase-1) | `global/CLAUDE.md` body trimmed from 70 to 27 lines; always-on invariants block of 7 lines; no information lost (removed paragraphs traced to existing files in the PR body verification table) |
| #441 | #438 (phase-2a) | `validate_skills.sh` gains a routing-only audit on the three harness files (default 30% prose-ratio threshold, env-overridable) + frontmatter-vs-body drift warnings for skills declaring `max_iterations`/`halt_condition`/`loop_safe: false`. CI `validate-skills.yml` triggers on harness-file changes. Current state: `global` 15.4% / `project` 25.7% / `enterprise` 0.0% — all under threshold |

Token impact measurement (session-start cost of `global/CLAUDE.md`):
- File size: 7,230 -> 1,087 bytes (-85%)
- Line count: 70 -> 31 (-56%)

## Remaining acceptance criteria

The epic AC still lists items that are not yet delivered:

- **PowerShell parity for the audit**: `scripts/validate_skills.ps1` has not been updated. Blocking factor: unit-test parity across the two shells.
- **Bootstrap / sync wiring**: intentionally skipped — adding the audit to install-time or sync flows may fail existing user configs and degrade install UX. Better surfaced as CI-only unless users ask for stricter local enforcement.
- **Tiers alias validation**: `tiers.ref_docs` keys are currently documented in YAML comments only (e.g. `core -> reference/error-handling.md`). Machine-readable validation requires a convention (either alias = filename basename, or an explicit `ref_docs_aliases:` mapping). Designing this convention is a separate decision.
- **Phase-3 self-improvement skill**: originally deferred until phase-1/2 validated the patterns. Both patterns now validated; decision on whether to file phase-3 is owner's call.

## Suggested next step

File a phase-2b issue that groups the three remaining items as a single scope, or close this epic and file them as independent issues if priorities differ.
