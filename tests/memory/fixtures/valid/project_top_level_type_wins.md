---
name: Top-level type wins
description: A valid project memory with both placements; the top-level type takes precedence.
type: project
metadata:
  node_type: memory
  type: bogus
source-machine: test-fixture
created-at: 2026-10-28
trust-level: verified
last-verified: 2026-10-28
---

This fixture carries a valid top-level `type` and an out-of-enum `metadata.type`.

**Why:** the nested value is only a fallback, so a valid top-level value must not be
overridden by it.

**How to apply:** read `metadata.type` only when the top-level key is absent.
