# sonar-fix fixtures

Reproduction fixtures for each whitelisted SonarQube rule codified in
`global/skills/_internal/sonar-fix/reference/auto-fixable-rules.md`.

Each rule has a `<rule_id>_before.<ext>` (input as it would arrive on a
PR) and a `<rule_id>_after.<ext>` (expected file state after sonar-fix
applies the codified fix). The before/after pair mirrors the Before/After
code block of the corresponding Pattern entry so the documented fix and
the test fixture cannot drift apart silently.

| Rule  | Before                | After                |
|-------|-----------------------|----------------------|
| S1481 | `S1481_before.py`     | `S1481_after.py`     |
| S1128 | `S1128_before.py`     | `S1128_after.py`     |
| S1854 | `S1854_before.py`     | `S1854_after.py`     |
| S1192 | `S1192_before.py`     | `S1192_after.py`     |
| S125  | `S125_before.py`      | `S125_after.py`      |
| S1116 | `S1116_before.c`      | `S1116_after.c`      |

## Validation

The driver script `test-fixtures.sh` enforces two invariants for every
rule:

1. The fixture's `<rule>_after.<ext>` file matches, byte-for-byte, the
   "After" code block in the Pattern entry of
   `auto-fixable-rules.md` (after stripping the surrounding fence).
2. The fixture's `<rule>_before.<ext>` file matches the "Before" code
   block of the same Pattern entry under the same rules.

Both files exist on disk so a future automated fix engine can read the
"Before" fixture, apply the codified transformation, and assert that
the result is byte-identical to the "After" fixture.

Run the driver from the repository root:

```bash
bash tests/sonar-fix/test-fixtures.sh
```

The driver exits non-zero whenever a Pattern entry's Before/After block
is edited without the matching fixture being updated (or vice versa).
For now the gate is manual — wiring the driver into
`.github/workflows/validate-skills.yml` is deferred to a follow-up PR
because the OAuth app creating this directory does not have the
`workflow` scope. Reviewers should run the driver locally as part of
PR review until that wiring lands.

## Extending

When adding a new rule to the whitelist:

1. Append a Pattern entry to `auto-fixable-rules.md` following the
   six-heading layout (Classifier / Root cause / Before / After /
   Verify / Safety).
2. Add `<rule>_before.<ext>` and `<rule>_after.<ext>` files to this
   directory whose contents match the Before/After code blocks
   verbatim.
3. Append a row to the table above and to the `RULES` array in
   `test-fixtures.sh`.

The driver auto-discovers any rule listed in its `RULES` array. Once
the follow-up PR wires `test-fixtures.sh` into the
`validate-skills.yml` workflow, no further CI wiring is required for
subsequent rule additions.
