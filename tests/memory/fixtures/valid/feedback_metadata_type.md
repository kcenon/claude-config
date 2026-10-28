---
name: Nested type from auto-memory
description: A valid feedback memory whose type lives under metadata, as auto-memory writes it.
metadata:
  node_type: memory
  type: feedback
  modified: 2026-10-28T00:00:00.000Z
source-machine: test-fixture
created-at: 2026-10-28
trust-level: verified
last-verified: 2026-10-28
---

This fixture mirrors the frontmatter layout that Claude Code's auto-memory writer
emits, where `type` is nested one level under a top-level `metadata:` map.

**Why:** validate.sh must accept the layout the harness actually writes, otherwise
every auto-memory file fails as FAIL-STRUCT.

**How to apply:** when no top-level `type` exists, read it from `metadata.type`.
