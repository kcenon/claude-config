---
name: User missing close delimiter
description: A user memory whose frontmatter is never closed by another `---` line.
type: user

This fixture has no closing frontmatter delimiter. The validator should report a
structural error and exit with code 1 (FAIL-STRUCT) because the frontmatter cannot
be parsed as a complete block.
