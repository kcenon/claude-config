---
description: A memory file missing the required name field entirely.
type: user
---

This fixture omits the required `name` field. Per spec section 3 the validator must
report a structural error and exit with code 1 (FAIL-STRUCT) because a required
field is absent.
