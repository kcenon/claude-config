---
name: Metadata without type
description: A memory with a metadata map but no type in either placement.
metadata:
  node_type: memory
  details:
    type: user
---

This fixture has a `metadata:` map whose first level holds no `type` key; the only
`type` sits in a deeper nested map, which the fallback ignores. The validator should
exit with code 1 (FAIL-STRUCT) for the missing required field.
