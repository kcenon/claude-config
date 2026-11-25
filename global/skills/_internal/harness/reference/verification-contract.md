# Verification Contract

Rules for any pipeline in which one party produces work and another checks it: Producer-Reviewer, Generator-Evaluator, a Supervisor that verifies its workers, and `fleet-orchestrator`.

A retry count limits how often a review loop runs. It does not say what may be checked again, so a loop can stay inside its count while the same evidence is confirmed over and over and the deliverable does not change. This contract limits what is verified, by whom, and when the loop must stop.

## Table of Contents

1. [Terms](#1-terms)
2. [Unit contract](#2-unit-contract)
3. [Evidence ledger](#3-evidence-ledger)
4. [Scope-matched checks](#4-scope-matched-checks)
5. [One orchestrator run per unit](#5-one-orchestrator-run-per-unit)
6. [Round budget](#6-round-budget)
7. [Severity scope](#7-severity-scope)
8. [Conflict rule](#8-conflict-rule)
9. [Stop signal](#9-stop-signal)
10. [Role guidance](#10-role-guidance)
11. [Brief templates](#11-brief-templates)
12. [What enforces this](#12-what-enforces-this)

---

## 1. Terms

| Term | Meaning |
|------|---------|
| Unit | One piece of work that is reviewed and committed as a whole. |
| Worker | The party that produces the unit. |
| Reviewer | The party that judges the unit. It does not produce it. |
| Orchestrator | The party that assigns units, sends them to review and decides what happens next. |
| Round | One brief sent to the reviewer and the verdict that comes back. |
| Tree state | The commit the work sits on plus a digest of the uncommitted changes. Two runs on the same tree state checked the same files. |
| Evidence | A recorded check result that names its command and its tree state. A result without both is a statement, not evidence. |
| Deliverable-level outcome | The reviewer's verdict together with the set of open blocker and major findings. It changes when the verdict changes or a blocker or major finding is closed or opened. |

## 2. Unit contract

The orchestrator writes this before the worker starts, and every brief for the unit quotes it. Severity (section 7) and conflicts (section 8) are judged against it, so a unit without one cannot be reviewed under this contract.

```markdown
## Unit contract: {unit-id}

**Deliverable:** {what exists when the unit is done}

**Invariants** (numbered; each one can be checked):
1. {invariant}
2. {invariant}

**Baseline:** {commit, tag or version that existing behaviour is compared with}

**Checks:** {the rows of the scope table in section 4 that apply to this unit}

**Known boundaries** (behaviour outside the contract, recorded and not fixed here):
- {none yet}
```

## 3. Evidence ledger

Every verification result is one ledger entry, kept at `_workspace/verification-ledger.md`. Whoever runs a check writes its entry: worker, orchestrator or reviewer.

```markdown
| # | Round | Claim | Command | Covers | Run by | Tree state | Result |
|---|-------|-------|---------|--------|--------|------------|--------|
| 1 | 0 | Unit tests pass | `{test command}` | `src/**`, `tests/**` | worker | `{commit}` + `{digest}` | pass, 412 tests |
| 2 | 0 | Docs build | `{docs command}` | `docs/**` | worker | `{commit}` + `{digest}` | pass |
```

`Covers` lists the paths whose content the check depends on. Round 0 is the work before the first review.

Take the tree state when the check starts, with these commands:

```bash
commit=$(git rev-parse HEAD)
digest=$({ git status --porcelain; git diff HEAD; git ls-files --others --exclude-standard -z | xargs -0 git hash-object; } | git hash-object --stdin)
```

The digest covers changed tracked files and untracked files, and is the same for two identical working trees.

**Rules:**

1. **A reported run is evidence.** When the worker reports a check with its command and tree state, the orchestrator compares the tree state with the current one. If they are equal, the result stands and the orchestrator does not run the check again. Who ran a check does not decide whether it counts.
2. **Re-run only on change.** A check may be run again only when a file under its `Covers` changed after the recorded tree state. Find out with `git diff --name-only {recorded commit}` plus the uncommitted files, matched against `Covers`.
3. **Skip and say so.** When no covered file changed, the check is skipped and the ledger gets a line that says so, naming the entry it relies on:

   ```markdown
   | 7 | 2 | Unit tests pass | (not re-run) | `src/**`, `tests/**` | orchestrator | `{commit}` + `{digest}` | relies on #1: no covered file changed |
   ```
4. **A statement is not evidence.** An entry without a command or without a tree state does not satisfy a check. The party that made it completes the entry or runs the check.
5. **The reviewer reads the ledger.** The reviewer is given the ledger and does not repeat an entry that stands. It runs a check only where its judgment needs a result the ledger does not hold.

## 4. Scope-matched checks

A check is required only when the change touches what the check covers. Each harness fills this table in once, with its own commands, and the unit contract names the rows that apply.

```markdown
| Change touches | Required checks | Not required |
|----------------|-----------------|--------------|
| Documentation only | {doc build or link check} | test suites, builds |
| One package or module | {that package's tests} | other packages' tests |
| A shared interface | {tests of the interface and of its consumers} | - |
| Build or dependency files | {full build}, {full suite} | - |
| Anything else | {full suite} | - |
```

A fix that follows a review round is a change like any other: it requires the checks of the rows it touches, not the checks of the whole unit.

## 5. One orchestrator run per unit

The orchestrator runs the unit's full check set once, immediately before the commit, on the tree state that is committed. That run is the unit's final evidence.

- Expensive checks (sanitizer builds, long suites, full builds) are run only there, unless a row of the scope table requires one earlier.
- Before that point the orchestrator relies on the ledger (section 3) and on scope-matched checks (section 4).
- If the final run fails, the failure is a finding for the worker. After the fix, the checks whose covered files changed are run again, and only those.

## 6. Round budget

Each unit gets **one full review and one narrow recheck**.

| Round | Brief | Scope |
|-------|-------|-------|
| 1 | First review (section 11) | The whole unit against its contract |
| 2 | Recheck (section 11) | Only the findings of round 1 and the decisions taken on them |

A third round is not the orchestrator's to start. It reports to the user with the open findings (section 9) and continues only on the user's decision.

## 7. Severity scope

The reviewer rates every finding with exactly one of three levels, and the brief gives it these definitions:

| Level | Definition | Effect |
|-------|------------|--------|
| Blocker | An invariant named in the unit contract is violated. | Must be fixed before the unit is committed. |
| Major | Behaviour that worked at the named baseline now fails. | Must be fixed before the unit is committed. |
| Minor | Everything else, including edge conditions the contract does not name. | Recorded under "Known boundaries" in the unit's documentation. Does not open a round and does not block the commit. |

A finding that cites neither a numbered invariant nor a baseline behaviour is minor, however serious it sounds. If such a finding ought to block, the contract is missing an invariant: the orchestrator decides whether to add one, records the reason, and treats that as a change of contract, not as a finding.

## 8. Conflict rule

When a finding contradicts a finding of an earlier round, or contradicts an accepted known boundary, the orchestrator stops iterating. It does not implement the newer finding and wait to see what breaks. It:

1. states the two requirements side by side and why both cannot hold,
2. decides which one wins, by the unit contract,
3. records the decision and its reason in the ledger, and moves the losing requirement to "Known boundaries",
4. states the decision in the next brief, so the reviewer does not raise the losing requirement again.

If the contract does not decide it, the question goes to the user.

## 9. Stop signal

If two consecutive rounds end without a change in the deliverable-level outcome, the orchestrator halts and reports to the user. This holds inside the round budget and in any further round the user allowed.

```markdown
## Verification halted: {unit-id}

**Reason:** {round budget used | two rounds without a change in outcome | conflict the contract does not decide}

**Rounds run:** {n}

**Open findings:**
| # | Level | Cites | Finding | Raised in round | Status |
|---|-------|-------|---------|-----------------|--------|

**Decisions taken:** {conflict decisions and contract changes, with reasons}

**Options:**
1. Accept the unit with the open findings recorded as known boundaries.
2. Allow one more round, limited to: {findings}.
3. Change the unit contract: {proposal}.
```

## 10. Role guidance

- The verifier role is one run in a fresh context. The orchestrator role holds the longest context and takes the most turns. The most capable and most expensive model therefore fits the verifier role better than the orchestrator role.
- An orchestrator that does run on such a model should run at medium effort: its work is routing and deciding, and the checks belong to the worker and the final run.
- Which model a user assigns to which role stays the user's choice. This section is guidance for a harness that has to pick.

## 11. Brief templates

Copy these as they are and fill in the braces.

### First review brief

```markdown
# Review: {unit-id}, round 1 of 2

## Unit contract
{the unit contract from section 2, in full}

## What changed
{diff range or file list}

## Evidence already recorded
{the ledger, in full}

These results stand for the tree state they name. Do not run them again. Run a check yourself only where your judgment needs a result the ledger does not hold, and add a ledger entry for it.

## What to judge
Whether the change satisfies each numbered invariant, and whether any behaviour that worked at the baseline now fails.

## How to rate
- Blocker: an invariant of the contract is violated. Cite its number.
- Major: behaviour that worked at {baseline} now fails. Cite the behaviour.
- Minor: everything else. Minor findings are recorded and do not block.

## What to return
- Verdict: AGREED or NOT AGREED. NOT AGREED requires at least one blocker or major finding.
- Findings: one row each with level, the invariant or baseline behaviour it cites, location, and the evidence for it.
```

### Recheck brief

```markdown
# Recheck: {unit-id}, round 2 of 2

## Unit contract
{the unit contract, in full, with any change marked}

## Findings of round 1 and what was done
| # | Level | Finding | Decision | Change made |
|---|-------|---------|----------|-------------|
| 1 | {level} | {finding} | {fixed / recorded as a known boundary / rejected: reason} | {files changed, or none} |

## Conflict decisions
{each decision taken under the conflict rule and its reason, or "none"}

## Evidence for the changes
{only the ledger entries added since round 1}

## What to judge
For each finding marked "fixed": is it resolved, and did the change made for it break an invariant or a baseline behaviour in the files that change touched?

## Limits
- Judge only the findings listed above and the files changed for them.
- A new finding is valid only if one of those changes caused it.
- Rate with the levels of round 1. A minor finding does not change the verdict.

## What to return
- Per finding: RESOLVED or NOT RESOLVED, with the evidence.
- Verdict: AGREED or NOT AGREED.
```

The recheck brief has no instruction to look again at anything that passed in round 1 and no instruction to try inputs or areas round 1 did not cover. Do not add either. A brief that asks for them turns the recheck into a second full review, and each round then finds one more edge case.

## 12. What enforces this

This contract is guidance. The orchestrator templates (`orchestrator-template.md`), the QA agent guide (`qa-agent-guide.md`) and `fleet-orchestrator` carry it into the harnesses they produce, and the brief templates above carry it to the reviewer. No hook reads the ledger or blocks a tool call because of it.

One thing is checked by machine: `tests/scripts/test-verification-contract.sh` fails when a harness reference mentions a review loop without linking to this file, or when this file loses one of its sections or brief templates.
