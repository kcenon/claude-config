---
title: "test(memory): multi-machine conflict scenario validation"
labels:
  - type/test
  - priority/medium
  - area/memory
  - size/M
  - phase/G-rollout
milestone: memory-sync-v1-multi
blocked_by: [G1]
blocks: [G3]
parent_epic: EPIC
---

## What

Execute documented multi-machine conflict scenarios on two real machines and confirm system behavior matches design. Test scenarios cover concurrent additions, edits, validation failures, secret-detection, and network partitions. Output: signed-off scenario log committed to `audit/multi-machine-validation-YYYY-MM-DD.md`.

### Scope (in)

- 5 documented scenarios run end-to-end
- Use 2 real machines (primary + second from #G1)
- Each scenario: setup → trigger → observe → record outcome
- Match observed behavior against expected from design
- Final report committed to claude-memory `audit/`

### Scope (out)

- Synthetic / mocked scenarios — must be real machines
- Stress / load testing
- Performance benchmarking under concurrency
- Adversarial security testing (separate threat-model focus, #G3)

## Why

Documented design + integration tests (#A5) only prove the *individual components* work. They don't prove the **emergent behavior** of two machines interacting in real conditions. Multi-machine scenarios reveal:

- Race conditions between two `memory-sync.sh` invocations
- Whether validation correctly blocks bad data from propagating
- Whether quarantine on one machine surfaces correctly on the other
- Whether conflict notifications reach the user before the other machine syncs

Without this validation, the system might silently mishandle real-world race conditions and the user only finds out when memory data is already corrupted or lost.

### What this unblocks

- #G3 — operational docs reference scenario test results as validation evidence
- General confidence that the system is production-ready

## Who

- **Tester**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium
- **Estimate**: 1 day (mostly waiting for sync intervals between scenarios)
- **Target close**: within 1 week of #G1 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Test environment**: 2 real machines (primary + #G1's onboarded second)
- **Output**: `kcenon/claude-memory/audit/multi-machine-validation-YYYY-MM-DD.md`

## How

### Approach

For each scenario, define exact commands to run on each machine, expected behavior, and observation method. Execute serially (don't run scenarios in parallel — too easy to confuse cause and effect). Record actual behavior side-by-side with expected.

### Detailed Design

**Scenario 1 — Concurrent additions, different files**

Setup: clean state on both machines.

Action:
- Machine A: write `memories/feedback_test_a.md`, sync
- Machine B (within 30 seconds): write `memories/feedback_test_b.md`, sync

Expected:
- Both files appear in `memories/` on both machines after both syncs complete
- No conflict
- Auto-merge succeeds

Observation:
- `git log --all --oneline -5` on both → both commits present in linear order
- Verify file presence on both

Pass criteria: both files visible on both machines, no conflict reported.

---

**Scenario 2 — Concurrent edits, same file (real conflict)**

Setup: `memories/feedback_test_shared.md` exists on both machines, identical content.

Action:
- Machine A: edit `feedback_test_shared.md` adding "rule A", sync
- Machine B (BEFORE A's sync completes): edit same file adding "rule B", sync

Expected:
- One machine's sync succeeds (whichever pushed first)
- Other machine's sync detects conflict during rebase
- Other machine's `memory-sync.sh` exits 3, fires critical-severity notification (#D5)
- Other machine's `~/.claude/logs/memory-sync.log` shows ABORT entry
- Manual resolution required on the second machine

Observation:
- Notification appears
- Log shows ABORT
- Both machines' content remains in their respective working trees until resolution

Pass criteria: conflict detected, notification fires, no silent data loss, manual resolution path documented and works.

---

**Scenario 3 — Bad memory pushed (validation bypass on one machine)**

Setup: Pre-commit hook (#C3) intentionally bypassed via `--no-verify` on Machine A to push a memory containing a synthetic secret.

Action:
- Machine A: write memory with secret, `git commit --no-verify`, push directly to remote
- Machine B (within sync interval): runs `memory-sync.sh` which pulls the bad commit

Expected:
- Machine B's post-pull validation (#D1 stage 7) detects secret
- Machine B auto-quarantines the offending file via #B4
- Machine B commits the quarantine action and pushes
- Machine A's next sync pulls the quarantine action (its own bad memory now in quarantine/)
- User notified on both machines (warning level)

Observation:
- File present in `quarantine/` on both machines
- Frontmatter shows `quarantined-at`, `quarantine-reason`, `quarantined-by`
- Notification log contains the alert

Pass criteria: bad data isolated within minutes, no machine acts on the secret, both machines reach consistent state.

**Important**: also verify GitHub Actions (#C5) caught it server-side (workflow status red). The quarantine on Machine B is the recovery; CI's reject is the prevention layer that caught it before the next merge.

---

**Scenario 4 — Network partition during sync**

Setup: Machine A has 3 unpushed commits; turn off network during `memory-sync.sh` execution.

Action:
- Machine A: simulate via `sudo route add -host github.com 127.0.0.1` (or `iptables` on Linux)
- Run `memory-sync.sh`
- Wait for failure
- Restore network: `sudo route delete -host github.com`
- Re-run `memory-sync.sh`

Expected:
- First run fails at stage `fetch_remote` with exit 6
- Lock released cleanly
- Notification fires (warn-level)
- Subsequent run with restored network succeeds, pushes all 3 commits

Observation:
- First run log shows fetch failure
- Lock file gone after script exits (not stale)
- Second run succeeds normally
- All 3 commits arrive on Machine B

Pass criteria: clean recovery; no orphan locks; data integrity preserved.

---

**Scenario 5 — Concurrent sync invocations on same machine**

Setup: Machine A runs `memory-sync.sh` twice nearly simultaneously (e.g., manual + scheduled).

Action:
- Machine A: open two terminals, run `memory-sync.sh` in both within 1 second

Expected:
- One acquires lock, proceeds
- Other detects lock contention, exits 5 silently (no spam)
- After first completes, repeat manually → succeeds
- No corruption from concurrent writes

Observation:
- One process exits 5
- Repository state consistent

Pass criteria: lock works as designed; no race condition.

---

**Report format** (`audit/multi-machine-validation-YYYY-MM-DD.md`):

```markdown
# Multi-machine validation — 2026-MM-DD

Tester: @kcenon
Machines used: macbook-pro (primary), mac-mini-home (second)

## Scenario 1 — Concurrent additions

Status: PASS / FAIL
Setup: ...
Action: ...
Expected: ...
Observed: ...
Notes: ...

## Scenario 2 — Concurrent edits ...

(repeat for all 5)

## Summary

| # | Scenario | Status |
|---|---|---|
| 1 | Concurrent additions | PASS |
| 2 | Concurrent edits | PASS |
| 3 | Bad memory bypass | PASS |
| 4 | Network partition | PASS |
| 5 | Concurrent sync local | PASS |

## Recommended actions

- (any improvements identified during testing)

## Sign-off

- @kcenon: 2026-MM-DD
```

### Inputs and Outputs

**Input**: 2 onboarded machines per #G1.

**Output**: signed-off report committed to `audit/multi-machine-validation-YYYY-MM-DD.md`.

### Edge Cases

- **Scenarios run out of order** → don't; serial execution prevents confusion
- **Test memory files clutter `memories/`** → cleanup at end of each scenario via quarantine or git revert
- **Scenario 3 requires temporarily granting --no-verify allowance** → document the bypass; remove after test
- **Network simulation differs across OS** → use OS-appropriate command (route on macOS, iptables on Linux)
- **Two machines clock-skewed** → pinpoint via `date -u` snapshot before each scenario; rule out as cause if results unexpected
- **Machine reboots mid-test** → not a scenario in v1; note as future consideration
- **Test takes longer than 1 day** (waiting for sync intervals) → scenarios use manual `memory-sync.sh` invocation rather than waiting for scheduled runs; reduces wall time

### Acceptance Criteria

- [ ] All 5 scenarios executed end-to-end on real machines
- [ ] Each scenario's "Status: PASS" requires both machines to reach the expected end state
- [ ] **Scenario 1 PASS**: both machines have both files post-sync
- [ ] **Scenario 2 PASS**: conflict detected, notification fires, no silent data loss
- [ ] **Scenario 3 PASS**: secret-bearing memory auto-quarantined; CI also rejected
- [ ] **Scenario 4 PASS**: clean recovery from network failure; lock released; data preserved
- [ ] **Scenario 5 PASS**: concurrent invocations serialized; no corruption
- [ ] Report committed to `audit/multi-machine-validation-YYYY-MM-DD.md`
- [ ] Test memory files cleaned up post-test
- [ ] If any scenario fails: file follow-up issue; do NOT close this issue until all 5 PASS

### Test Plan

The tests ARE this issue's deliverable. Beyond execution, the test plan is:
- Reproduce each scenario at least once
- Document the exact commands used (in the report)
- If a scenario fails on first run, fix the underlying issue and re-run before declaring PASS

### Implementation Notes

- Use **manual `memory-sync.sh` invocations** rather than waiting for hourly scheduler — much faster
- For Scenario 2, the timing trick is to start B's sync **before** A's push completes; you can simulate by adding a sleep in A's `memory-sync.sh` (`sleep 10` after pre-push validation)
- For Scenario 3, the bypass uses `git commit --no-verify` and direct `git push` — clearly mark this as a test maneuver in commit messages
- For Scenario 4, network simulation: macOS `sudo route add -host github.com 127.0.0.1` then `route delete`; Linux `sudo iptables -A OUTPUT -d github.com -j DROP` then `iptables -D OUTPUT -d github.com -j DROP`
- After each scenario, manually verify clean state before next: `gh pr list`, `gh issue list`, both machines' `memory-status.sh`
- Don't be afraid to extend scenarios if mid-test you observe an unexpected behavior worth investigating — note in report

### Deliverable

- `audit/multi-machine-validation-YYYY-MM-DD.md` committed
- PR linked to this issue
- @kcenon's sign-off in the report

### Breaking Changes

None — testing only.

### Rollback Plan

Test memory files cleaned up post-scenario. No persistent change.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #G1
- Blocks: #G3
- Related: every component issue (#A2 through #F4) — this is the integration test for all of them

**Docs**:
- `docs/MEMORY_SYNC.md`
- `docs/THREAT_MODEL.md` (#G3) — scenarios validate threat-mitigation claims

**Commits/PRs**: (filled at PR time)
