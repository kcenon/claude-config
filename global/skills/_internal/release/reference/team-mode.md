# Team Mode Instructions

Three-team parallel workflow for release creation. This file contains the complete team mode architecture, setup, spawning, workflow phases, cleanup, and fallback procedures.

---

Three-team workflow for release creation. Dev team handles git operations, Review team validates changelog accuracy, Doc team formats release notes and documentation.

> **Requires**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json

## Team Architecture

```
         Lead (Coordinator)
         ┌──────────────┐
         │ Version check │
         │ Final publish │
         └──────┬───────┘
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
┌──────┐   ┌──────┐   ┌──────┐
│ Dev  │   │Review│   │ Doc  │
│ Team │◄──│ Team │   │ Team │
└──────┘   └──────┘   └──────┘
  dev     reviewer    doc-writer

  Dev: creates tag, manages git operations
  Reviewer: validates changelog accuracy and version correctness
  Doc-writer: formats release notes and updates CHANGELOG.md
```

## T-1. Setup (Lead executes)

Perform Solo Mode Steps 1-2 (Validate Version, Get Previous Tag).
Verify version format and collect commit range.

## T-2. Create Team and Tasks

```
TeamCreate(team_name="release-v$VERSION", description="Release v$VERSION for $ORG/$PROJECT")
```

| Task | Subject | Owner | blockedBy | Phase |
|------|---------|-------|-----------|-------|
| 1 | Generate raw changelog from commits | dev | — | A |
| 2 | Validate changelog accuracy and completeness | reviewer | 1 | B |
| 3 | Format release notes and update CHANGELOG.md | doc-writer | 1 | B |
| 4 | Apply changelog corrections (if reviewer has findings) | dev | 2 | C |
| 5 | Review formatted release notes | reviewer | 3 | C |
| 6 | Apply release notes corrections (if any) | doc-writer | 5 | D |
| 7 | Create git tag and push | dev | 2 or 4, 5 or 6 | E |
| 8 | Create GitHub release with final notes | lead | 7 | E |

## T-3. Spawn Teammates

**Dev Team** (git operations + changelog generation):

```
Agent(
  name="dev",
  team_name="release-v$VERSION",
  subagent_type="general-purpose",
  prompt="You are the dev team for release v$VERSION in $ORG/$PROJECT.

    Your responsibilities:
    1. Task 1: Generate raw changelog by categorizing commits since $PREVIOUS_TAG:
       - feat → Added, fix → Fixed, refactor/perf/style → Changed
       - docs → Documentation, test/chore/build/ci → Other
       Format: '- commit_message (short_hash)'
    2. Task 4: If reviewer reports inaccuracies in the changelog,
       correct the categorization or descriptions.
    3. Task 7: Create annotated git tag and push:
       git tag -a 'v$VERSION' -m 'Release v$VERSION'
       git push origin 'v$VERSION'

    Rules:
    - Commit format: chore(release): prepare v$VERSION (English only, no emojis)
    - Do NOT create tag until reviewer approves changelog

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Review Team** (changelog validation):

```
Agent(
  name="reviewer",
  team_name="release-v$VERSION",
  subagent_type="general-purpose",
  prompt="You are the review team for release v$VERSION in $ORG/$PROJECT.

    Your responsibilities:
    1. Task 2: Validate the raw changelog:
       - Are commits categorized correctly? (feat vs fix vs refactor)
       - Are breaking changes identified and highlighted?
       - Are all commits since $PREVIOUS_TAG included?
       - Is the version bump appropriate? (major for breaking, minor for feat, patch for fix)
       Report any inaccuracies to dev.
    2. Task 5: Review the formatted release notes from doc-writer:
       - Professional formatting?
       - Accurate content matching the validated changelog?
       - Breaking changes section if applicable?

    Feedback: Send corrections to dev (Task 4) or doc-writer (Task 6) as needed.
    Max 1 review round for changelog, 1 for release notes.

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

**Documentation Team** (release notes formatting):

```
Agent(
  name="doc-writer",
  team_name="release-v$VERSION",
  subagent_type="general-purpose",
  prompt="You are the documentation team for release v$VERSION in $ORG/$PROJECT.

    Your responsibilities:
    1. Task 3: Format the raw changelog into professional release notes:
       - Add version header with date: ## [VERSION] - YYYY-MM-DD
       - Group by category: Added, Fixed, Changed, Documentation, Other
       - Remove empty categories
       - Add migration notes if breaking changes exist
    2. Update CHANGELOG.md file with the new release section
    3. Task 6: If reviewer suggests corrections, apply them

    Rules:
    - Follow existing CHANGELOG.md format if present
    - Commit format: docs(release): update CHANGELOG for v$VERSION

    Check TaskList for your assigned tasks. Mark each as completed when done."
)
```

## T-4. Workflow Phases (Lead coordinates)

**Phase A — Changelog Generation:**
1. Dev generates raw changelog from git commits (Task 1)

**Phase B — Parallel Review + Formatting:**
1. Reviewer validates changelog accuracy (Task 2) ∥ Doc-writer formats release notes (Task 3)
2. These run in parallel — both depend on Task 1

**Phase C — Corrections (if needed):**
1. Dev applies changelog corrections from reviewer (Task 4)
2. Reviewer validates doc-writer's formatted notes (Task 5)

**Phase D — Final Adjustments:**
1. Doc-writer applies any corrections to release notes (Task 6)

**Phase E — Publish:**
1. Dev creates and pushes git tag (Task 7)
2. Lead creates GitHub release with final notes (Task 8):
   ```bash
   gh release create v$VERSION --repo $ORG/$PROJECT \
     --title "v$VERSION" --notes "$RELEASE_NOTES"
   ```

## T-5. Cleanup

```
SendMessage(to="dev", message={type: "shutdown_request"})
SendMessage(to="reviewer", message={type: "shutdown_request"})
SendMessage(to="doc-writer", message={type: "shutdown_request"})
TeamDelete()
```

## T-Error. Team Mode Fallback

If any teammate fails or team coordination breaks down:

1. Shutdown all teammates and delete team
2. If changelog was generated: offer to continue in Solo Mode from Step 5 (tag)
3. If nothing completed: offer full Solo restart
