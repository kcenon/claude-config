# Skill Testing Checklist

> **Loading**: Excluded from default context via `.claudeignore`. Load with `@load: reference/skill-testing`.
> **Full methodology**: For comprehensive testing with automated grading, see the `/harness` skill.

## Quick Testing Checklist

- [ ] Description triggers correctly on intended queries
- [ ] Description does NOT trigger on near-miss queries
- [ ] SKILL.md body is under 500 lines
- [ ] Reference files are wired up (not orphaned)
- [ ] Output quality is measurably better with skill than without

## 1. Trigger Verification

### Should-Trigger Queries (8-10)
Create diverse phrasings of your skill's intended use:
- Formal and casual language
- Explicit and implicit requests
- Simple and complex scenarios
- Domain-specific terminology

### Should-NOT-Trigger Queries (8-10)
Create **near-miss** boundary cases — similar keywords but different intent:
- These are the real test value (not obviously unrelated queries)
- Example: For an xlsx-skill, a near-miss is "convert Excel chart to PNG" (image-conversion, not xlsx)

### Conflict Detection
Check if your skill's trigger queries also activate existing skills unintentionally.

## 2. Assertion Writing Guidelines

Good assertions are:
- **Objectively verifiable** (true/false, not subjective quality)
- **Descriptive** (clear name explaining what's tested)
- **Core value** (tests what the skill uniquely provides)

Avoid assertions that:
- Always pass with or without the skill (no discriminative power)
- Test subjective qualities (text style, design taste)
- Test trivial aspects unrelated to skill purpose

### Assertion Structure

```json
{
  "expectations": [
    {
      "text": "Output contains sorted data in descending order",
      "passed": true,
      "evidence": "Column B sorted: 100, 95, 87, 72, 65"
    }
  ],
  "summary": {
    "passed": 1,
    "failed": 0,
    "total": 1,
    "pass_rate": 1.0
  }
}
```

## 3. With-Skill vs Without-Skill Comparison

For each test prompt, run two parallel evaluations:

| Run | Skill Loaded | Output Directory |
|-----|-------------|-----------------|
| With-skill | Yes | `_workspace/iteration-N/eval-{id}/with_skill/outputs/` |
| Without-skill (baseline) | No | `_workspace/iteration-N/eval-{id}/without_skill/outputs/` |

Capture `total_tokens` and `duration_ms` immediately upon completion (not recoverable later).

Compare results using assertions. The skill should measurably outperform baseline.

## 4. Test Workspace Structure

```
_workspace/
  iteration-N/
    eval-{id}/
      eval_metadata.json    # Test prompt + assertions
      with_skill/
        outputs/             # Skill-assisted output
        grading.json         # Assertion results
      without_skill/
        outputs/             # Baseline output
        grading.json         # Assertion results
```

### eval_metadata.json
```json
{
  "eval_id": 0,
  "eval_name": "descriptive-test-name",
  "prompt": "realistic user prompt for this test",
  "assertions": [
    "output contains X",
    "file created in Y format"
  ]
}
```

## 5. Iterative Improvement

1. Write skill + create 2-3 test prompts
2. Run with-skill vs baseline in parallel
3. Evaluate with assertions + user review
4. Feedback: generalize fixes (avoid overfitting to specific test cases)
5. Create new `iteration-N+1/` directory
6. Re-test until: user satisfied OR no meaningful improvement remains

---

*Reference document for skill testing methodology. Version 1.0.0*
