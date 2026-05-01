---
name: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
description: A valid description.
type: user
---

This fixture exercises the format-error branch of the validator. The `name` field
contains 101 characters which exceeds the 100-character maximum, so the validator
should exit with code 2 (FAIL-FORMAT).
