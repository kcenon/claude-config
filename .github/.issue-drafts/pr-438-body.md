Closes #438

## What

Extend `scripts/validate_skills.sh` with a routing-only audit for the three harness-layer `CLAUDE.md` files and with two frontmatter-vs-body drift checks for skills. Trigger the workflow on harness-file changes.

## Why

The phase-1 work (#437) slimmed `global/CLAUDE.md` to a routing index. Without enforcement, prose would drift back in — the same motivation that led to tier presets (#401) and `loop_safe` (#403) being declared as frontmatter contracts. This PR reuses the existing validator's plumbing rather than forking a new script.

## How

### 1. Routing-only audit (`validate_claude_md`)

For each audited file (`global/CLAUDE.md`, `project/CLAUDE.md`, `enterprise/CLAUDE.md`):

- Skip frontmatter (first `---` line breaks the scan — harness files do not use YAML frontmatter).
- Classify each non-blank, non-heading line:
  - Bullets (`-`, `*`, `+`), table rows (`|`), import directives (`@./`), blockquotes (`>`) -> routing
  - Any line inside a heading whose text matches `[Ii]nvariant` -> routing (invariant-equivalent)
  - Everything else -> prose
- Fail if `prose / (routing + prose) > AUDIT_PROSE_RATIO` (default `0.30`, overridable via env var).

Measurements on the current tree (post-#437):

| File | Prose | Routing/Invariant | Ratio |
|------|-------|-------------------|-------|
| `global/CLAUDE.md` | 2 | 11 | 15.4% |
| `project/CLAUDE.md` | 9 | 26 | 25.7% |
| `enterprise/CLAUDE.md` | 0 | 3 | 0.0% |

### 2. Frontmatter-vs-body drift (warnings, not fatal)

Inside `validate_skill()`, after existing checks:

- If frontmatter declares `max_iterations` or `halt_condition`, the body must mention `loop|retry|iteration|poll`.
- If frontmatter declares `loop_safe: false`, the body must contain a heading whose text matches side-effect / idempoten / loop-safety.

These are warnings, so incremental skill authoring is not blocked; CI reports the count.

### 3. CI triggering

`validate-skills.yml` now triggers on changes to `global/CLAUDE.md`, `project/CLAUDE.md`, and `enterprise/CLAUDE.md` in addition to the existing path set.

### 4. Documentation

`docs/TOKEN_OPTIMIZATION.md` gains a **Harness Routing Audit** section under the existing Tier Preset Impact content, covering classification table, threshold, current measurements, and the drift checks.

## Verification

- [x] Current tree passes: `bash scripts/validate_skills.sh` -> 222/222 passed, 12 warnings, exit 0.
- [x] Injected 5 prose lines into a test file -> audit reports `62.5% > 30%`, exit 1.
- [x] No changes to existing behavior: all previously passing checks still pass.
- [x] Warnings surfaced for skills that declare `max_iterations`/`halt_condition`/`loop_safe: false` without matching body references -> reviewer can address in follow-up PRs per skill.

## Scope boundaries

### Included
- `scripts/validate_skills.sh` bash extension (routing audit + drift checks)
- CI paths update
- `docs/TOKEN_OPTIMIZATION.md` documentation

### Deferred to phase-2b (will file follow-up)
- PowerShell parity (`scripts/validate_skills.ps1`) — parallel refactor, independent risk surface
- `bootstrap.*` / `scripts/sync.*` wiring — needs UX design: should install-time audit block or warn?
- `tiers.ref_docs` alias validation — currently documented only in comments; requires a machine-readable convention before enforcement

## Related

- Part of #439 (harness-optimization epic)
- Depends on #437 (already merged)
- Enforces invariants from #401 (tier presets), #403 (loop_safe)
