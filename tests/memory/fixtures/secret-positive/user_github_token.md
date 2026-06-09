---
name: GitHub token leak fixture
description: Contains a synthetic GitHub personal access token to trigger the secret detector.
type: user
---

A leaked GitHub PAT looks like ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD and the
secret detector must flag this exact pattern. The token here is fabricated and not
valid.
