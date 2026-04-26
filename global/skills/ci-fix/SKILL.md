---
name: ci-fix
description: "Diagnose and fix failing CI checks by classifying the failure into a known pattern and applying a codified remediation. Use when CI reports MSVC C4996 warnings-as-errors, CMake FetchContent shallow-clone failures, __cpp_lib_format probe mismatches, or when pr-work escalates a failing workflow. Cuts the push-wait-fail-retry loop to a single iteration for the three dominant patterns documented from prior sessions."
argument-hint: "[pr-number] [--pattern msvc-c4996|cmake-fetchcontent|cpp-lib-format] [--dry-run]"
user-invocable: true
disable-model-invocation: false
allowed-tools: "Bash(gh *)"
max_iterations: 3
halt_conditions:
  - { type: success,  expr: "Workflow run conclusion == success" }
  - { type: fallback, expr: "failure maps to an unknown error class not in reference/known-fixes.md" }
on_halt: "Escalate to user with failing log excerpt and classification result"
loop_safe: true
---

# ci-fix Skill

Classify a failing CI run into one of the three recurring patterns captured in `reference/known-fixes.md`
and apply the codified remediation before re-pushing.

## Usage

```
/ci-fix                                         # Auto-detect current branch's failing PR
/ci-fix 601                                     # Target PR #601
/ci-fix 601 --pattern msvc-c4996                # Skip classification, apply a specific fix
/ci-fix 601 --dry-run                           # Print the diagnosis and proposed diff only
```

## Arguments

| Argument | Purpose |
|----------|---------|
| `[pr-number]` | PR to diagnose. If omitted, resolve via the current branch's open PR. |
| `--pattern <id>` | Skip classification. Valid ids: `msvc-c4996`, `cmake-fetchcontent`, `cpp-lib-format`. |
| `--dry-run` | Print diagnosis, quote the failing log excerpt, and show the proposed diff. Do not write files or push. |

## When to Invoke

- A PR's CI has **one failing run** matching one of the three patterns.
- `pr-work` has escalated after its built-in retry budget is exhausted.
- The user says "fix CI", "classify this CI failure", or names a pattern explicitly.

Do **not** invoke for:
- Flaky-but-unknown failures (log, ask user, add to `known-fixes.md` if it recurs).
- Green CI (nothing to fix).

## Classification Pipeline

Follow this deterministic sequence. Stop at the first match.

1. **Fetch log excerpt**
   ```bash
   RUN_ID=$(gh run list --branch "$(git branch --show-current)" \
     --json databaseId,conclusion --jq '.[] | select(.conclusion=="failure") | .databaseId' | head -1)
   gh run view "$RUN_ID" --log-failed | tail -200
   ```

2. **Match against the classifier table** (`reference/known-fixes.md` § Classifier):

   | Signal in log | Pattern |
   |---------------|---------|
   | `error C4996` OR `warning C4996` under MSVC with `/WX` | `msvc-c4996` |
   | `FetchContent` + `fatal: could not read Username` / `object ... not found` / `remote error: upload-pack` on a commit hash | `cmake-fetchcontent` |
   | `<format>` include + missing `__cpp_lib_format` OR link error for `std::format` | `cpp-lib-format` |

3. **Apply the codified fix**
   - `msvc-c4996` → see `reference/msvc-c4996.md`
   - `cmake-fetchcontent` → see `reference/cmake-fetchcontent.md`
   - `cpp-lib-format` → see `reference/known-fixes.md` § cpp-lib-format

4. **Commit with conventional format**
   ```
   fix(ci): <pattern-id> — <short reason>
   ```

5. **Push and monitor**
   Reuse the `pr-work` CI monitor loop. Budget: 20 minutes total (4 × 5-minute retries).

## Escalation

This table operationalizes the skill's frontmatter `halt_condition` and `on_halt` fields. Every condition below is a terminal halt state that consumes one of the `max_iterations: 3` budget slots.

| Condition | Action | Halt |
|-----------|--------|------|
| Classifier does not match | Print the first 80 lines of the log; ask the user to either add a new pattern to `known-fixes.md` or hand off. | yes — unknown error class |
| Fix applied but CI still red | Re-classify once. On a second miss, convert the PR to draft and escalate. | yes — after 2nd miss |
| 20-minute budget exceeded | Report current check table; do **not** merge. | yes — time budget |

**Example halt trace**: CI reports `cmake-fetchcontent` → fix applied → CI still fails with `msvc-c4996` → re-classify and apply C4996 fix → CI still fails with a fourth pattern not in `known-fixes.md` → `halt_condition` matches (unknown class) → skill exits per `on_halt` (escalate to user with diagnosis).

## Time Budget

Per invocation: **20 minutes** wall-clock from classification to a green re-run. Break down:

- Classification + diff: ~2 minutes
- Push + workflow dispatch + queue wait: ~3 minutes
- CI run itself: up to 10 minutes for typical matrices
- One retry slot: ~5 minutes

If total elapsed exceeds 20 minutes, stop, report status, and hand off.

## References

- Pattern catalogue and diffs: `reference/known-fixes.md`
- CMake FetchContent macro expansion: `reference/cmake-fetchcontent.md`
- MSVC C4996 migration guidance: `reference/msvc-c4996.md`
- Invoked from: `global/skills/pr-work/SKILL.md` on failing-CI escalation
