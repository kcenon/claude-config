---
name: Type out of enum
description: A memory whose type field is not one of the four enum values.
type: bogus
---

This fixture exercises the type-enum check in `validate.sh`. The `type` field is
set to `bogus`, which is not one of the allowed values (user, feedback, project,
reference). The validator should exit with code 2 (FAIL-FORMAT).
