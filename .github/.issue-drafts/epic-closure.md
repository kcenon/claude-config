## Epic closure

All three sub-issues merged. Closing with a final acceptance-criteria audit so the deferred items have a recorded decision.

### Acceptance criteria status

| AC | Status | Evidence |
|----|--------|----------|
| `global/CLAUDE.md` body <= 30 lines; invariants block <= 12 lines | Met | Body 27 lines, invariants 7 lines (#437 / #440) |
| Every removed paragraph has a verified equivalent elsewhere | Met | Verification table in #440 PR description |
| Extended audit runs in a CI workflow; regressions fail the audit | Met | `validate-skills.yml` triggered on harness files, `validate_skills.sh`/`.ps1` enforce default 30% prose ratio (#441 / #443) |
| `docs/TOKEN_OPTIMIZATION.md` captures before/after token counts and threshold knobs | Met | New **Harness Routing Audit** section (#441) |
| Phase-3 explicitly deferred, merged, or withdrawn with reason recorded | **Withdrawn** — see below |

### Intentional non-goals (final decisions)

- **Bootstrap / sync wiring**: Not pursued. Rationale recorded during phase-2a: adding the audit to install-time (`bootstrap.*`) or sync (`scripts/sync.*`) flows risks failing existing user configs and degrading install UX. CI already enforces the invariant on PRs. If local enforcement is later desired, prefer a warn-only `sync.*` hook over install-time blocking.
- **`tiers.ref_docs` alias validation**: Not pursued. Current aliases (`core`, `advanced`) are documented in YAML comments only (`# core -> reference/error-handling.md`). Machine-readable enforcement requires either a convention (alias equals file basename) or an explicit `ref_docs_aliases:` mapping. Designing that convention is a separate decision, not blocked by anything delivered here.
- **Phase-3 self-improvement skill**: Withdrawn. The original deferral said "until phase-1/2 validate the patterns." Both patterns now validated; however, no telemetry or user-reported pain point exists that would justify a dedicated meta-skill. File a new issue if a concrete need emerges.

### Delivered impact

- `global/CLAUDE.md` file size: 7,230 -> 1,087 bytes (-85%)
- `global/CLAUDE.md` line count: 70 -> 31 (-56%)
- Harness routing discipline enforced by CI on every PR touching the three harness files
- Drift warnings surface the 12 skills that declare `max_iterations` / `halt_condition` / `loop_safe: false` without matching body references — actionable backlog if anyone wants to address them

### Complements

- #398 (skills layer) remains the sibling epic at a different layer. Progress there is independent.

Closing this epic.
