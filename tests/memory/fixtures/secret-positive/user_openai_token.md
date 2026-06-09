---
name: OpenAI-style token fixture
description: Contains a synthetic OpenAI sk- prefixed token long enough to match the detector.
type: user
---

This fixture exercises the sk- token signature. The detector requires at least 20
alphanumeric characters after the prefix to avoid matching unrelated identifiers
such as sk-learn. A synthetic token sk-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789 is
provided so the detector reports a finding.
