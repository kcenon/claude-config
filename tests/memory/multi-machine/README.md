# Multi-machine conflict scenario tests

Validates the cross-machine memory-sync system (issue #533) by simulating two
machines on a single host. Each scenario uses two clones of a synthetic bare
remote and exercises `scripts/memory-sync.sh` exactly the way it would run on
Machine A and Machine B.

## What this covers

| ID | Scenario | Issue body |
|----|----------|------------|
| S1 | Concurrent additions on different files | Scenario 1 |
| S2 | Concurrent edits on the same file (real conflict) | Scenario 2 |
| S3 | Validator-blocked propagation (secret bypass on A, B quarantines) | Scenario 3 |
| S4 | Network partition during sync, then recovery | Scenario 4 |
| S5 | Concurrent sync invocations on the same host | Scenario 5 |
| S6 | Clock skew tolerance across hosts | Extension |
| S7 | Concurrent quarantine agreement across hosts | Extension |

S6 and S7 are extensions covering edge behaviors implied by but not numbered in
the issue body: deterministic ordering under clock skew (issue task list,
scope-in) and convergent quarantine state when both hosts independently detect
the same bad ingress.

## What is deferred

The issue's authoritative scope-out lists "synthetic / mocked scenarios" --
i.e. the issue ALSO asks for an operator-driven run on two real machines that
produces a signed-off `audit/multi-machine-validation-YYYY-MM-DD.md`.

This harness does NOT replace that operator run; it provides:

- A fast, repeatable pre-flight that catches regressions in `memory-sync.sh`,
  `memory-notify.sh`, `quarantine-move.sh`, and `secret-check.sh` before the
  operator burns a real two-machine session on it.
- Documented expected behavior, asserted automatically, that the operator's
  signed-off report can reference as "what the harness already proved".

The following are explicitly DEFERRED to the operator run because they require
real two-host conditions:

- macOS terminal-notifier / Linux notify-send delivery proof
- Real network partition via `route` / `iptables` (this harness simulates the
  same exit-code 6 path via an unreachable `file://` remote)
- Genuine divergent system clocks at the kernel level (this harness simulates
  the property tested -- deterministic outcome regardless of commit timestamp
  -- via `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`)
- The signed-off audit report itself (operator deliverable; not generated here)

## Layout under `/tmp/mm-test-<pid>/<sid>/`

```
bare.git/             bare repo simulating origin (kcenon/claude-memory)
seed/                 throwaway clone used to seed bare with initial state
host-A/               clone representing Machine A
host-B/               clone representing Machine B
host-A.log host-B.log per-host memory-sync.log
host-A.lock host-B.lock per-host lock files
```

The harness never touches the user's real `~/.claude/` directory: every
`memory-sync.sh` invocation passes `--clone-dir`, `--log-file`, `--lock-file`
pointing inside the sandbox, and `trap 'rm -rf "$TEST_TMP_BASE"' EXIT`
cleans the sandbox unconditionally.

## Running

```bash
# From repo root
bash tests/memory/multi-machine/run-multi-machine-tests.sh
```

Expected output ends with `Summary: N pass, 0 fail`. Total runtime is well
under one minute on commodity hardware (the only sleep is the 3-second lock
holder used by S5 to ensure lock contention is observable).

## Exit codes asserted

The harness verifies the contract documented in the head of `memory-sync.sh`:

| Code | Scenario asserting it |
|------|----------------------|
| 0    | S1, S4 (after recovery), S5 (after release), S6, all clean paths |
| 2    | S3, S7 (post-pull validator detected bad ingress) |
| 3    | S2 (rebase conflict aborted) |
| 5    | S5 (lock contention) |
| 6    | S4 (fetch failed during partition) |

## Cross-references

- `scripts/memory-sync.sh` -- system under test (#520)
- `scripts/memory-notify.sh` -- alerting channel referenced by sync (#524)
- `scripts/memory/secret-check.sh` -- pre-push and post-pull secret detector
- `scripts/memory/quarantine-move.sh` -- quarantine routing (#514)
- `tests/memory/run-sync-tests.sh` -- single-host sync regressions (companion)
- `docs/THREAT_MODEL.md` -- defines what counts as a "conflict" in this system
- Issue #533 -- requirements; body is authoritative for scope
