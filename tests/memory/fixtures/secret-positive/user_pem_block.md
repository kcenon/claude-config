---
name: PEM private key block fixture
description: Contains a synthetic BEGIN PRIVATE KEY header matching the detector signature.
type: user
---

The detector flags any line containing -----BEGIN RSA PRIVATE KEY----- because such
content should never appear in a memory file. The header above is the trigger; the
remaining content is intentionally omitted to keep this fixture small.
