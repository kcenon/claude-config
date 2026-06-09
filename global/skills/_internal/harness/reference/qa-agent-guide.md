# QA Agent Design Guide

A guide for including QA agents in build harnesses. Based on bug patterns discovered in a real project (SatangSlide) and their root cause analysis, this guide provides a systematic verification methodology for catching defects that QA commonly misses.

---

## Table of Contents

1. [Defect Patterns QA Agents Miss](#1-defect-patterns-qa-agents-miss)
2. [Integration Coherence Verification](#2-integration-coherence-verification)
3. [QA Agent Design Principles](#3-qa-agent-design-principles)
4. [Verification Checklist Template](#4-verification-checklist-template)
5. [QA Agent Definition Template](#5-qa-agent-definition-template)
6. [Real-world Case Study: 7 Bug Examples](#6-real-world-case-study-7-bug-examples)

---

## 1. Defect Patterns QA Agents Miss

### 1-1. Boundary Mismatch

The most frequent defect type. Two components are each "correctly" implemented individually, but the contract breaks at the connection point.

| Boundary | Mismatch example | Why it's missed |
|----------|-----------------|-----------------|
| API response -> front-end hook | API returns `{ projects: [...] }`, hook expects `SlideProject[]` | Each passes individual verification; no cross-comparison done |
| API response field name -> type definition | API uses `thumbnailUrl` (camelCase), type defines `thumbnail_url` (snake_case) | TypeScript generic casting bypasses the compiler |
| File path -> link href | Page lives at `/dashboard/create` but link points to `/create` | File structure and href are not cross-compared |
| State transition map -> actual status update | Map defines `generating_template -> template_approved`, code omits the transition | Only checks map existence, doesn't trace all update code |
| API endpoint -> front-end hook | API exists but no corresponding hook (never called) | API list and hook list are not 1:1 mapped |
| Immediate response -> async result | API immediately returns `{ status }`, front-end accesses `data.failedIndices` | Sync/async response distinction not verified in types |

### 1-2. Why Static Code Review Can't Catch These

- **TypeScript generic limitations**: `fetchJson<SlideProject[]>()` -- even if the runtime response is `{ projects: [...] }`, compilation passes.
- **`npm run build` passing does not equal correct behavior**: with type casting, `any`, and generics, the build succeeds but runtime fails.
- **Existence verification vs connection verification**: "Does the API exist?" and "Does the API response match the caller's expectations?" are entirely different verifications.

---

## 2. Integration Coherence Verification

**Cross-comparison verification** areas that must be included in every QA agent.

### 2-1. API Response <-> Front-end Hook Type Cross-verification

**Method**: Compare the shape of objects passed to `NextResponse.json()` in each API route with the `fetchJson<T>` type parameter in the corresponding hook.

```
Verification steps:
1. Extract the object shape passed to NextResponse.json() in the API route
2. Check the T type in fetchJson<T> of the corresponding hook
3. Compare whether the shape matches T
4. Check wrapping: if API returns { data: [...] }, does the hook unwrap via .data?
```

**Watch especially for:**
- Pagination APIs: `{ items: [], total, page }` vs front-end expecting a plain array
- snake_case DB fields -> camelCase API response -> front-end type definition mismatches
- Immediate response (202 Accepted) vs final result shape differences

### 2-2. File Path <-> Link/Router Path Mapping

**Method**: Extract URL paths from page files under `src/app/`, then cross-check against all `href`, `router.push()`, and `redirect()` values in the code.

```
Verification steps:
1. Extract URL patterns from page.tsx file paths under src/app/
   - (group) -> removed from URL
   - [param] -> dynamic segment
2. Collect all href=, router.push(, redirect( values in code
3. Confirm each link matches an actually existing page path
4. Watch URL prefixes for pages inside route groups (e.g., under dashboard/)
```

### 2-3. State Transition Completeness Tracking

**Method**: Extract all `status:` updates from code and cross-check against the state transition map.

```
Verification steps:
1. Extract the allowed transition list from the state transition map (STATE_TRANSITIONS)
2. Search all API routes for .update({ status: "..." }) patterns
3. Confirm each transition is defined in the map
4. Identify transitions defined in the map but never executed in code (dead transitions)
5. Especially: verify that transitions from intermediate states (e.g., generating_template)
   to final states (template_approved) are not missing
```

### 2-4. API Endpoint <-> Front-end Hook 1:1 Mapping

**Method**: List all API routes and front-end hooks to check for matching pairs.

```
Verification steps:
1. Extract endpoint list by HTTP method from route.ts files under src/app/api/
2. Extract fetch call URL list from use*.ts files under src/hooks/
3. Identify API endpoints not called by any hook -> flag as "unused"
4. Determine whether "unused" is intentional (admin APIs, etc.) or a call omission
```

---

## 3. QA Agent Design Principles

### 3-1. Use general-purpose Type, Not Explore

If the QA agent is `Explore` type, it can only read. But effective QA requires:
- Pattern searching with Grep (extracting all `NextResponse.json()` calls)
- Running scripts for automated cross-checks (API shape vs hook types)
- Optionally fixing issues directly

**Recommendation**: Set as `general-purpose` type, but specify a "verify -> report -> request fix" protocol in the agent definition.

### 3-2. Prioritize "Cross-comparison" Over "Existence Checking"

| Weak checklist | Strong checklist |
|---------------|-----------------|
| Does the API endpoint exist? | Does the API endpoint's response shape match the corresponding hook's type? |
| Is the state transition map defined? | Do all status update code paths match the map's transitions? |
| Does the page file exist? | Do all links in the code point to actually existing pages? |
| Is TypeScript strict mode on? | Are there type safety bypasses via generic casting? |

### 3-3. The "Read Both Sides Simultaneously" Principle

For QA to catch boundary bugs, reading only one side is insufficient. Always:
- Read the API route **and** the corresponding hook **together**
- Read the state transition map **and** the actual update code **together**
- Read the file structure **and** link paths **together**

Explicitly state this principle in the agent definition.

### 3-4. Run QA After Each Module, Not Just After Everything Is Complete

Placing QA only at "Phase 4: After full completion" in the orchestrator leads to:
- Bug accumulation, making fixes expensive
- Early boundary mismatches propagating to subsequent modules

**Recommended pattern**: Run cross-verification on each backend API + corresponding hook immediately after API completion (incremental QA).

---

## 4. Verification Checklist Template

Integration coherence checklist for web applications, to include in QA agent definitions.

```markdown
### Integration Coherence Verification (Web App)

#### API <-> Front-end Connection
- [ ] All API route response shapes match corresponding hook generic types
- [ ] Wrapped responses ({ items: [...] }) are unwrapped in hooks
- [ ] snake_case <-> camelCase conversion is applied consistently
- [ ] Immediate responses (202) and final results have distinguishable shapes in the front-end
- [ ] All API endpoints have corresponding front-end hooks that are actually called

#### Routing Coherence
- [ ] All href/router.push values in code match actual page file paths
- [ ] Route groups ((group)) being removed from URLs is accounted for in path verification
- [ ] Dynamic segments ([id]) are filled with correct parameters

#### State Machine Coherence
- [ ] All defined state transitions are executed in code (no dead transitions)
- [ ] All status updates in code are defined in the transition map (no unauthorized transitions)
- [ ] Transitions from intermediate states to final states are not missing
- [ ] State-based branching in front-end (if status === "X") -- X is actually reachable

#### Data Flow Coherence
- [ ] DB schema field names and API response field names are consistently mapped
- [ ] Front-end type definitions and API response field names match
- [ ] null/undefined handling for optional fields is consistent on both sides
```

---

## 5. QA Agent Definition Template

Core sections to include in the QA agent for a build harness.

```markdown
---
name: qa-inspector
description: "QA verification specialist. Verifies spec compliance, integration coherence, and design quality."
---

# QA Inspector

## Core Role
Verify implementation quality against specs and **integration coherence between modules**.

## Verification Priority

1. **Integration coherence** (highest) -- boundary mismatches are the primary cause of runtime errors
2. **Functional spec compliance** -- API/state machine/data model
3. **Design quality** -- colors/typography/responsiveness
4. **Code quality** -- unused code, naming conventions

## Verification Method: "Read Both Sides Simultaneously"

For boundary verification, always **open both sides of the code simultaneously** and compare:

| Verification target | Left side (producer) | Right side (consumer) |
|--------------------|--------------------|---------------------|
| API response shape | route.ts NextResponse.json() | hooks/ fetchJson<T> |
| Routing | src/app/ page file paths | href, router.push values |
| State transitions | STATE_TRANSITIONS map | .update({ status }) code |
| DB -> API -> UI | Table column names | API response fields -> type definitions |

## Team Communication Protocol

- Immediately notify the responsible agent with a specific fix request (file:line + fix method)
- For boundary issues, notify **both** sides' agents
- To leader: verification report (distinguish passed/failed/unverified items)
```

---

## 6. Real-world Case Study: 7 Bug Examples

All content in this guide is derived from lessons learned from these actual bugs:

| Bug | Boundary | Root cause |
|-----|----------|-----------|
| `projects?.filter is not a function` | API -> hook | API returns `{projects:[]}`, hook expects a plain array |
| All dashboard links return 404 | File path -> href | `/dashboard/` prefix missing from links |
| Theme images not visible | API -> component | `thumbnailUrl` vs `thumbnail_url` field name mismatch |
| Theme selection not saved | API -> hook | select-theme API exists but no corresponding hook |
| Generation page waits forever | State transition -> code | `template_approved` transition code missing |
| `data.failedIndices` crash | Immediate response -> front-end | Accessing background job result in the immediate response |
| "View slides" after completion returns 404 | File path -> href | `/projects/` should be `/dashboard/projects/` |
