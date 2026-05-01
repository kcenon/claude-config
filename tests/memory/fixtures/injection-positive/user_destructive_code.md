---
name: Destructive command fixture
description: Contains a documented destructive shell command that should trigger pattern 4.
type: user
---

The following snippet is included as a destructive-command sample for testing only.
Running rm -rf / would erase the entire filesystem and must never appear in real
memory content. The injection scanner must flag this fixture.
