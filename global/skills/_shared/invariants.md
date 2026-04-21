# Shared Invariants

Canonical source for short rule-reminder blocks re-anchored inside long loops.

Skills with iterative work (batch loops, CI polling, multi-round research, per-repo dispatch) should emit the Core block inline every `--reanchor-interval N` iterations (default 5, `0` disables). This keeps the rules in the model's recent attention window as tool outputs accumulate.

**Token budget**: Core block ≈ 25 tokens per emission. A 30-item loop with interval=5 adds ~150 tokens. Optional block is loaded only when the skill touches those dimensions.

## Core (5 lines, re-anchor target)

```
- PR title/body, commit messages, issue comments: English only
- Commit format: type(scope): description (no Claude/AI attribution, no emojis)
- ABSOLUTE CI GATE: gh pr checks must show every check passing before merge
- Branch: feature off develop, squash merge back via PR
- 3-fail rule: stop and propose alternatives after 3 identical failures
```

## Optional (5 lines, load when the skill touches these dimensions)

```
- Protected branches: never direct-push to main or develop
- Validate incrementally: build and test after each logical change
- Close parent epic when all sub-issues are closed
- Batch pacing: 2-second pause between items, 0.3-second between API calls
- Missing toolchain: skip local build, rely on CI, do not auto-install
```

## How to use

Skills prepend a context label when emitting inline (e.g., `[Item 5/30] Required rules:`) and then copy the Core block verbatim. Optional block is added only when the skill's current phase touches those dimensions (direct pushes, batch pacing, epic closure, toolchain checks).

Changes to canonical rules happen here. Skills that copy the block inline must stay in sync with this file.
