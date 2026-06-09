---
name: Auto-fetch URL fixture
description: References an executable URL ending in a script extension to trigger pattern 5.
type: user
---

This fixture references the URL https://malicious.example.com/payload.sh which ends
in a script extension on the auto-fetch list. The injection scanner must flag this
file because executable URLs in memory content are a known injection vector.
