# Distributed Batch Dispatch via RemoteTrigger

> **Type**: Design / Research Document
> **Status**: Research only — no implementation
> **Related issues**: #287 (epic), #298 (this research), #297 (external orchestrator), #306 / #294 (subagent delegation, shipped)
> **Purpose**: Evaluate whether `RemoteTrigger` and the `/schedule` skill can be used as a distributed dispatch layer for `issue-work` / `pr-work` batch mode, and record a go / defer / reject decision.

## Background

Long-running batch workflows in `issue-work` and `pr-work` experience rule drift around items 15-25 of a single in-process run. The epic #287 catalogues mitigations across four tiers:

- Tier 0 (shipped): lower default batch limit, chunked confirmation gate, inline rule reminders
- Tier 1 (shipped): PreToolUse guards for language, merge gate, and attribution
- Tier 2 (shipped): **subagent delegation** as the default batch dispatch strategy (#294 / PR #306)
- Tier 2 (shipped, this repo): **`--auto-restart`** flag for process-level resets every N items (#296 / PR #307)
- Tier 3 (this document + #297): distributed dispatch via RemoteTrigger or external orchestrator scripts

Subagent delegation already provides per-item context isolation inside a single parent Claude session. `--auto-restart` provides full process-level isolation every N items via resume files. Both reuse Claude Code's built-in infrastructure. The question this document addresses is whether pushing the isolation boundary further — one remote-agent session per batch item, with completely independent lifecycles — yields enough additional benefit to justify the added complexity and operational surface area.

## Known Properties of RemoteTrigger

This section records only what is knowable from the tool's declared API surface and the `/schedule` skill description, without performing a test call. Each unknown is flagged for the empirical test plan at the bottom.

### API surface

RemoteTrigger maps onto `/v1/code/triggers` with five actions:

| Action | HTTP | Path | Purpose |
|--------|------|------|---------|
| `list` | GET | `/v1/code/triggers` | Enumerate existing triggers on the account |
| `get` | GET | `/v1/code/triggers/{id}` | Fetch one trigger's definition and recent-run metadata |
| `create` | POST | `/v1/code/triggers` | Register a new cron-scheduled remote agent; body describes the prompt / skill to invoke |
| `update` | POST | `/v1/code/triggers/{id}` | Partial update to an existing trigger |
| `run` | POST | `/v1/code/triggers/{id}/run` | Fire an existing trigger immediately, optionally with a per-run body override |

Authorization is handled in-process by the OAuth token the CLI already holds. Unlike subagent delegation (which borrows the parent's in-memory tool permissions), each trigger run is billed and rate-limited as a separate Anthropic session on the same account.

### Execution model

A remote trigger run starts a **fresh remote Claude session** on Anthropic infrastructure. The session has its own:
- CLAUDE.md load (reloaded from repo contents at trigger time)
- Skills, agents, and settings resolved against the same account
- Conversation history (empty at start — no parent context inherited)
- Tool result pool (empty — no contamination)

This is strictly stronger isolation than subagent delegation, because subagents still execute in the parent Claude Code process and share its memory address space, even though their conversation window is fresh.

### `/schedule` skill

The `/schedule` skill described in the session-level tool catalogue wraps RemoteTrigger with a cron-first interface. It is designed for the recurring-agent use case (`every day at 09:00`), not a fire-and-forget dispatch loop. Its primary affordance is scheduling, not queuing — meaning the conceptual fit with "dispatch 30 independent jobs right now" is awkward: one would have to use `create` + `run` in pairs, or `run` without scheduling if the API permits ad-hoc invocations.

## Six Research Questions

### Q1. Can `RemoteTrigger create` accept arbitrary skill invocations with arguments?

**Known**: The `create` body is free-form JSON; the API surface places no semantic constraints on the prompt field. A prompt of `/issue-work $ORG/$PROJECT $ISSUE_NUMBER --solo` should be representable as plain text, and the remote session would interpret it the same way the local CLI does because both resolve against the same `.claude/skills/` directory of the account.

**Unknown — requires empirical test**:
- Whether the remote execution environment receives the same environment variables, MCP server config, and hook settings as the local session (without these, `settings.json`-driven hooks like `commit-message-guard` or `pr-target-guard` may not apply).
- Whether interactive tools (`AskUserQuestion`, TTY prompts) are supported in remote sessions or are no-ops / errors.
- Whether the remote session can push commits to the user's repo (git identity inheritance, SSH keys, `gh auth` token scope).

**Risk if these fail**: The whole point of delegation is rule enforcement. A remote session without the hook layer is a **worse** isolation story than subagent delegation, not a better one.

### Q2. What is the per-trigger creation and dispatch latency?

**Known**: `create` is a synchronous POST to Anthropic API; expected latency is bounded by HTTP round-trip plus server-side trigger registration. `run` is similarly a POST that queues the trigger — the actual remote session startup (loading CLAUDE.md, resolving skills, streaming system prompt) happens server-side after the POST returns.

**Unknown — requires empirical test**:
- Create+run end-to-end time for a single trivial trigger (target: < 5s for "dispatch 30 jobs" to feel responsive)
- Whether `create` can be followed immediately by `run`, or if there is a minimum scheduling gap
- Whether `run` returns once the remote session starts, or once it completes (the critical factor for orchestrator design)

**Guess**: Create is likely sub-second. Run likely starts a session asynchronously and returns an ID within a few seconds. But guessing is exactly what this question was meant to eliminate — numbers are required before "dispatch 30 jobs and let them run" can be claimed feasible.

### Q3. How are completions reported back to the orchestrator?

This is the hardest question and likely the decisive one.

**Known from API surface**: The `get` action returns trigger state, including presumably a recent-run list with exit status. Polling `get` on each dispatched trigger is the only documented path back to the orchestrator.

**Unknown — requires empirical test**:
- Whether `get` exposes a rich completion record (stdout, exit code, PR URL, CI status) or only a binary success/fail status
- Whether there is any push-style notification (webhook, long poll, event stream) or only polling
- Whether intermediate progress is visible while a remote run is in flight

**Design implication**: If only polling is available, the orchestrator pattern degrades from "dispatch and forget" to "dispatch and poll every N seconds × 30 items". At 30 items × 30s poll interval × 10 minutes average runtime, that is 600 API calls just for status, before retries. This cost has to be compared against the alternative: a single `--auto-restart` run that uses zero API calls beyond normal Claude Code traffic.

### Q4. Cost model — 30 remote sessions vs 30 subagents vs 30 process invocations

Comparison across the three currently-available dispatch strategies for a hypothetical 30-item batch. Numbers in parentheses are order-of-magnitude estimates; real values require empirical test.

| Dimension | Subagent delegation (shipped) | `--auto-restart` every 5 (shipped) | External script (#297) | Remote trigger per item (this doc) |
|-----------|-------------------------------|-----------------------------------|-----------------------|-----------------------------------|
| Parent-side token growth | ~100 words per item (~3K total) | Resets every 5 items | Zero (each item in its own process) | Zero (each item in its own remote session) |
| CLAUDE.md reload count | 1 (parent) | 6 (every chunk) | 30 | 30 |
| Skill catalogue reload | 1 | 6 | 30 | 30 |
| Per-item startup cost | Low (shared parent pool) | Medium (fresh chunk but same host process) | High (full `claude` boot) | Highest (remote session + network) |
| Tool permission inheritance | Yes (parent's settings) | Yes (reloaded at restart) | Yes (loaded from disk) | **Unknown** — risk of drift from local `settings.json` |
| Hook enforcement | Yes (same process) | Yes (same process) | Yes (reloaded from disk) | **Unknown** — risk of remote runtime not executing local hooks |
| Completion visibility | Immediate (same turn) | Immediate (before restart) | Process exit code + log file | **Polling-only** (Q3) |
| Failure blast radius | Isolated to subagent | Isolated to current chunk | Isolated to process | Isolated to remote session |
| Orchestrator complexity | Lowest (built-in) | Low (resume file + wrapper) | Medium (bash/PowerShell script) | Highest (dispatcher + poller + reconciliation) |
| Infrastructure dependency | None | None (optional wrapper) | Local shell + `claude` CLI | Anthropic API uptime + rate limits |
| Cost amplification per item | Baseline | Baseline + 1 startup per chunk | Baseline + full startup per item | Baseline + full startup per item + network + polling |

Read across the rows, the pattern is clear: **each successive strategy trades local convenience for stronger isolation, but the isolation gain diminishes faster than the operational cost grows**. Subagent delegation already takes care of per-item attention pool freshness. `--auto-restart` takes care of process-level state accumulation. `#297` takes care of disk-level state accumulation. The remaining scenario where remote triggers uniquely win is when the user wants **parallel execution across independent accounts or machines** — a use case neither issue-work nor pr-work actually has.

### Q5. Failure isolation guarantees

**Known**: Remote sessions are fully separate on the server side. An OOM, crash, timeout, or infinite loop in one remote session cannot affect another remote session or the local orchestrator. This is strictly better than any in-process approach.

**Unknown — requires empirical test**:
- Whether a failed remote session is retried automatically or left in a terminal failed state
- Whether the API surfaces a clear distinction between "infrastructure failure" (retry-safe) and "task failure" (user action needed)
- What happens if the Anthropic API is temporarily unavailable mid-batch — does `list` eventually catch up, or are dispatched triggers lost?

### Q6. Concurrency limits and rate limiting

**Unknown — requires empirical test**:
- The per-account maximum concurrent remote sessions (hard limit from Anthropic tier)
- Rate limits on `create`/`run` POSTs per minute
- Whether hitting a limit returns 429 + retry-after, or a different error shape
- Whether the limit counts remote triggers separately from regular Messages API traffic

**Design implication**: If the concurrent-session limit is below 30, the "spawn 30 jobs and let them run" model becomes "spawn N, wait for a slot, spawn more" — which is essentially a re-implementation of `--auto-restart` with network latency. If the limit is generous but rate-limited (e.g., 60 POSTs/minute), 30-item dispatch is fine but a 200-item recovery run could be throttled.

## Cost comparison summary table

| Strategy | Shipped? | Parent context growth | Isolation strength | Ops complexity | New failure modes |
|----------|----------|----------------------|-------------------|----------------|-------------------|
| Subagent delegation (#294) | Yes (PR #306) | Fixed ~100 words/item | Conversation-level | None | None |
| `--auto-restart` (#296) | Yes (PR #307) | Resets every N items | Process-level | Low (wrapper script) | Interrupted writes to resume file |
| External script (#297) | No | Zero | OS process-level | Medium (bash/ps1 orchestrator) | Log file rotation, signal handling |
| RemoteTrigger per item (#298) | No | Zero | Remote-session-level | **Highest** | API outages, auth drift, rate limits, completion polling races, hook non-application (Q1/Q3/Q6) |

## Decision

**DEFER.** Do not implement now. Revisit only if specific user demand emerges.

### Rationale

1. **The problem #298 was designed to solve is already solved by shipped work.** Subagent delegation covers conversation-level drift. `--auto-restart` covers process-level state accumulation. Both reuse existing infrastructure and require no new operational surface area. There is no open quality gap that remote triggers would uniquely close.

2. **The known unknowns in Q1, Q3, and Q6 are exactly the ones that would make remote triggers either a strict improvement or a strict regression compared to subagent delegation.** Without those answers, the decision "implement" is not defensible. Testing would require creating real triggers on the user's Anthropic account with resulting cost and potential clutter — a side effect that is not justified while simpler shipped alternatives exist.

3. **The unique value proposition of remote triggers (parallel execution across independent accounts / machines) is not a current `issue-work` / `pr-work` requirement.** Batches in this repo are already small (default `--limit 5`, hard cap 10 without `--force-large`) because rule drift, not throughput, is the binding constraint. Parallel dispatch does not address rule drift; it just moves it to a different axis.

4. **Revisiting trigger**: This decision should be reconsidered if any of the following becomes true:
   - A real-world batch exceeds 30 items routinely and users report `--auto-restart` is not enough
   - Anthropic publishes concrete documentation on RemoteTrigger hook inheritance, completion reporting, and rate limits that resolves Q1 / Q3 / Q6 positively
   - A user explicitly asks to run multiple batches concurrently on the same account (fan-out across repos)
   - The `/schedule` skill adds an ad-hoc "run now with prompt" affordance that eliminates the create+run two-step

### Empirical test plan (for future revisit)

If this decision is revisited, the following minimal test sequence would resolve the open questions at low cost and minimum account clutter. **Do not execute without explicit user approval**, because even a trivial test leaves a trigger artifact on the user's Anthropic account.

| # | Test | Measures | Success criterion |
|---|------|----------|-------------------|
| 1 | `RemoteTrigger create` with a prompt that prints `echo hello` and exits | Q1 — can arbitrary text be used as a prompt; create latency | Create returns < 2s with a trigger ID |
| 2 | `RemoteTrigger run` on the trigger from step 1 | Q2 — run-to-start latency | Run returns < 3s with a run ID |
| 3 | `RemoteTrigger get` polled every 10s until completion | Q3 — completion shape; polling cost per item | Completion visible within 30s with structured exit status |
| 4 | `RemoteTrigger create` with a prompt that invokes `/issue-work $repo $issue --solo` on a trivial test issue | Q1 — real skill invocation; environment inheritance | Remote session respects CLAUDE.md language rule, commit hooks, and PR target gate |
| 5 | 5× parallel `create`+`run` with the test prompt | Q6 — concurrency limits | All 5 succeed without 429 |
| 6 | Intentionally-failing prompt | Q5 — failure shape | `get` returns a distinguishable error status |

Cost upper bound: 6 trigger creations + ~6 short runs, disposable afterwards via `list` + `delete` (if delete is supported; otherwise the triggers remain until account cleanup).

## Relationship to other tier-3 issues

- **#297 — external orchestrator script**: Orthogonal, not superseded by this decision. #297 is a local-only alternative with no new infrastructure dependency. If `--auto-restart` turns out to be insufficient for a specific user workflow, #297 is the next-closest option and can be shipped independently of this research.
- **#299 — re-invoke skill per item**: Already closed as deprecated by subagent delegation (#294 / PR #306).
- **#295 — default to team mode**: Already closed as superseded by subagent delegation (#294 / PR #306).

## Acceptance criteria for this issue

- [x] Design doc exists with answers to all 6 questions (answers split into "known from API surface" and "requires empirical test" where appropriate)
- [x] Cost comparison table across subagent delegation, `--auto-restart`, external script, and remote trigger
- [x] Decision recorded: **DEFER**
- [x] Empirical test plan documented for future revisit
- [N/A] If implement: separate follow-up issue created — not applicable because the decision is DEFER
