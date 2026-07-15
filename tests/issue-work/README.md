# issue-work triage tests

Unit tests for the issue-work triage state machine
(`global/skills/_internal/issue-work/scripts/triage.sh`). The suite shadows `gh`
with `fake-gh.sh`, so no network or GitHub auth is required.

## Run

```bash
bash tests/issue-work/test-triage.sh
```

The suite is wired into CI by `.github/workflows/validate-skills.yml`.

## Files

| File | Role |
|------|------|
| `test-triage.sh` | Test runner: pure-function unit tests + end-to-end scenarios. |
| `fake-gh.sh` | Canned `gh` for the subset of commands triage.sh calls; records mutations to `mutations.log` and appends posted comments so idempotency reruns observe prior state. |

## Acceptance-criteria coverage (issue #829)

| AC | Scenario | Assertion |
|----|----------|-----------|
| AC1 | Oversized issue, no children, plan supplied | `decomposed`; two children created; exactly one parent summary. |
| AC2 | Oversized parent with an eligible open child | `proceed` on the child; no children created; no decomposition comment. |
| AC3 | Documented, unchanged blocker | Rerun posts no additional comment (fingerprint match). |
| AC4 | Blocker set changed between runs | Exactly one updated comment. |
| AC5 | Blocker resolved between runs (new human info) | Fresh state re-read flips `blocked` -> `proceed`. |
| AC6 | Partial decomposition (one of two children exists) | Rerun creates only the missing child. |
| AC4b | Multi-blocker: first unchanged, a later blocker flips state | Exactly one updated comment (M1 fingerprint-leak regression). |
| AC7 | Claim race lost on the first child | Advances to the next eligible child, rolls back the speculative `@me` assignment (m4), and proceeds. |
| AC8 | Parent whose children are all closed | `skipped` with a completion-audit reason; no closed child is claimed. |
| AC9 | Blocked/decomposed outcomes | No assignment and no child/branch creation. |

## Verification matrix coverage

| Verification item | Scenario |
|-------------------|----------|
| Unchanged vs changed blocker, new human comment | AC3, AC4, AC5. |
| Existing children, partial decomposition | AC2, AC6. |
| Concurrent claim | AC7. |
| Cyclic parent/child relationship | `VER cycle` — visited guard terminates the traversal. |
| Max child traversal depth | `VER max-depth` — depth guard yields `failed`, never loops. |
| Three identical fetch failures | `VER m1` — retry helper stops with a `blocked` outcome (issue #829 risk control). |
| Batch reporting does not treat decomposition as a merge success | `VER batch reporting` — asserts the accounting guard in `reference/batch-mode.md` B-5. |

## Scope note

These are bash tests. PowerShell parity for the triage gate is deferred to issue
#832 (team/batch/cross-platform regression integration), per the epic #828 split.
