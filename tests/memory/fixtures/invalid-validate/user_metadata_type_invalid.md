---
name: Nested type out of enum
description: A memory whose only type is nested under metadata and is not an enum value.
metadata:
  node_type: memory
  type: bogus
---

This fixture exercises the type-enum check on the nested `metadata.type` fallback.
The value `bogus` is not one of the allowed values (user, feedback, project,
reference), so the validator should exit with code 2 (FAIL-FORMAT).
