---
title: "feat(memory): PreToolUse hook validates memory writes"
labels:
  - type/feature
  - priority/high
  - area/memory
  - size/M
  - phase/D-engine
milestone: memory-sync-v1-engine
blocked_by: [C5]
blocks: [E1]
parent_epic: EPIC
---

## What

Implement `global/hooks/memory-write-guard.sh` — a Claude Code PreToolUse hook for `Edit | Write` matchers. When the target path is under `~/.claude/memory-shared/memories/`, validates the proposed new content with `validate.sh` + `secret-check.sh`. Returns `permissionDecision: deny` on blocking failure. `injection-check.sh` warnings appended to `feedback` field but do not block.

### Scope (in)

- Single bash hook script following existing `claude-config/global/hooks/` conventions
- Activates only for write paths under `~/.claude/memory-shared/memories/`
- Validates proposed content (the would-be new file) before writing
- Blocks on `validate.sh` exit ≥ 1 or `secret-check.sh` exit 1
- Surfaces `injection-check.sh` flags as feedback (warning, not block)
- Performance target: < 500ms typical
- Registered in `global/settings.json` under PreToolUse Edit | Write matcher

### Scope (out)

- File-watching for non-tool writes (e.g., user opens editor and saves) — out of Claude Code's hook scope
- Validation of paths outside the memory tree (those have their own guards)
- Auto-quarantining files written that fail (Edit/Write would just be rejected)

## Why

A memory written by Claude (auto-memory) or user (Edit tool) bypasses pre-commit hooks until git commit time. **Catching at write time** has two benefits:

1. **Immediate feedback** — Claude sees the rejection and can self-correct in the same session, rather than leaking a bad memory until the next manual commit
2. **No "ghost memory" period** — between the bad write and the next commit, the file exists on disk and could influence the running session

Reusing the same validators ensures consistency: anything pre-commit blocks, write-guard also blocks (and vice versa).

### What this unblocks

- #E1 — migration runbook references this hook for write protection
- General defense layer 1 in the 5-layer model

## Who

- **Implementer**: @kcenon
- **Reviewer**: @kcenon

## When

- **Priority**: high
- **Estimate**: 1 day
- **Target close**: within 1 week of #C5 closing

## Where

- **Issue tracker**: `kcenon/claude-config`
- **Work tree**: `kcenon/claude-config/global/hooks/memory-write-guard.sh`
- **Settings update**: `kcenon/claude-config/global/settings.json` (add to PreToolUse Edit | Write matcher list)
- **PowerShell parallel**: `global/hooks/memory-write-guard.ps1` (Windows / claude-docker compatibility)

## How

### Approach

PreToolUse hook receives a JSON document describing the tool call. The hook extracts `tool_input.file_path` and (for Edit) `tool_input.new_string` or (for Write) `tool_input.content`. If the path is under `~/.claude/memory-shared/memories/`, the hook writes the proposed full content to a temp file and runs the validators against it. Returns JSON with `permissionDecision` field per the corrected spec from #A1.

Existing hook reference patterns: `claude-config/global/hooks/sensitive-file-guard.sh`, `pre-edit-read-guard.sh`. This hook follows the same call shape.

### Detailed Design

**Hook input** (JSON via stdin per Claude Code hook contract):
```json
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/Users/raphaelshin/.claude/memory-shared/memories/feedback_new.md",
    "content": "---\nname: ...\n---\n..."
  }
}
```

For `Edit`, the hook needs to **simulate** the post-edit content. It loads the current file (if exists), applies the `old_string → new_string` substitution, and validates the result. If `replace_all=true`, applies all occurrences.

**Hook output** (stdout JSON):
```json
{
  "permissionDecision": "allow|deny",
  "feedback": "<message shown to Claude / user>"
}
```

**Activation gate**:
```
- Read tool_input.file_path
- If not under "$HOME/.claude/memory-shared/memories/" → output {"permissionDecision":"allow"}, exit 0
- Else proceed to validation
```

**Validation flow**:
```
1. Build proposed_content:
   - For Write: tool_input.content
   - For Edit: simulate old_string → new_string substitution on current file content
2. Write proposed_content to /tmp/claude-write-guard-$$.md
3. Run validate.sh on temp file → exit code v
4. Run secret-check.sh on temp file → exit code s
5. Run injection-check.sh on temp file → exit code i
6. Decision:
   - if v >= 1 OR s == 1 → deny with feedback listing reasons
   - else → allow, with optional feedback if i == 3
7. Cleanup: rm temp file
8. Output JSON, exit 0
```

**State and side effects**:
- Creates and removes one temp file per invocation
- Read-only on memory tree (does NOT write the proposed content; hook returns decision only)
- No git operations
- Returns ASAP if path not in memory tree (perf)

**Performance target**:
- Pass-through (path not memory) → < 5ms
- Validation path → < 500ms (limited by validator startup × 3)

**External dependencies**: bash 3.2+, jq (optional but useful for JSON parsing), validate.sh / secret-check.sh / injection-check.sh on PATH or via known location.

### Inputs and Outputs

**Input** (Write to non-memory path — fast pass):
```json
{"tool_name":"Write","tool_input":{"file_path":"/some/other/file.txt","content":"..."}}
```

**Output**:
```json
{"permissionDecision":"allow"}
```
Exit: `0`

**Input** (Write clean memory):
```json
{"tool_name":"Write","tool_input":{"file_path":"/Users/raphaelshin/.claude/memory-shared/memories/feedback_new.md","content":"---\nname: New rule\ndescription: ...\ntype: feedback\n---\n\n... body ..."}}
```

**Output**:
```json
{"permissionDecision":"allow"}
```

**Input** (Write with secret):
```json
{"tool_name":"Write","tool_input":{"file_path":".../memories/feedback_leak.md","content":"... ghp_aBcDeFg ..."}}
```

**Output**:
```json
{
  "permissionDecision": "deny",
  "feedback": "memory-write-guard: secret-check.sh blocked write\n  [!] token pattern at line 7"
}
```
Exit: `0` (hook itself succeeded; the deny is in the JSON)

**Input** (Write triggering injection flag):
```json
{"tool_name":"Write","tool_input":{"file_path":".../memories/feedback_strict.md","content":"... always ... never ... must always ..."}}
```

**Output**:
```json
{
  "permissionDecision": "allow",
  "feedback": "memory-write-guard: write allowed but injection-check flagged:\n  [?] high density of absolute commands (3 occurrences)\nReview before merge."
}
```

**Input** (Edit, simulated post-edit content):
- Hook loads current file
- Applies old_string → new_string substitution
- Validates the simulated result

### Edge Cases

- **Edit with `old_string` not found in current file** → tool would fail anyway; hook validates current file (no-op simulation), allows
- **Edit with `replace_all: true`** → simulation applies all occurrences
- **Write to non-existent parent directory** under memory tree → tool will fail when actually creating; hook still validates content (treat as new file)
- **Write of `MEMORY.md`** (the auto-generated index) → hook allows (skipped per validate.sh special case)
- **Write of file in `quarantine/`** → not under `memories/`, hook does NOT validate (quarantine is reviewed separately)
- **Path with symlinks** → resolve via `realpath` before checking prefix
- **Symlink-walk attack** (`memories/../../etc/passwd`) → resolve, then re-check prefix
- **Hook runs but validators are missing** → emit deny with diagnostic; safer than allow
- **Hook fails internally** (bug) → emit allow with feedback noting the internal error; do NOT block legitimate work due to a hook bug; pre-commit and CI catch what slips
- **Concurrent writes to same file** → each invocation independent; no ordering guarantee, but each is validated against its own proposed content
- **`tool_input.file_path` missing or malformed** → emit allow with diagnostic (don't block tool; let it fail naturally)
- **Very large `content`** (>1MB) → tool would handle; hook truncates for validator if needed; document
- **PowerShell mirror behaves identically** for cross-platform parity

### Acceptance Criteria

- [ ] Hook script `global/hooks/memory-write-guard.sh` (executable)
- [ ] **PowerShell mirror** `global/hooks/memory-write-guard.ps1` for Windows / claude-docker
- [ ] Registered in `global/settings.json` PreToolUse with matcher `Edit|Write`
- [ ] **Path gate**: only acts on `realpath` of `$HOME/.claude/memory-shared/memories/*.md`
- [ ] **Edit simulation**: applies `old_string → new_string` (respects `replace_all`) before validating
- [ ] **Decision logic**:
  - `validate.sh` exit ≥ 1 → deny
  - `secret-check.sh` exit 1 → deny
  - `injection-check.sh` exit 3 → allow with feedback (warning)
  - Else allow
- [ ] **Output**: valid JSON with `permissionDecision` and optional `feedback`
- [ ] **Performance**: < 5ms pass-through; < 500ms validation path
- [ ] **Internal failure handling**: emits allow with diagnostic on internal hook bug (fail-open by design — pre-commit/CI catch)
- [ ] **Path resolution** uses `realpath` to prevent symlink bypass
- [ ] Bash 3.2 compatible
- [ ] Test fixture: write of clean memory → allow; write of secret memory → deny; write of injection-flagged → allow with feedback

### Test Plan

- Manual test via Claude Code: ask Claude to write a clean memory, observe allow
- Ask Claude to write memory with synthetic secret, observe deny + feedback
- Ask Claude to write memory with absolute-command density, observe allow with warning
- Ask Claude to write a non-memory file, observe pass-through speed
- Symlink test: target path resolves to memory tree → still validated
- Hook bug simulation: rename validate.sh → hook emits allow with diagnostic
- Performance: time 100 invocations, average under target

### Implementation Notes

- **JSON parsing**: prefer `jq` if available (`jq -r '.tool_input.file_path'`); fallback to grep/sed for environments without jq (claude-config codebase already follows this pattern)
- **Edit simulation in bash**: use bash parameter expansion for substitution: `simulated="${current/$old/$new}"` for first occurrence; loop with `${var/$old/}` until empty for `replace_all`
- **Temp file**: `mktemp -t claude-write-guard.XXXXXX.md` for portability across macOS/Linux
- **Cleanup**: `trap 'rm -f "$tmp"' EXIT` ensures temp removed even on early exit
- **Path prefix check**: `realpath_resolved="$(realpath "$path")"; [[ "$realpath_resolved" == "$HOME/.claude/memory-shared/memories/"* ]]`
- **realpath** is not in macOS by default until Big Sur — use `python3 -c "import os; print(os.path.realpath(...))"` fallback if needed
- **Avoid `awk` write-redirection** in this hook — entirely bash + sed
- **Settings.json registration** appends to existing PreToolUse Edit | Write matcher list; respects existing hook order; documents the order in a `_note` comment per existing claude-config convention
- Hook should be late in the matcher chain (after `pre-edit-read-guard.sh`, before others) — order matters per existing `_note` in settings.json

### Deliverable

- `global/hooks/memory-write-guard.sh` (executable, ~150 lines)
- `global/hooks/memory-write-guard.ps1` (PowerShell parallel)
- Update `global/settings.json` to register the hook
- Test fixtures
- PR linked to this issue

### Breaking Changes

None — additive hook. Existing memory write paths gain validation; no path that previously worked stops working unless content was actually invalid.

### Rollback Plan

- Remove hook entry from `global/settings.json`
- Remove hook script files
- Revert PR

## Cross-references

**Issues**:
- Part of #EPIC
- BlockedBy: #C5
- Blocks: #E1
- Related: #C3 (sibling — pre-commit), #D1 (sibling — sync-time), #A2/#A3/#A4 (validator consumers)

**Docs**:
- `docs/MEMORY_VALIDATION_SPEC.md` (#A1) — exit-code contract
- `docs/THREAT_MODEL.md` (#G3) — write-guard is layer 1 of 5

**Commits/PRs**: (filled at PR time)

**Reference pattern**: `claude-config/global/hooks/sensitive-file-guard.sh`
