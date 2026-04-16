# Tier 2 Benchmark Results

Quantitative comparison of Tier 2 isolation strategies against the
rule-drift problem described in epic [#287](https://github.com/kcenon/claude-config/issues/287).

## Run Metadata

| Field | Value |
|-------|-------|
| Date | 2026-04-16 |
| claude-config commit | `c01b8ba` |
| scratch-repo | `kcenon/batch-drift-scratch` |
| scratch-repo SHA | See PR list in raw results |
| Claude CLI version | 2.1.109 |
| Items per strategy | 30 (+ 5-item baseline) |

## Strategy Comparison

| Strategy | Items 1-5 drift | Items 6-30 drift | Total | Drift growth |
|----------|----------------|------------------|-------|--------------|
| 5-item baseline | 0/25 | n/a | 0 | n/a |
| Single-session batch (30 items) | 0/25 | 0/125 | 0 | 1.0x |

**Drift growth < 1.5x is the qualitative pass bar.** Both runs passed.

### Signal Breakdown

#### 5-item Baseline

| Signal | Count |
|--------|-------|
| language_violations | 0 |
| attribution_leaks | 0 |
| ci_gate_violations | 0 |
| missing_closes | 0 |
| commit_format_violations | 0 |

#### Single-Session Batch (30 items)

| Signal | Items 1-5 | Items 6-30 | Total |
|--------|-----------|------------|-------|
| language_violations | 0 | 0 | 0 |
| attribution_leaks | 0 | 0 | 0 |
| ci_gate_violations | 0 | 0 | 0 |
| missing_closes | 0 | 0 | 0 |
| commit_format_violations | 0 | 0 | 0 |

## Analysis

### Methodology

The benchmark used `kcenon/batch-drift-scratch`, a disposable repo prefilled with
30 trivial typo-fix issues (each requiring `teh` → `the` in a single file). Drift
signals were extracted from the PRs and commits produced during the batch run using
the SSOT extractor library (`tests/batch_drift_benchmark/extractors.sh`).

### Key Finding: Zero Drift Detected

Both the 5-item baseline and the 30-item single-session batch produced zero drift
signals across all five dimensions. This indicates that for **trivial, uniform
workloads**, the Tier 0-1 mitigations (hooks, inline rules, chunked gates) are
sufficient to prevent drift without additional Tier 2 isolation.

### Limitations of This Benchmark

1. **Workload uniformity**: All 30 items were identical in complexity (XS, single-line
   typo fixes). Real-world batches have heterogeneous complexity, which increases
   cognitive load and context pressure. The zero-drift result may not generalize to
   mixed-complexity batches.

2. **Single-session only**: The 30-item run executed in a single `claude --print`
   session (batch mode), not under a specific Tier 2 isolation strategy. This tests
   the Tier 0-1 mitigations but does not isolate the Tier 2 contribution.

3. **Subagent and auto-restart strategies not benchmarked**: These strategies could not
   be tested because `run-benchmark.sh` invokes `claude --print` in batch mode, which
   triggers `AskUserQuestion` for plan approval. `--print` mode cannot answer interactive
   prompts. The `--no-confirm` flag skips the chunked gate (B-4.1) but not the initial
   batch plan approval (B-3).

4. **No CI in scratch repo**: The scratch repo has no CI workflow beyond GitGuardian,
   so `ci_gate_violations` is measured against a permissive check set. A production
   repo with strict CI would provide a stronger signal.

### Strategy Assessment

| Strategy | Tested? | Isolation Level | Notes |
|----------|---------|----------------|-------|
| Subagent (#294) | No | Agent tool boundary | Blocked by batch mode approval in --print mode |
| Auto-restart (#296) | No | Process restart | Blocked by same limitation |
| Orchestrator (#297) | Partial (1 item) | OS process boundary | Works per-item; batch-issue-work.sh validated |
| Single-session | Yes (30 items) | None (Tier 0-1 only) | Zero drift on trivial workload |

### Recommendation

1. **For trivial/uniform workloads**: Tier 0-1 mitigations are sufficient. No
   additional isolation needed.

2. **For production mixed-complexity batches**: Use the **orchestrator** strategy
   (`scripts/batch-issue-work.sh`) as the default. It provides the strongest
   isolation guarantee (OS process boundary per item) and was validated for
   single-item execution.

3. **Follow-up required**: Run a heterogeneous-complexity benchmark (mix of XS-L
   issues) to determine where single-session batch drift actually begins. This
   would establish the true value of Tier 2 isolation strategies.

4. **Fix batch mode for --print**: Add `--auto-approve` flag or make `--no-confirm`
   skip the initial batch plan approval when running non-interactively. This
   unblocks proper subagent and auto-restart benchmarking.

## Chosen Winner

**Orchestrator (#297)** — recommended as the default Tier 2 strategy for
production batches, based on:

1. Strongest isolation guarantee (OS-level process isolation per item)
2. Validated in this benchmark for per-item execution
3. No batch mode --print limitation (calls claude per item, not in batch mode)
4. Zero drift in single-item tests

The subagent (#294) and auto-restart (#296) strategies should be benchmarked with
a heterogeneous workload once the `--auto-approve` limitation is resolved.

## Raw Results

| File | Description |
|------|-------------|
| `results/subagent-baseline-20260416T032000Z.json` | 5-item baseline aggregated results |
| `results/subagent-30item-20260416T043000Z.json` | 30-item single-session aggregated results |
| `logs/subagent-baseline-*-raw/` | Per-item PR data (baseline) |
| `logs/subagent-30item-*-raw/` | Per-item PR data (30-item) |

---
*Part of epic #287. Version 1.0.0*
