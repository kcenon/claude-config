---
alwaysApply: true
---

# Question Handling Procedure

> **Version**: 1.2.0
> **Extracted from**: workflow.md
> **Purpose**: Defines the standard procedure for processing user questions

## 1. Translate

- **Internal processing**: Translate the user's question into English internally for comprehensive understanding
- **Display translation**: Show the English translation to the user at the beginning of the response
- **Context preservation**: Maintain the original question's context and nuances during translation

## 2. Analyze

- **Task breakdown**: Decompose the problem into clear, manageable tasks
- **Identify assumptions**: Explicitly state any assumptions being made
- **Highlight constraints**: Note technical, time, or resource constraints
- **Missing information**: Call out any information gaps that could affect the solution

## 3. Present

- **Share analysis**: Present your understanding and planned approach to the user before proceeding
- **Encourage feedback**: Invite the user to correct misunderstandings or provide clarifications
- **Confirm direction**: Wait for user approval on complex or ambiguous tasks before implementation

## 4. Execute

- **Transform to verifiable goals**: Reframe requests as testable outcomes before coding

  | Request | Verifiable Goal |
  |---------|----------------|
  | "Add validation" | "Tests for invalid inputs all pass" |
  | "Improve performance" | "Benchmark shows measurable improvement" |
  | "Refactor X" | "Existing tests pass with no behavior change" |

- **Work incrementally**: Make small, reversible changes — verify each before proceeding
- **Communicate blockers**: Report unexpected issues before attempting workarounds

## 5. Verify

For multi-step tasks, define a verification plan:

```
1. [Step] → verify: [expected outcome]
2. [Step] → verify: [expected outcome]
```

- **Check against goals**: Compare outcomes to verifiable goals from step 4
- **Loop on failure**: If verification fails, diagnose, adjust, and re-execute

---
*Part of the workflow guidelines module*
