# Baseline Fixtures

This directory is intentionally empty in the repository tree. The "baseline
regression" assertion in `tests/memory/run-validation-tests.sh` exercises the
17 real memory files described in
[`docs/MEMORY_VALIDATION_SPEC.md`](../../../docs/MEMORY_VALIDATION_SPEC.md)
section 9. Those files live in the owner's per-machine memory directory:

```
~/.claude/projects/-Users-raphaelshin-Sources/memory/
```

They are not portable across machines (paths and contents are owner-specific),
so they are not committed here. The runner therefore **skips** the baseline
regression block when this directory contains no `*.md` files. Skipping is not
counted as a failure.

## Optional: populate the directory locally

To exercise the baseline regression assertion on the owner's machine, copy or
symlink the 17 files plus `MEMORY.md` into this directory:

```bash
cp ~/.claude/projects/-Users-raphaelshin-Sources/memory/*.md \
   tests/memory/fixtures/baseline/
```

Or symlink each file (preserves a single source of truth):

```bash
for f in ~/.claude/projects/-Users-raphaelshin-Sources/memory/*.md; do
  ln -sf "$f" tests/memory/fixtures/baseline/
done
```

Re-run the test runner:

```bash
bash tests/memory/run-validation-tests.sh
```

The assertion passes when the summary output of each validator matches the
verdicts documented in spec section 9:

- `validate.sh --all`        : `0 pass, 17 warn, 0 fail`
- `secret-check.sh --all`    : `18 clean, 0 with findings`
- `injection-check.sh --all` : `14 clean, 3 flagged`

## Why not commit copies?

- The 17 files contain identifying information from the owner's setup that
  would otherwise be redacted. Committing copies would either leak that
  information or require manual scrubbing that drifts from the spec.
- Issue #515 plans to migrate the canonical baseline to the
  `kcenon/claude-memory` repository. After that move, this directory may be
  removed entirely.

## .gitignore

The `.gitignore` in this directory ignores every file except `README.md` so
local copies of the baseline never get committed by accident.
