---
name: User simple preference
description: A minimal valid user-type memory file used as a happy-path fixture.
type: user
source-machine: test-fixture
created-at: 2026-05-01
trust-level: verified
last-verified: 2026-05-01
---

This fixture covers the simplest valid case for `user` type memories.
It exists to confirm `validate.sh` exits 0 when every required and recommended
field is present and the body is at least 30 characters long.
