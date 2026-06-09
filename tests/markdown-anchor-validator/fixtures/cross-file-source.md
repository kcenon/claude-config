# Cross-file reference source

This file contains an inter-file reference whose target is the sibling
`cross-file-target.md`. When only this file is staged, the validator
must lazy-resolve anchors from the unstaged sibling and allow the
commit because the target heading exists.

[valid cross-file ref](cross-file-target.md#real-target-heading)
