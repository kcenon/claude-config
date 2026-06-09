# PR Comment Templates and Guidelines

Templates for CI/CD failure analysis comments posted to pull requests, including initial analysis, follow-up iterations, and escalation comments.

---

## Initial Failure Analysis Comment (Step 3)

**MANDATORY**: After analyzing failures, post a comment to the PR documenting the analysis.

**IMPORTANT**: PR comments must comply with the active `CLAUDE_CONTENT_LANGUAGE` policy resolved from `commit-settings.md` (default `english`; other values: `korean_plus_english`, `exclusive_bilingual`, `any`). Do not hard-code "English only" — under `exclusive_bilingual` a Korean-only comment is valid.

```bash
gh pr comment $PR_NUMBER --repo $ORG/$PROJECT --body "$(cat <<'EOF'
## CI/CD Failure Analysis

**Analysis Time**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Attempt**: #[ATTEMPT_NUMBER]

### Failed Workflows

| Workflow | Job | Step | Status |
|----------|-----|------|--------|
| [workflow-name] | [job-name] | [step-name] | Failed |

### Root Cause Analysis

**Primary Error**:
```
[Extract key error message here]
```

**Analysis**:
[Brief explanation of why this error occurred]

**Identified Issues**:
1. [Issue 1 description]
2. [Issue 2 description]

### Proposed Fix

| Issue | Proposed Solution | Files Affected |
|-------|-------------------|----------------|
| [Issue 1] | [Solution description] | `path/to/file.ext` |

### Next Steps
- [ ] Apply proposed fixes
- [ ] Verify locally
- [ ] Push and monitor CI

---
*Automated failure analysis - Attempt #[ATTEMPT_NUMBER]*
EOF
)"
```

### Comment Guidelines

| Item | Requirement |
|------|-------------|
| **Language** | Comply with the active `CLAUDE_CONTENT_LANGUAGE` policy (see `commit-settings.md`). Per-artifact rule applies: under `exclusive_bilingual`, each comment must be wholly English-only or wholly Korean-only. |
| Timing | Immediately after failure analysis, before attempting fix |
| Content | Include actual error messages (sanitized if needed) |
| Format | Use tables and code blocks for readability |
| Updates | Edit existing comment or add new comment per attempt |

### Sensitive Data Handling

Before posting, sanitize the following from error logs:
- API keys and secrets
- Internal hostnames/IPs
- Personal identifiable information (PII)
- Database connection strings

---

## Follow-up Attempt Comment (Step 9)

For subsequent attempts, update the PR with a follow-up comment:

**IMPORTANT**: Comment language follows the active `CLAUDE_CONTENT_LANGUAGE` policy (see `commit-settings.md`).

```bash
gh pr comment $PR_NUMBER --repo $ORG/$PROJECT --body "$(cat <<'EOF'
## CI/CD Failure Analysis - Attempt #[N]

**Previous Attempt Result**: [Passed/Failed]
**Previous Fix Applied**: [Brief description of what was fixed]

### New Failure Analysis

| Workflow | Job | Step | Previous Status | Current Status |
|----------|-----|------|-----------------|----------------|
| [workflow-name] | [job-name] | [step-name] | Fixed | New Failure |

### What Changed

**Previous Fix**:
- [What was fixed in the previous attempt]

**Why It Still Fails**:
- [Analysis of why the previous fix didn't fully resolve the issue]

### New Root Cause

**Error**:
```
[New error message]
```

**Analysis**:
[Updated analysis based on new information]

### Updated Proposed Fix

| Issue | Proposed Solution | Files Affected |
|-------|-------------------|----------------|
| [Issue] | [Solution] | `path/to/file.ext` |

---
*Automated failure analysis - Attempt #[N] of 3*
EOF
)"
```

---

## Escalation Comment (Step 11)

When max retry attempts (3) are exceeded without success:

**IMPORTANT**: Escalation comment language follows the active `CLAUDE_CONTENT_LANGUAGE` policy (see `commit-settings.md`).

1. **Add summary comment to PR**:
   ```bash
   gh pr comment $PR_NUMBER --repo $ORG/$PROJECT --body "## Auto-fix Summary

   **Attempted fixes**: 3
   **Status**: Manual intervention required

   ### Attempted Fixes
   1. [commit-hash] fix description - Still failing
   2. [commit-hash] fix description - Still failing
   3. [commit-hash] fix description - Still failing

   ### Current Failures
   - Workflow: [workflow-name]
   - Error: [error-summary]

   Please review manually."
   ```

2. **Add label** (if available):
   ```bash
   gh pr edit $PR_NUMBER --repo $ORG/$PROJECT --add-label "needs-manual-review"
   ```

3. **Report final status** to user with detailed failure information

### Escalation Decision Matrix

| Attempt | Action |
|---------|--------|
| 1-2 | Auto-fix and retry |
| 3 | Final attempt with detailed logging |
| After max | Escalate to human review |
