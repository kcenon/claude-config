---
name: Project memory with how-to
description: A valid project memory carrying both Why and How to apply markers.
type: project
source-machine: test-fixture
created-at: 2026-05-01
trust-level: verified
last-verified: 2026-05-01
---

Project-scoped memory describing a build convention.

**Why:** the build convention exists because consistent invocation reduces drift
across CI environments.

**How to apply:** invoke the documented script from the repository root and verify the
exit code matches the published contract.
