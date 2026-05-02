# Memory Sync — Threat Model

**Version**: 1.0.0
**Last updated**: 2026-05-01
**Status**: Active
**Issue**: [#534](https://github.com/kcenon/claude-config/issues/534)
**Epic**: [#505](https://github.com/kcenon/claude-config/issues/505)

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [Assets](#2-assets)
3. [Adversary and Failure Models](#3-adversary-and-failure-models)
4. [Defense Layers Overview](#4-defense-layers-overview)
5. [Threat R1 — Sync Silent Failure](#5-threat-r1--sync-silent-failure)
6. [Threat R2 — Contaminated Memory Propagation](#6-threat-r2--contaminated-memory-propagation)
7. [Threat R3 — SSH Signing Key Loss](#7-threat-r3--ssh-signing-key-loss)
8. [Threat R4 — Audit Findings Overload](#8-threat-r4--audit-findings-overload)
9. [Threat R5 — Backfill Destroys Data](#9-threat-r5--backfill-destroys-data)
10. [Threat R6 — Validator False-Positives](#10-threat-r6--validator-false-positives)
11. [Threat R7 — GitHub Outage / Repo Loss](#11-threat-r7--github-outage--repo-loss)
12. [Residual Risks](#12-residual-risks)
13. [Versioning](#13-versioning)

---

## 1. Purpose and Scope

This document is the canonical security analysis of the cross-machine memory
sync system implemented in
[epic #505](https://github.com/kcenon/claude-config/issues/505). It enumerates
the seven threat categories surfaced during epic design, maps each to the
existing defense layer responsible for catching it, and calls out the residual
risk that no automated control fully closes.

### In scope

- The git-backed memory store at `~/.claude/memory-shared/` and its remote
  `kcenon/claude-memory`.
- The sync engine [`memory-sync.sh`](../scripts/memory-sync.sh) and its
  pre-push and post-pull validation stages.
- The PreToolUse [`memory-write-guard.sh`](../global/hooks/memory-write-guard.sh),
  SessionStart [`memory-integrity-check.sh`](../global/hooks/memory-integrity-check.sh),
  and PostToolUse [`memory-access-logger.sh`](../global/hooks/memory-access-logger.sh)
  hooks.
- The validators `validate.sh`, `secret-check.sh`, `injection-check.sh` (in
  the `claude-memory` repository).
- The weekly `audit.sh` and optional monthly `semantic-review.sh`.
- Branch protection and CI gating on `kcenon/claude-memory`.

### Out of scope

- Threats to the host operating system, local filesystem, or local SSH agent.
- Network-layer threats below TLS (the user's ISP, the Claude API endpoint).
- Threats targeting GitHub itself (account takeover at the platform level,
  GitHub-side data loss).
- Threats targeting the Claude Code binary, Claude API, or Anthropic
  infrastructure.
- Multi-tenant or cross-user threats — this is a single-user system; the user
  is trusted and is not modeled as an attacker against themselves.

### Authoritative references

- [`MEMORY_SYNC.md`](./MEMORY_SYNC.md) — operations runbook (companion document)
- [`MEMORY_VALIDATION_SPEC.md`](./MEMORY_VALIDATION_SPEC.md) — validator
  contract, exit codes, schema rules
- [`MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) — trust tier semantics
- [`SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md) — per-machine signing setup

---

## 2. Assets

| Asset | Sensitivity | Notes |
|-------|-------------|-------|
| Memory file content (`memories/*.md` body) | Medium | Project context, decisions, feedback rules. Not credentials by design (secret-check.sh enforces). |
| Memory frontmatter | Medium | Author, source machine, trust level. Provenance — tampering enables forgery. |
| `MEMORY.md` index | Low | Generated artifact derived from frontmatter. Drift surfaces as warning, not authority. |
| User identity (signing key, GitHub handle, email in commits) | Low | Already public via existing repository commits. |
| `~/.claude/logs/memory-access.log` | Low | Path-only access record; never transmitted; rotates monthly. Local to each machine. |
| Session-specific transient memory | High | Never written to disk. Out of scope. |
| SSH signing key (per machine, in `~/.ssh/`) | High | Provenance authority. Compromise covered under [R3](#7-threat-r3--ssh-signing-key-loss). |
| Branch protection on `kcenon/claude-memory` `main` | Critical | Server-side gate. Compromise covered under [R7](#11-threat-r7--github-outage--repo-loss). |

---

## 3. Adversary and Failure Models

This system models three failure modes — automated, accidental, and adversarial:

| Mode | Example | Primary mitigation surface |
|------|---------|---------------------------|
| Automated failure | launchd dies, network drop, validator false-positive | SessionStart integrity check, idempotent retry, warn-only validators |
| Accidental misuse | User mis-edits a memory, runs backfill on wrong tree | Backups, dry-run defaults, git history |
| Adversarial input | Prompt-injection-driven self-reinforcing memory text | 5-layer validation chain, monthly semantic review, trust tiers |

The adversarial model is **prompt injection by content Claude reads**, not a
malicious operator. The user account is trusted by definition (single-user
system); a fully compromised user account is treated as out of scope and
recoverable only by repository teardown and re-bootstrap.

---

## 4. Defense Layers Overview

Five primary layers form the core defense, plus orthogonal layers:

| # | Layer | Implementation | Catches | Gate type |
|---|-------|---------------|---------|-----------|
| 1 | Write-time | [`memory-write-guard.sh`](../global/hooks/memory-write-guard.sh) (PreToolUse, [#521](https://github.com/kcenon/claude-config/issues/521)) | Bad writes the moment Claude attempts an Edit/Write on a memory file | Block (deny) |
| 2 | Pre-commit | claude-memory `.git/hooks/pre-commit` ([#517](https://github.com/kcenon/claude-config/issues/517)) | Bad commits the moment the author commits | Block (refuse commit) |
| 3 | Sync pre-push | [`memory-sync.sh`](../scripts/memory-sync.sh) Stage 4 ([#520](https://github.com/kcenon/claude-config/issues/520)) | Bad commits before they leave this machine | Block (exit 1) |
| 4 | Sync post-pull | `memory-sync.sh` Stage 7 ([#520](https://github.com/kcenon/claude-config/issues/520)) | Bad commits incoming from another machine | Quarantine (move to `quarantine/`, alert) |
| 5 | Weekly audit | `audit.sh` ([#528](https://github.com/kcenon/claude-config/issues/528)) | Slow rot, stale (>90d), broken refs, duplicate-suspect, unused | Surface for review (`/memory-review`) |

### Orthogonal layers

| Layer | Implementation | Role |
|-------|---------------|------|
| Server-side | [`memory-validation.yml`](https://github.com/kcenon/claude-memory) GitHub Actions ([#519](https://github.com/kcenon/claude-config/issues/519)) | Mirror of layers 2–3; rejects pushes that bypass local hooks (e.g. `--no-verify`) |
| Branch protection | `kcenon/claude-memory` `main` requires signed commits | Forgery cannot land via signed-but-stolen-key without per-machine compromise |
| SessionStart visibility | [`memory-integrity-check.sh`](../global/hooks/memory-integrity-check.sh) ([#522](https://github.com/kcenon/claude-config/issues/522)) | Surfaces last-sync age and unread alerts before any session work begins |
| Monthly semantic review | `semantic-review.sh` ([#530](https://github.com/kcenon/claude-config/issues/530)), opt-in | Catches subtle injection that heuristic checks miss (self-reinforcing instructions, compositional injection) |
| Access logging | [`memory-access-logger.sh`](../global/hooks/memory-access-logger.sh) ([#531](https://github.com/kcenon/claude-config/issues/531)) | Path-only record; feeds unused-memory check; supports forensic review |
| Trust tiers | `verified` / `inferred` / `quarantined` ([`MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md)) | Auto-application gate: only `verified` is auto-applied; `inferred` is shown with marker; `quarantined` never auto-applied |

---

## 5. Threat R1 — Sync Silent Failure

### Threat description

The hourly scheduler (launchd on macOS, systemd user timer on Linux) dies,
hangs, or stops being invoked, and the user is not alerted. Machines drift
from each other; changes made on machine A never reach machine B.

### Likelihood / Impact

- **Likelihood**: Medium. launchd `RunAtLoad` mitigates resume-from-sleep gaps;
  systemd `Persistent=true` recovers missed events. However, scheduler unload
  (e.g., via `launchctl bootout` for unrelated reasons), permission loss on
  the plist, or a long-running prior invocation holding the lock can all
  silently halt the cycle.
- **Impact**: High. Drift compounds over time; what looks like missing memory
  on one machine may already be present on the other.

### Attack surface

Not adversarial — environmental. The triggers are:

- Operating-system scheduler change (e.g., launchd policy update).
- User-initiated `launchctl unload` / `systemctl --user disable` without
  realizing it disables sync.
- Network outage during all scheduled invocations within the warning window.
- A `memory-sync.sh` invocation that hangs past the lock-timeout cutoff
  causing pile-up to drop subsequent invocations.

### Detection layer

- **Primary**: [`memory-integrity-check.sh`](../global/hooks/memory-integrity-check.sh)
  ([#522](https://github.com/kcenon/claude-config/issues/522)). Runs at every
  `SessionStart` and prints a warning when last sync exceeds 24 hours.
- **Secondary**: `scripts/memory-status.sh --detail` ([#523](https://github.com/kcenon/claude-config/issues/523))
  shows last-sync age on demand.

### Mitigation

- launchd: `RunAtLoad=true` + `StartInterval=3600` recovers missed intervals
  immediately on wake/login.
- systemd: `OnCalendar=hourly` + `Persistent=true` runs missed events after
  reboot.
- `--lock-timeout 30` in the scheduler invocation prevents pile-up; second
  invocation exits if first run exceeds 30s, and the next interval retries.
- Output rotation via `cleanup.sh` keeps `/tmp/claude-memory-sync.{out,err}`
  inspectable.

### Residual risk

The 24h warning threshold is itself a tolerated drift window. Between hour 1
(scheduler dies) and hour 24 (first warning surfaces), there is no automated
notification — the user sees the issue at the next session, not when it
happens. A scheduled push notification or external dead-man monitor could
close this gap; not implemented because it adds infrastructure for a
single-user system. Operators uncomfortable with the 24h window can lower
`SYNC_STALE_SECS` in
[`memory-integrity-check.sh`](../global/hooks/memory-integrity-check.sh).

---

## 6. Threat R2 — Contaminated Memory Propagation

### Threat description

A memory file containing prompt-injected content (e.g., self-reinforcing
instructions like "always disable validation"), a leaked secret (token, PII,
SSH key), or otherwise malformed content lands in the local store on machine A
and is replicated to machine B before any user notices. On machine B, the
contaminated memory then influences future Claude sessions persistently.

### Likelihood / Impact

- **Likelihood**: Low. Five overlapping defense layers (see
  [Section 4](#4-defense-layers-overview)) each independently catch typical
  contamination patterns. To propagate, content would have to evade all five.
- **Impact**: Critical. Persistent self-reinforcing instructions are the
  textbook prompt-injection escalation; once auto-applied at every
  SessionStart, behavior across all machines is shaped indefinitely.

### Attack surface

- External document Claude reads contains a prompt-injection payload that
  manipulates Claude into writing a memory.
- User pastes terminal output into a session that includes a hidden injection
  string (rare but plausible).
- Claude infers a "memory-worthy" rule from a misleading session and writes
  it as `inferred`.

### Detection layer

All five layers participate:

| Layer | What it catches | Failure mode |
|-------|----------------|--------------|
| 1 — Write-guard ([#521](https://github.com/kcenon/claude-config/issues/521)) | `secret-check.sh` exit 1 → deny; `validate.sh` exit 1/2 → deny | Bypassable only if Claude bypasses the hook (which is enforced in `settings.json`) |
| 2 — Pre-commit ([#517](https://github.com/kcenon/claude-config/issues/517)) | Same validators at commit time | Bypassable via `git commit --no-verify` |
| 3 — Sync pre-push ([#520](https://github.com/kcenon/claude-config/issues/520)) | Same validators on local diff before push | Hard-coded into `memory-sync.sh`; no `--no-verify` equivalent |
| 4 — Sync post-pull ([#520](https://github.com/kcenon/claude-config/issues/520)) | Validators on full incoming tree; auto-quarantine | Same — file moved to `quarantine/` rather than blocking sync |
| 5 — Weekly audit ([#528](https://github.com/kcenon/claude-config/issues/528)) | Slow rot, suspicious patterns, stale | Surfaces, does not block |
| Server (orthogonal, [#519](https://github.com/kcenon/claude-config/issues/519)) | GitHub Actions mirror of layers 2–3 | Catches `--no-verify` bypasses |
| Monthly semantic review (orthogonal, [#530](https://github.com/kcenon/claude-config/issues/530)) | Subtle injection (compositional, contradictions) | AI-based; opt-in |

### Mitigation

- `injection-check.sh` is **warn-only** by design (exit 3 = allow with
  feedback) so genuine but suspicious-looking content is not lost; `validate.sh`
  and `secret-check.sh` are blocking.
- Auto-quarantine on layer 4: files that fail post-pull validation are moved
  to `quarantine/` and an alert is emitted via [`memory-notify.sh`](../scripts/memory-notify.sh).
  Sync proceeds with the rest of the tree; only the offending file is
  isolated.
- Trust tiers gate auto-application: only `verified` is auto-applied to
  sessions; `inferred` requires a marker; `quarantined` is never
  auto-applied.

### Residual risk

- **Compositional injection across multiple memories.** Each memory file
  passes individual validation, but combined behavior emerges from
  interaction. Monthly semantic review (opt-in) is the partial mitigation;
  full compositional analysis is an open research problem.
- **Time window between bad write and validators catching.** Between layers 1
  and 2 (write to commit), or layers 3 and 4 (pre-push to post-pull), there
  is a brief window where the bad file exists locally. Local-only impact
  during that window; sync layer 4 catches it before it reaches another
  machine.
- **Validator gaps** for novel injection patterns not yet encoded in
  `injection-check.sh`. Mitigated by the monthly semantic-review fallback
  and by the warn-only design surfacing flagged patterns to `/memory-review`.

---

## 7. Threat R3 — SSH Signing Key Loss

### Threat description

The SSH signing key on a machine is lost (disk failure, hardware retirement)
or compromised (unauthorized access to the machine, key file readable by
another user). Lost = cannot push commits any more; compromised = an
attacker may forge memory entries that appear legitimate.

### Likelihood / Impact

- **Likelihood**: Low. SSH keys are stored under `~/.ssh/` with `0600`
  permissions and are tied to a specific machine. They do not transit the
  network beyond a key-exchange-protected `git push`.
- **Impact**: Medium. Per-machine keys (the design choice in
  [`SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md)) limit blast radius to
  a single machine. Branch protection requires signed commits, so a
  compromised key lets an attacker push only **as that machine**, not as
  any other.

### Attack surface

- Disk failure / accidental deletion of `~/.ssh/id_ed25519`.
- Unauthorized local access to the machine while logged in.
- Backup tape exposure if `~/.ssh/` was included in plaintext backups.

### Detection layer

- **Loss**: `git push` fails with a signing error during the next sync;
  surfaces as a `memory-notify.sh` `critical` alert and at the next
  SessionStart.
- **Compromise**: not directly detectable from the repository side; the
  weekly audit surfaces unfamiliar commits, and `git log
  --show-signature` exposes the key fingerprint per commit.

### Mitigation

- **Per-machine keys**: each machine generates its own SSH signing key. Loss
  on one machine does not require coordination across the fleet.
- **Rotation procedure** documented in
  [`SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md): generate a new key,
  update GitHub authorized signing keys, update `user.signingkey`, optionally
  re-sign recent commits.
- **Compromise procedure**: revoke the public key from GitHub
  authorized-signing keys, generate a fresh key, audit `git log
  --show-signature` for unexpected fingerprints, and quarantine any
  unrecognized commits.

### Residual risk

- A compromised key combined with local commit access lets the attacker
  produce signed-but-malicious commits until the key is revoked. The five
  validation layers still apply to those commits (server-side `--no-verify`
  bypass is impossible once the GitHub Actions check is required), so the
  attacker cannot bypass content validation — only forge provenance.
- Rotation is manual; there is no automated key-rotation cadence. Acceptable
  for a single-user system; an enterprise extension would add scheduled
  rotation.

---

## 8. Threat R4 — Audit Findings Overload

### Threat description

The weekly `audit.sh` ([#528](https://github.com/kcenon/claude-config/issues/528))
surfaces too many findings (stale memories, duplicate-suspect pairs, broken
references, unused entries) for the user to review. The user defers review,
findings accumulate, and the audit channel becomes background noise that no
longer drives action. The system enters a state where validation runs but
nobody reads the output.

### Likelihood / Impact

- **Likelihood**: Medium. With 17 baseline memories the current finding rate
  is sustainable; as the corpus grows, finding volume grows roughly linearly.
- **Impact**: Low operationally — the system continues to function — but
  high erosionally: defeated audits hide real contamination signals that
  would otherwise be triaged.

### Attack surface

Not adversarial — a usability failure. Triggered by:

- Memory growth without proportional review cadence.
- A noisy validator that flags too many false positives (see also
  [R6](#10-threat-r6--validator-false-positives)).
- Lack of paginated or filterable review tooling.

### Detection layer

- The `/memory-review` skill ([#529](https://github.com/kcenon/claude-config/issues/529))
  surfaces audit findings interactively and tracks review state.
- `memory-status.sh --detail` shows audit-history activity.

### Mitigation

- **Batching**: `audit.sh` runs weekly, not daily. Findings cluster in a
  single report rather than streaming.
- **Threshold tuning**: `--stale-days N`, `--similarity-threshold N` flags
  let the operator tune signal-to-noise without code changes.
- **`/memory-review` paginates**: only flagged items surface; clean memories
  are silent.
- **Idempotency rule**: a recent report (<6 days) skips re-generation, so a
  flapping scheduler does not produce duplicate findings.

### Residual risk

Review cadence depends on the user. If `/memory-review` is not run, audit
reports pile up and the threat materializes. There is no automated
enforcement of review — by design, since a single-user system gains nothing
from machine-rejecting unreviewed audits. The mitigation is operator
discipline plus the SessionStart unread-alerts counter, which surfaces audit
findings at every session start.

---

## 9. Threat R5 — Backfill Destroys Data

### Threat description

`backfill-frontmatter.sh` ([#512](https://github.com/kcenon/claude-config/issues/512))
adds frontmatter to existing memory files. A bug in the script, an incorrect
invocation, or a malformed input could overwrite legitimate content,
corrupt frontmatter, or silently mis-attribute provenance.

### Likelihood / Impact

- **Likelihood**: Low. The script has been exercised on the 17 baseline
  memories ([#513](https://github.com/kcenon/claude-config/issues/513)),
  defaults to dry-run, and is idempotent.
- **Impact**: High when realized. A buggy backfill could affect every
  memory file in one invocation.

### Attack surface

- Direct invocation by the user with the wrong target tree.
- Future regression in the script logic.
- Input file with malformed pre-existing frontmatter triggering an unhandled
  edge case.

### Detection layer

- **Pre-execution**: dry-run (`--dry-run`) is the default; the operator
  inspects the diff before applying.
- **Backup**: every backfill writes a timestamped backup of the original
  tree before mutating.
- **Post-execution**: `validate.sh` is run against the modified tree; the
  audit and write-guard layers also apply on subsequent activity.

### Mitigation

- **Idempotency**: re-running on already-backfilled files is a no-op; the
  script detects existing frontmatter and skips.
- **Auto-backup**: the timestamped backup is kept until the operator
  manually deletes it.
- **Dry-run default**: applying changes requires an explicit `--apply` (or
  equivalent) flag.
- **Git history**: even without the explicit backup, every prior state is
  recoverable from `claude-memory` git history.

### Residual risk

- A truly catastrophic bug that simultaneously breaks the backup mechanism
  and the dry-run default — extremely unlikely, but not zero. Recovery in
  that case relies on git history.
- An operator who passes `--apply` after a too-quick dry-run inspection
  could miss a subtle issue. No automated safeguard; the dry-run output is
  the safeguard.

---

## 10. Threat R6 — Validator False-Positives

### Threat description

A heuristic validator (`secret-check.sh`, `injection-check.sh`, less commonly
`validate.sh`) flags content that is legitimate but pattern-matched against a
suspicion rule. A false positive at layer 1 (write-guard) blocks a Claude
write; at layer 3 (sync pre-push) it blocks the operator's commit. Repeated
false positives erode trust in the validators and incentivize bypass.

### Likelihood / Impact

- **Likelihood**: Medium. Pattern-based heuristics over natural-language
  content trade recall for precision; some false-positive rate is inherent.
- **Impact**: Medium. Real disruption (write-guard denials, push refused),
  but recoverable — the operator can refine the validator, override per
  call, or rephrase the memory.

### Attack surface

Not adversarial — design tension between recall and precision. Triggered by:

- Memory text that quotes secret-shaped patterns for documentation purposes
  (e.g., a memory describing how to recognize a leaked token).
- Memory text that quotes injection-shaped phrases (e.g., a memory about
  writing prompt-injection tests).

### Detection layer

- The validator emits explicit findings; the operator inspects them.
- `injection-check.sh` is **warn-only** (exit 3) by design — it surfaces
  patterns without blocking.
- `validate.sh` exit 3 (semantic warning) is also warn-only; only exits 1
  and 2 (structural and format errors) block writes.

### Mitigation

- **Tiered exit codes**: blocking versus warning is per-validator and
  per-condition. Only secret-detection (`secret-check.sh` exit 1) and
  hard structural errors (`validate.sh` exit 1/2) block; everything else
  surfaces feedback without preventing the action. See
  [`MEMORY_VALIDATION_SPEC.md`](./MEMORY_VALIDATION_SPEC.md) Section 7 for
  the contract.
- **Allowlist for known patterns**: quoted code blocks, fenced examples,
  and the `SECRETS_ALLOWLIST` (where applicable) reduce noise on canonical
  documentation patterns.
- **Operator override**: per-call bypass via documented escape hatches; never
  via silent `--no-verify` (which the server-side check catches).

### Residual risk

False-positive fatigue is the dominant residual risk. Mitigated only by:

- Periodic validator tuning against the false-positive corpus.
- Trust tiers — the operator can move a validator-warned-but-legitimate
  memory to `verified` after manual review without rewriting it.
- The warn-only stance for injection-check, which means the false-positive
  blast radius is feedback noise, not write loss.

---

## 11. Threat R7 — GitHub Outage / Repo Loss

### Threat description

`kcenon/claude-memory` becomes unavailable. Causes range from transient
GitHub outage (hours) to repository deletion (catastrophic). With no
remote, sync fails and machines diverge.

### Likelihood / Impact

- **Likelihood**: Low. GitHub uptime is >99.9% for typical workloads;
  outright repository loss is rare and recoverable from clones.
- **Impact**: High in the catastrophic case (no canonical source), graceful
  in the transient case (degrades to local-only operation).

### Attack surface

- GitHub-side incident.
- Account-level event (suspension, closure) affecting `kcenon`'s repos.
- Accidental repository deletion (mitigated by GitHub's 90-day soft-delete
  for private repos).
- Adversarial repo deletion via stolen GitHub credentials — handled under
  account-takeover threat model, out of scope here.

### Detection layer

- `memory-sync.sh` exits 6 (network / git operation failed) when remote is
  unreachable; `memory-notify.sh` raises a `critical` alert.
- SessionStart integrity check displays last-sync age; sustained sync
  failures surface as growing staleness.

### Mitigation

- **Local clones are full mirrors**. Every participating machine holds the
  complete history. Restoring after repository loss is `git push` from any
  one clone to a re-created repository.
- **Weekly `git bundle` to local backup** is the recommended operator
  practice; a bundle on offline media survives even simultaneous loss of
  GitHub and the primary machine.
- **Graceful degradation**: with GitHub down, sync fails open — local
  memory still loads at SessionStart, the write-guard still validates, and
  the operator continues working. Sync resumes automatically when the
  remote returns.

### Residual risk

- **Simultaneous loss of GitHub and all clones** would be terminal. Only
  offline `git bundle` backups close this gap; not enforced automatically.
- **Long outages compound** with [R1](#5-threat-r1--sync-silent-failure):
  a sustained GitHub outage looks identical to a dead scheduler. The 24h
  warning surfaces both equally, but root-cause diagnosis falls to
  `memory-status.sh` and `git fetch` manual checks.

---

## 12. Residual Risks

A consolidated view of residual risk across all seven threats:

| ID | Residual risk | Notes |
|----|---------------|-------|
| R1 | 24h drift window before SessionStart warning surfaces | Tunable threshold; no real-time push |
| R2 | Compositional injection across multiple files | Partial mitigation via monthly semantic review |
| R2 | Brief local-only window between bad write and validator catch | Layer 4 catches before propagation |
| R3 | Stolen-key forgery until revocation | Per-machine keys limit blast radius; content validators still apply |
| R4 | Audit fatigue → unreviewed findings | Operator discipline + SessionStart unread alerts |
| R5 | Catastrophic backfill bug + simultaneous backup failure | Git history is the ultimate recovery |
| R6 | False-positive fatigue | Tiered exit codes, warn-only stance for injection-check |
| R7 | Simultaneous GitHub + all-clones loss | Only offline `git bundle` closes; not automated |
| Meta | Insider threat by user account itself | Out of scope — single-user trusted operator model |
| Meta | Threats to host OS, network infra, GitHub itself | Out of scope per [Section 1](#1-purpose-and-scope) |

"All threats fully mitigated" is never true. The 5-layer defense, trust
tiers, and audit cadence collectively reduce realized risk to a level
acceptable for a single-user system that prizes auditability and
recoverability over zero-tolerance enforcement.

---

## 13. Versioning

| Version | Date | Change |
|---------|------|--------|
| 1.0.0 | 2026-05-01 | Initial publication. Covers R1–R7 from epic [#505](https://github.com/kcenon/claude-config/issues/505) risk table; aligns with `MEMORY_SYNC.md` v1.0.0. |

Subsequent versions follow the version-bump rules in
[`MEMORY_SYNC.md`](./MEMORY_SYNC.md#18-versioning).

---

## Cross-references

- [`MEMORY_SYNC.md`](./MEMORY_SYNC.md) — operations runbook (companion)
- [`MEMORY_VALIDATION_SPEC.md`](./MEMORY_VALIDATION_SPEC.md) — validator contract
- [`MEMORY_TRUST_MODEL.md`](./MEMORY_TRUST_MODEL.md) — trust tier semantics
- [`MEMORY_MIGRATION.md`](./MEMORY_MIGRATION.md) — single-machine migration runbook
- [`MEMORY_STABILIZATION_CHECKLIST.md`](./MEMORY_STABILIZATION_CHECKLIST.md) — single-machine stabilization
- [`SSH_COMMIT_SIGNING.md`](./SSH_COMMIT_SIGNING.md) — per-machine signing setup
- Epic [#505](https://github.com/kcenon/claude-config/issues/505) — cross-machine memory sync
