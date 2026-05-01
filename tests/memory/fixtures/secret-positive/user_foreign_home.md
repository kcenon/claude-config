---
name: Foreign home directory fixture
description: References a non-owner /Users/ path expected to be flagged by the detector.
type: user
---

This fixture references the path /Users/strangeruser/Documents/notes.md which is
not owned by the configured owner. The secret detector must produce a finding so
that machine-specific paths do not leak across sync boundaries.
