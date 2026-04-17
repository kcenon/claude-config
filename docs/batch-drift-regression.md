# Batch Drift Regression Test

Automated regression test that verifies batch workflows retain rule compliance
at scale. Ensures a 30-item batch does not drift measurably from a 5-item baseline.

Part of epic [#287](https://github.com/kcenon/claude-config/issues/287).

## Overview

Long-running batch sessions (>15 items) suffer attention dilution: the model
progressively ignores rules as context accumulates. The Tier 0-2 mitigations
(hooks, chunked gates, subagent delegation) defend against this drift. The
regression test measures whether those defenses hold.

## Architecture

```
┌────────────────────────┐
│  GitHub Actions         │  Nightly + manual dispatch
│  batch-drift-regression │
└─────────┬──────────────┘
          │
          ▼
┌────────────────────────┐
│  run-regression.sh      │  Orchestrates: seed → benchmark → assert
└─────────┬──────────────┘
          │
    ┌─────┼──────────────────┐
    ▼     ▼                  ▼
  seed  run-benchmark.sh   thresholds.json
         │
         ▼
  aggregate-results.sh
         │
         ▼
  extractors.sh  ← SSOT: hooks/lib/validate-commit-message.sh
```

### Components

| Component | Path | Role |
|-----------|------|------|
| Regression runner | `tests/batch_drift_regression/run-regression.sh` | Top-level orchestrator |
| Thresholds | `tests/batch_drift_regression/thresholds.json` | Max allowed drift counts |
| CI workflow | `.github/workflows/batch-drift-regression.yml` | Nightly schedule + dispatch |
| Benchmark runner | `tests/batch_drift_benchmark/run-benchmark.sh` | Executes strategy under test |
| Seed script | `tests/batch_drift_benchmark/seed-scratch-repo.sh` | Bootstraps scratch repo |
| Extractors | `tests/batch_drift_benchmark/extractors.sh` | Signal measurement functions |
| Aggregator | `tests/batch_drift_benchmark/aggregate-results.sh` | Per-item → bucket summary |
| Documentation | `docs/batch-drift-regression.md` | This file |

## Drift Signals

Five signals are measured on every PR produced during the batch:

| Signal | What it measures | Extractor |
|--------|-----------------|-----------|
| `language_violations` | CJK characters in PR body (non-English leak) | `extract_language_violations` |
| `attribution_leaks` | Claude/Anthropic/AI-assisted references | `extract_attribution_leaks` |
| `ci_gate_violations` | PR merged while checks not all passing | `extract_ci_gate_violations` |
| `missing_closes` | PR body missing `Closes #N` keyword | `extract_missing_closes` |
| `commit_format_violations` | Commits failing Conventional Commits format | `extract_commit_format_violations` |

Attribution detection uses `CMV_ATTRIBUTION_REGEX` from
`hooks/lib/validate-commit-message.sh` (SSOT) — the same regex enforced by the
`commit-message-guard` and `attribution-guard` hooks.

## Thresholds

Default thresholds apply to the `items_6_to_30` bucket (items beyond the
safe-zone baseline). They are defined in `tests/batch_drift_regression/thresholds.json`:

| Signal | Max Allowed | Rationale |
|--------|-------------|-----------|
| `language_violations` | 0 | Mandatory English — zero tolerance |
| `attribution_leaks` | 0 | Enforced by hooks — zero tolerance |
| `ci_gate_violations` | 0 | Absolute CI gate — zero tolerance |
| `missing_closes` | 1 | Allow 1 transient miss (edge case in auto-close) |
| `commit_format_violations` | 0 | Enforced by commit-msg hook — zero tolerance |

### Tuning Thresholds

Edit `thresholds.json` or pass `--threshold-file` with a custom file.
Thresholds should be tuned after the first live benchmark run (#315) provides
baseline data. A threshold of 0 means "as strict as the 5-item baseline."

## Running the Test

### Locally

```bash
# Dry-run (no network, no cost)
bash tests/batch_drift_regression/run-regression.sh --dry-run

# Live run (requires gh + claude CLI, creates real PRs)
bash tests/batch_drift_regression/run-regression.sh \
    --strategy subagent \
    --items 30

# Custom thresholds
bash tests/batch_drift_regression/run-regression.sh \
    --threshold-file path/to/custom-thresholds.json

# Skip seeding (reuse existing scratch repo state)
bash tests/batch_drift_regression/run-regression.sh --skip-seed
```

### Via GitHub Actions

- **Nightly**: Runs automatically at 03:17 UTC (12:17 KST) daily
- **Manual**: Go to Actions → "Batch Drift Regression" → Run workflow
  - Select strategy (default: subagent)
  - Set item count (default: 30)
  - Optionally skip seeding

### CI Requirements

The workflow requires two repository secrets:

| Secret | Purpose |
|--------|---------|
| `SCRATCH_REPO_TOKEN` | GitHub PAT with write access to `kcenon/batch-drift-scratch` |
| `ANTHROPIC_API_KEY` | API key for Claude CLI invocations |

## Triage Guide

### When the regression test fails

1. **Check the summary artifact** — download `regression-summary` from the Actions run
2. **Identify which signal(s) failed** — the `last-run-summary.json` file lists each signal with actual vs threshold
3. **Check if the failure is in items 6-30** — early items (1-5) are always the baseline
4. **Review the raw PR data** — download `benchmark-logs` artifact for per-item JSON

### Common failure causes

| Signal | Likely Cause | Fix |
|--------|-------------|-----|
| `language_violations` | `pr-language-guard` hook disabled or bypassed | Verify hook in `global/hooks/` |
| `attribution_leaks` | `attribution-guard` hook regex drift | Check SSOT regex in `hooks/lib/validate-commit-message.sh` |
| `ci_gate_violations` | `merge-gate-guard` hook weakened | Verify hook logic and test |
| `missing_closes` | Skill template changed | Check `Closes #N` pattern in skill files |
| `commit_format_violations` | `commit-msg` hook broken | Run `hooks/lib/validate-commit-message.sh` tests |

### Intentional regression testing

To verify the test catches real drift, temporarily disable a hook and run:

```bash
# 1. Disable pr-language-guard (backup first)
mv global/hooks/pr-language-guard.sh global/hooks/pr-language-guard.sh.bak

# 2. Run regression — should FAIL on language_violations
bash tests/batch_drift_regression/run-regression.sh --strategy subagent

# 3. Restore hook
mv global/hooks/pr-language-guard.sh.bak global/hooks/pr-language-guard.sh
```

## Outputs

| Output | Path | Retention |
|--------|------|-----------|
| Run summary | `tests/batch_drift_regression/last-run-summary.json` | Until next run |
| Strategy results | `tests/batch_drift_benchmark/results/<strategy>-<ts>.json` | Permanent (committed) |
| Benchmark logs | `tests/batch_drift_benchmark/logs/<strategy>-<ts>.log` | 14 days (CI artifact) |
| Raw PR data | `tests/batch_drift_benchmark/logs/<strategy>-<ts>-raw/` | 14 days (CI artifact) |

## Cost

Each regression run processes N items through a full `/issue-work` cycle:
- 30 items × ~1 Claude session each = significant token usage
- Creates ~30 PRs in the scratch repo
- Typical runtime: 1-3 hours

The nightly schedule limits cost to one run per day. Use `workflow_dispatch`
for ad-hoc runs after skill or hook changes.

---
*Part of epic #287. Version 1.0.0*
