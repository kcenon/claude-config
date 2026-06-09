---
name: Private IP leak fixture
description: References an RFC1918 private IPv4 address to trigger the network detector.
type: user
---

This fixture documents an internal service hosted at 10.0.5.42 which falls inside
the private IPv4 ranges enumerated in MEMORY_VALIDATION_SPEC.md section 6. The
secret detector should report a finding for this address.
