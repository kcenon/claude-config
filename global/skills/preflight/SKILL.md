---
name: preflight
description: "Reproduce CI checks locally before pushing so failures surface on the developer machine, not on GitHub. Aligns with the ci-fix skill's pattern catalogue and catches MSVC C4996, CMake FetchContent shallow-clone, and deprecated-API issues pre-push. Invoke manually with /preflight or automatically via CLAUDE_PREFLIGHT=1 in the pre-push hook."
argument-hint: "[--only <check>] [--skip <check>] [--verbose]"
user-invocable: true
disable-model-invocation: false
allowed-tools: "Bash(act *),Bash(docker *),Bash(cmake *)"
loop_safe: true
halt_conditions:
  - { type: success, expr: "all selected preflight checks complete with non-zero failures = 0" }
  - { type: failure, expr: "any selected check reports failure or its runner errors out" }
on_halt: "Print per-check summary table and exit non-zero if any check failed"
---

# preflight Skill

Reproduce the green-CI contract on the developer machine. Pairs with `ci-fix` — same pattern
library, opposite direction: `ci-fix` reacts, `preflight` prevents.

## Usage

```
/preflight                         # Run all available checks in sequence
/preflight --only deprecated-api   # Run a single named check
/preflight --skip msvc-docker      # Run all checks except one
/preflight --verbose               # Print each check's full stdout/stderr
```

```bash
# Non-interactive: pre-push hook invocation
CLAUDE_PREFLIGHT=1 git push origin <branch>
```

## Checks

| Id | Purpose | Tool requirement | Skipped if tool absent? |
|----|---------|------------------|-------------------------|
| `cmake-configure` | Configure with `-Werror`-equivalents to catch deprecation warnings early | `cmake` on PATH | Yes |
| `deprecated-api` | `grep` for the deprecated-API set shared with `ci-fix/reference/known-fixes.md` | POSIX `grep` | No (always runs) |
| `act-linux` | `act` replay of Linux GitHub Actions jobs | `act` on PATH | Yes |
| `msvc-docker` | Docker run of an MSVC image to rebuild the Windows matrix leg | `docker` on PATH | Yes |

Each check is implemented in `scripts/` and returns a structured report to stdout. Exit code
`0` means the check either passed or was skipped due to a missing tool. Any non-zero exit
blocks the `pre-push` gate when `CLAUDE_PREFLIGHT=1`.

## Invocation Order

1. `deprecated-api` — cheap, always runs, catches low-hanging fruit.
2. `cmake-configure` — fast configure-only run; most project misconfigurations surface here.
3. `act-linux` — slower, runs the Linux matrix locally.
4. `msvc-docker` — slowest; only meaningful when the project has a Windows matrix leg.

Stop on first failure unless `--verbose` is set, in which case continue and print a per-check
report at the end.

## Opt-in `pre-push` Integration

The project-level `hooks/pre-push` hook invokes the skill only when the opt-in flag is set:

```bash
CLAUDE_PREFLIGHT=1 git push origin my-branch
```

Absent the env var, the hook preserves its current protected-branch behaviour. When set, the
hook calls `bash global/skills/preflight/scripts/run-all.sh`; any non-zero exit aborts the push
with a summary of the failing check.

To opt in persistently for a shell session:

```bash
export CLAUDE_PREFLIGHT=1
```

## Report Format

Each check script emits a single JSON line on stdout:

```json
{"check":"deprecated-api","status":"pass","duration_ms":123,"findings":0}
{"check":"msvc-docker","status":"skip","reason":"docker not on PATH"}
{"check":"cmake-configure","status":"fail","duration_ms":4210,"evidence":"/tmp/preflight-cmake-4321.log"}
```

`status` is one of `pass`, `fail`, or `skip`. `evidence` is a path to the captured log when
the check fails.

## Shared Pattern Library

Deprecated-API patterns live in `global/skills/ci-fix/reference/known-fixes.md` (the ci-fix
skill's catalogue). `scripts/run-deprecated-api.sh` reads a generated pattern file at
`/tmp/preflight-patterns.txt` that is derived from the ci-fix catalogue on first invocation.
This keeps ci-fix as the single source of truth and avoids drift between the two skills.

## Escalation

| Condition | Action |
|-----------|--------|
| A check fails | Emit JSON report with `evidence` path; exit non-zero. |
| All required tools missing | Print `"no runnable checks on this host"` and exit 0 (informational). |
| Shared pattern file is stale (older than ci-fix/reference) | Regenerate, then run. |

## References

- Pattern catalogue and diagnostic diffs: `global/skills/ci-fix/reference/known-fixes.md`
- MSVC C4996 migration: `global/skills/ci-fix/reference/msvc-c4996.md`
- CMake FetchContent deep-dive: `global/skills/ci-fix/reference/cmake-fetchcontent.md`
- `act` (nektos/act): <https://github.com/nektos/act>
