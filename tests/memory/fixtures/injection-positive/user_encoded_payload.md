---
name: Encoded payload fixture
description: Contains a long base64-like blob that should trigger pattern 6.
type: user
---

The following blob is intentionally long to exceed the 120 character base64 detection
threshold:

QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQQ==

The injection scanner must flag this fixture.
