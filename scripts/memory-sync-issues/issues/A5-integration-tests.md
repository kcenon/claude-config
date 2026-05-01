---
title: "test(memory): integration tests for validate/secret/injection tools"
labels:
  - type/test
  - priority/medium
  - area/memory
  - size/M
  - phase/A-validation
milestone: memory-sync-v1-validation
blocked_by: [A2, A3, A4]
blocks: [B1, C1, C2]
parent_epic: EPIC
---

## What

Build integration tests that exercise the three validators (#A2, #A3, #A4) against synthetic fixture files plus the 17 real baseline files. A dedicated test runner produces a pass/fail summary suitable for CI invocation.

### Scope (in)

- Fixture set: 5 valid samples (one per type or scenario) + 5 invalid samples per validator
- Synthetic positive secret samples (5 categories) and injection samples (7 categories)
- Real baseline regression: 17 existing memory files must produce documented verdicts
- Single test runner script that runs all three validators across the fixture set
- Bash 3.2 (macOS) and bash 5.x (Linux) compatibility tests

### Scope (out)

- Unit tests for individual validator functions (validators are bash scripts; integration-only is acceptable for v1)
- Performance benchmarks (separate concern)
- Automated test against future memory files added post-v1

## Why

Without an automated test set, every change to the three validators risks silent regression. The 17 baseline files alone are insufficient — they test the happy path for the corrected spec, but not failure modes. Synthetic fixtures fill the gap.

### What this unblocks

- #B1 — confidence to define trust-tier semantics on validated memory
- #C2 — index generator can rely on validators being correct
- #C3 — pre-commit hook can rely on validators being correct
- #C5 — GitHub Actions workflow runs this test runner

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: medium — important but not on the critical path until #C3
- **Estimate**: 1 day
- **Target close**: within 1 week of #A4 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree** (final): `kcenon/claude-memory/tests/` after #C1
- **Work tree** (interim): `kcenon/claude-config/tests/memory/`
- **Test runner**: `tests/run-validation-tests.sh`
- **Fixtures**: `tests/fixtures/{valid,invalid,secret-positive,injection-positive}/`

## How

### Approach

Mirror the structure of `claude-config/tests/hooks/` (existing test pattern in this codebase). Test runner discovers fixtures by directory convention and asserts validator output matches expectations declared in `*.expected` files.

### Detailed Design

**Directory layout**:
```
tests/
├── run-validation-tests.sh
├── fixtures/
│   ├── valid/            # validate.sh expects PASS
│   │   ├── user_simple.md
│   │   ├── feedback_with_why.md
│   │   ├── project_with_how.md
│   │   ├── reference_external.md
│   │   └── all_phase2_fields.md
│   ├── invalid-validate/ # validate.sh expects exit 1, 2, or 3 per *.expected
│   │   ├── missing_frontmatter.md  + .expected (exit:1)
│   │   ├── missing_close_delim.md  + .expected (exit:1)
│   │   ├── name_too_long.md        + .expected (exit:2)
│   │   ├── type_invalid.md         + .expected (exit:2)
│   │   ├── body_too_short.md       + .expected (exit:1)
│   │   └── feedback_without_why.md + .expected (exit:3)
│   ├── secret-positive/  # secret-check.sh expects exit 1
│   │   ├── github_token.md
│   │   ├── aws_key.md
│   │   ├── openai_token.md
│   │   ├── private_ip.md
│   │   ├── foreign_home.md
│   │   ├── ssh_fingerprint.md
│   │   └── pem_block.md
│   ├── injection-positive/ # injection-check.sh expects exit 3
│   │   ├── direct_phrase.md
│   │   ├── system_marker.md
│   │   ├── persona_override.md
│   │   ├── destructive_code.md
│   │   ├── auto_fetch.md
│   │   ├── encoded_payload.md
│   │   └── absolute_density.md
│   └── baseline/         # symlink or copy of the 17 real memories
│       └── (17 files)
```

**Test runner flow**:
1. Iterate `fixtures/valid/*.md` → run validate.sh, expect exit 0
2. Iterate `fixtures/invalid-validate/*.md` → run validate.sh, parse `.expected` for exit code, assert match
3. Iterate `fixtures/secret-positive/*.md` → run secret-check.sh, expect exit 1
4. Iterate `fixtures/injection-positive/*.md` → run injection-check.sh, expect exit 3
5. Run all three validators against `fixtures/baseline/` → assert exact verdict counts (1 PASS, 17 WARN; 18 CLEAN; 14 CLEAN, 3 FLAGGED)
6. Print summary: `Total: N pass, N fail`
7. Exit 0 only if all assertions pass

**`.expected` file format**:
```
exit:1
contains:missing closing frontmatter delimiter
```
Two simple keys for v1 (exit code + substring match).

**Data structures**:
- `pass_count`, `fail_count` integers
- `failures[]` array of `<fixture>:<reason>` strings

**State and side effects**:
- Read-only on inputs
- Stdout: per-test result + summary
- No temp files
- Returns 0 if all pass, 1 otherwise

**External dependencies**: bash 3.2+, the three validators on PATH or via `--validators-dir`.

### Inputs and Outputs

**Input** (default):
```
$ ./tests/run-validation-tests.sh
```

**Output** (all pass):
```
[PASS] valid/user_simple.md
[PASS] valid/feedback_with_why.md
...
[PASS] invalid-validate/missing_frontmatter.md (exit 1, contains 'missing opening')
...
[PASS] secret-positive/github_token.md (exit 1)
...
[PASS] injection-positive/direct_phrase.md (exit 3)
...
[PASS] baseline regression: validate.sh 1+17+0
[PASS] baseline regression: secret-check.sh 18+0
[PASS] baseline regression: injection-check.sh 14+3

Total: 36 pass, 0 fail
```
Exit code: `0`

**Output** (one fail):
```
...
[FAIL] invalid-validate/name_too_long.md (expected exit 2, got 0)
...

Total: 35 pass, 1 fail

Failures:
  invalid-validate/name_too_long.md: expected exit 2, got 0
```
Exit code: `1`

**Input** (with custom validators dir):
```
$ ./tests/run-validation-tests.sh --validators-dir /tmp/claude/memory-validation/scripts
```

**Input** (CI invocation):
```
$ ./tests/run-validation-tests.sh && echo OK
```

### Edge Cases

- **Fixture file with no `.expected` companion** → test runner uses default expectation (exit 0 for valid/, derived from directory name otherwise)
- **Fixture filename containing spaces** → not supported in v1; runner rejects
- **Symlink loop in fixtures/** → `find` fails; runner exits 1 with diagnostic
- **Validator script missing or non-executable** → runner reports per-test "validator not found"
- **Bash 3.2 vs 5.x output difference** → if any divergence, runner flags and treats as failure
- **Real baseline file replaced/modified** → baseline-regression assertion fails; signals memory data changed (intentional or not)
- **`.expected` with malformed key** → ignored (forward-compatible); print warning
- **Empty fixture directory** → runner prints "no tests in <dir>" and continues (not a failure)
- **`fixtures/baseline/` missing** → baseline regression skipped with warning, runner exits 1 (mandatory in CI)
- **CI runner without macOS** → bash 3.2 tests skipped if `/bin/bash --version` reports 5.x (note: GitHub Actions macOS runners ship with bash 3.2 in `/bin/bash`)

### Acceptance Criteria

- [ ] Test runner script `tests/run-validation-tests.sh` (executable)
- [ ] **Fixture coverage**
  - [ ] 5 valid fixtures (one per common scenario)
  - [ ] 6 invalid-validate fixtures with `.expected` companion files
  - [ ] 7 secret-positive fixtures (one per category)
  - [ ] 7 injection-positive fixtures (one per category)
  - [ ] baseline/ contains the 17 real memory files (copy or symlink)
- [ ] **Assertions executed**
  - [ ] valid/ → all return exit 0 from validate.sh
  - [ ] invalid-validate/ → exit code matches `.expected:exit:N`, output contains `.expected:contains:STRING`
  - [ ] secret-positive/ → all return exit 1 from secret-check.sh
  - [ ] injection-positive/ → all return exit 3 from injection-check.sh
  - [ ] baseline regression: validate.sh produces 1 PASS + 17 WARN + 0 FAIL
  - [ ] baseline regression: secret-check.sh produces 18 CLEAN + 0 findings
  - [ ] baseline regression: injection-check.sh produces 14 CLEAN + 3 FLAGGED (exact match on the 3 known files)
- [ ] Summary line: `Total: N pass, N fail`
- [ ] Exit 0 only if all assertions pass
- [ ] `--validators-dir <path>` overrides validator location
- [ ] **Bash 3.2** (macOS default) and **bash 5.x** (Linux) both pass
- [ ] Runs in < 5 seconds on baseline fixture set
- [ ] Help text on `--help`

### Test Plan

- Manually break one validator (introduce a bug); confirm runner detects it
- Run on macOS bash 3.2 and Linux bash 5.x
- Run twice → byte-identical output
- Add a new fixture, runner discovers and tests it without code changes (directory-driven)

### Implementation Notes

- Existing test pattern in `claude-config/tests/hooks/test-runner.sh` is the model — follow same conventions (output format, `.expected` file convention)
- Avoid `set -e` in the test runner — failures should accumulate, not abort
- Use `bash --version` to check minimum version; warn if < 3.2
- Fixtures should be **minimal** — each fixture isolates exactly one rule. A 50-line fixture testing 3 rules is harder to debug than 3 separate fixtures
- `.expected` parsing: `grep '^key:' file | head -1 | cut -d: -f2-` keeps it bash-3.2-friendly
- For injection-positive fixtures, ensure the absolute-command-density test fixture has at least 3 occurrences of distinct keywords (not 3 copies of "always") so it tests the count not the deduplication

### Deliverable

- `tests/run-validation-tests.sh` (executable)
- `tests/fixtures/` directory tree with all fixtures + `.expected` files
- Symlink or copy mechanism for `fixtures/baseline/` (document choice)
- PR linked to this issue

### Breaking Changes

None.

### Rollback Plan

Revert PR.

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #A2, #A3, #A4
- Blocks: #B1, #C2
- Related: #C5 (CI workflow consumes this runner)

**Docs**:
- Spec: `docs/MEMORY_VALIDATION_SPEC.md` (defines expected verdicts)
- Baseline report: `/tmp/claude/memory-validation/baseline/REPORT.md`

**Commits/PRs**: (filled at PR time)

**Reference pattern**: `claude-config/tests/hooks/test-runner.sh`
