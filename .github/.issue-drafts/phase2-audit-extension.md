## What

Extend the existing `scripts/validate_skills.sh` (and `.ps1` sibling) to audit a new invariant: `global/CLAUDE.md` and `project/CLAUDE.md` must stay "routing-only" within a declared threshold. Wire the extended audit into `bootstrap.*` and `scripts/sync.*` so regressions are caught automatically.

Do not create a new audit script. The goal is to keep the tooling surface minimal.

## Why

Once the harness-layer phase-1 work lands (sibling sub-issue), `global/CLAUDE.md` will be routing-only. Without enforcement, prose will accumulate back over time — the same reason tier presets (#401) and `loop_safe` (#403) introduced frontmatter contracts: drift is detected only by manual review today.

`scripts/validate_skills.sh` already implements the validation plumbing (counters, colored output, pass/fail summary, 342 lines). Adding the CLAUDE.md check there reuses existing infrastructure rather than forking a parallel tool.

## Who

- Owner: @kcenon
- Reviewers: harness / skill-system maintainers

## When

phase-2 of the harness-optimization epic. Starts after phase-1 lands.

## Where

- `scripts/validate_skills.sh` (extend)
- `scripts/validate_skills.ps1` (extend, Windows parity)
- `bootstrap.sh`, `bootstrap.ps1` (call after install)
- `scripts/sync.sh`, `scripts/sync.ps1` (call after sync)
- `.github/workflows/` (add a job to an existing validate workflow, or extend `validate-hooks.yml`)
- `docs/TOKEN_OPTIMIZATION.md` (document the threshold and rationale)

## How

### Technical Approach

1. **Routing-only invariant** (new check function in `validate_skills.sh`):
   - Parse `global/CLAUDE.md` and `project/CLAUDE.md`.
   - Classify each non-blank line as `heading`, `routing` (bullet with a file path or `@load:` token), `invariant` (lines inside a marked always-on block), or `prose`.
   - Fail if `prose / (heading + routing + invariant)` exceeds a threshold (default 0.30, configurable via `AUDIT_PROSE_RATIO`).
   - Emit a structured report with line numbers of offending prose so a human can fix or reclassify.
2. **Skill frontmatter / body consistency** (extend existing checks):
   - If `max_iterations` or `halt_condition` declared in frontmatter, body must reference a loop or retry section.
   - If `loop_safe: false`, body must have a "Side effects" or equivalent section.
   - If `tiers:` declared, each tier's `ref_docs` keys must resolve to files under the skill's `reference/` directory.
3. **Wiring**:
   - `bootstrap.sh`/`.ps1`: call `validate_skills.sh` (no flag change needed; validation already runs today — just ensure new checks are included).
   - `scripts/sync.sh`/`.ps1`: run after sync, print remediation hints on failure.
   - CI: extend one existing workflow to run the script on PRs that touch `global/CLAUDE.md`, `global/skills/**`, or `rules/**`.
4. **Exit code contract**: preserve current exit-code meaning in `validate_skills.sh` (0 = pass, non-zero = fail). Threshold breaches should be fatal unless `AUDIT_SOFT=1`.

### Acceptance Criteria

- [ ] `scripts/validate_skills.sh` and `.ps1` gain the new checks without regressions on existing behavior.
- [ ] Exit 0 on a clean checkout of the repo after phase-1 lands.
- [ ] Manually injecting a 5-line prose block into `global/CLAUDE.md` triggers a non-zero exit with a readable report.
- [ ] Manually breaking a skill's `tiers.ref_docs` pointer triggers a non-zero exit.
- [ ] Bootstrap and sync both invoke the audit and surface failures.
- [ ] CI workflow runs the audit on path-matching PRs.
- [ ] `docs/TOKEN_OPTIMIZATION.md` documents the threshold and the reason.

### Non-goals

- Do not automate rewrites. The audit flags; a human edits.
- Do not build a second validator binary or script. One audit entry point only.

## Related

- Part of #439 (harness-optimization epic).
- Enforces invariants introduced by #401 (tier presets) and #403 (loop_safe flag).
- Related to #398 (skills layer), but checks harness + skill-body consistency.
