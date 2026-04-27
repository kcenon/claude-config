# Team Mode Instructions

Three-team workflow for tiered feature implementation. Dev team implements each tier, Review team validates quality, Doc team documents. Per-tier feedback loop ensures every tier meets quality gates.

> **Requires**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json

## Team Architecture

```
         Lead (Coordinator)
         ┌──────────────┐
         │ Tier tracking │
         │ Final report  │
         └──────┬───────┘
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
┌──────┐   ┌──────┐   ┌──────┐
│ Dev  │◄──│Review│   │ Doc  │
│ Team │──►│ Team │   │ Team │
└──────┘   └──────┘   └──────┘
  dev     reviewer    doc-writer

  Per tier: Dev implements → Reviewer validates → Doc-writer documents
  Feedback: Reviewer → Dev for fixes before moving to next tier
```

## T-1. Setup (Lead executes)

Perform Solo Mode Steps 1-2 (Enumerate Tiers, User Confirmation).
After user confirms, create team.

## T-2. Create Team and Tasks

```
TeamCreate(team_name="impl-all-levels", description="Implement all tiers for: $FEATURE")
```

For each tier (e.g., Easy, Medium, Hard), create a task group:

| Task | Subject | Owner | blockedBy |
|------|---------|-------|-----------|
| 1 | Implement Easy tier | dev | — |
| 2 | Write tests for Easy tier | dev | 1 |
| 3 | Review Easy tier: quality + completeness | reviewer | 2 |
| 4 | Document Easy tier | doc-writer | 2 |
| 5 | Apply review changes for Easy tier (if any) | dev | 3 |
| 6 | Implement Medium tier | dev | 3 or 5 |
| 7 | Write tests for Medium tier | dev | 6 |
| 8 | Review Medium tier | reviewer | 7 |
| 9 | Document Medium tier | doc-writer | 7 |
| 10 | Apply review changes for Medium tier (if any) | dev | 8 |
| 11 | Implement Hard tier | dev | 8 or 10 |
| 12 | Write tests for Hard tier | dev | 11 |
| 13 | Review Hard tier | reviewer | 12 |
| 14 | Document Hard tier | doc-writer | 12 |
| 15 | Apply review changes for Hard tier (if any) | dev | 13 |
| 16 | Final report: all tiers complete | lead | 13 or 15, 4, 9, 14 |

**Key flow:** Each tier follows: Dev implements → Dev tests → Reviewer reviews ∥ Doc-writer documents → Dev fixes (if needed) → Next tier.

Doc-writer tasks can run in parallel with review (both depend on implementation + tests).

## T-3. Spawn Teammates

**Dev Team** (implementation + tests):

```
Agent(
  name="dev",
  team_name="impl-all-levels",
  subagent_type="general-purpose",
  prompt="You are the dev team for implementing all tiers of: $FEATURE

    Your responsibilities:
    1. Implement each tier in order (Easy → Medium → Hard)
    2. Write comprehensive tests for each tier
    3. Run tests and verify passing before marking implementation complete
    4. If reviewer sends change requests, apply fixes before moving to next tier

    Enforcement rules (CRITICAL):
    - NO partial implementations: every tier must be fully functional
    - NO TODO comments: every function must be implemented
    - NO placeholder returns: no 'return 0', 'return None', 'return {}'
    - NO untested tiers: each tier MUST have passing tests

    Commit format: feat(scope): implement <tier> tier (English only, no emojis)
    Test commit: test(scope): add tests for <tier> tier

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Review Team** (quality validation per tier):

```
Agent(
  name="reviewer",
  team_name="impl-all-levels",
  subagent_type="general-purpose",
  prompt="You are the review team for validating all tiers of: $FEATURE

    Your responsibilities per tier:
    1. Verify the implementation is complete (no TODOs, no placeholders)
    2. Check code quality: DRY, proper error handling, edge cases
    3. Verify tests cover the tier's requirements adequately
    4. Check that the tier integrates correctly with previous tiers
    5. If issues found, send change requests to dev

    Classification:
    - Critical: Incomplete implementation, placeholder code, missing tests
    - Major: Poor error handling, missing edge cases, integration issues
    - Minor: Style, naming, minor optimizations

    Feedback loop:
    - Send change requests to dev via SendMessage if Critical/Major found
    - Max 2 review rounds per tier. After round 2, approve with notes.
    - Do NOT allow moving to next tier with unresolved Critical items.

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Documentation Team** (per-tier documentation):

```
Agent(
  name="doc-writer",
  team_name="impl-all-levels",
  subagent_type="general-purpose",
  prompt="You are the documentation team for: $FEATURE

    Your responsibilities per tier:
    1. Document the tier's functionality and usage
    2. Add code examples showing how to use the tier
    3. Update any relevant README sections
    4. If the tier adds CLI flags or configuration, document them

    Rules:
    - Document each tier as it's completed (don't wait for all tiers)
    - Match existing documentation style
    - Commit format: docs(scope): document <tier> tier (English only)

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

## T-4. Workflow (Lead coordinates)

For each tier (Easy → Medium → Hard):

**Per-Tier Cycle:**
1. Dev implements tier + writes tests (sequential)
2. Reviewer validates ∥ Doc-writer documents (parallel)
3. If reviewer has Critical/Major findings → Dev fixes → Reviewer re-reviews
4. When tier approved → proceed to next tier

```
┌─── Tier N ────────────────────────────────┐
│ Dev: implement → test                      │
│        │                                   │
│        ├──► Reviewer: validate             │
│        │         │                         │
│        │    Has Critical?                  │
│        │    ├─ Yes → Dev fixes → Re-review │
│        │    └─ No → Approved               │
│        │                                   │
│        └──► Doc-writer: document           │
│                                            │
│ Tier approved → Next Tier ─────────────────┘
```

**Important:** Do NOT start next tier until reviewer approves current tier.
This prevents cascade failures where later tiers build on broken earlier tiers.

## T-5. Final Report (Lead)

After all tiers complete, generate the same report format as Solo Mode Step 5,
with additional team metrics:

| Metric | Value |
|--------|-------|
| Tiers completed | N/N (100%) |
| Review rounds | X total across all tiers |
| Change requests resolved | Y |

## T-6. Cleanup

```
SendMessage(to="dev", message={type: "shutdown_request"})
SendMessage(to="reviewer", message={type: "shutdown_request"})
SendMessage(to="doc-writer", message={type: "shutdown_request"})
TeamDelete()
```

## T-Error. Team Mode Fallback

If any teammate fails or team coordination breaks down:

1. Shutdown all teammates and delete team
2. Check which tiers are complete (all must have passing tests)
3. Offer to continue in Solo Mode from the next incomplete tier
4. Preserve all commits — completed tiers are still valid
