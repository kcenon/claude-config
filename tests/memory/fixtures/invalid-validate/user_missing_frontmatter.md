name: User missing opening delimiter
description: A user memory whose first line is not the frontmatter open delimiter.
type: user
---

This fixture omits the opening `---` line, so the validator should detect a
structural error and exit with code 1 (FAIL-STRUCT).
