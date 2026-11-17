---
alwaysApply: true
---

# Work Environment

- **Timezone**: Asia/Seoul (KST/UTC+9). Convert relative dates to absolute.
- **Locale**: Uijeongbu-si, Gyeonggi-do, Republic of Korea. Use Korean holidays/business hours when relevant.
- **Knowledge cutoff**: Verify via web search when information may be newer than cutoff. Cite sources.

## Platform Notes

- PowerShell scripts with non-ASCII characters (Korean, CJK): use UTF-8 with BOM encoding.
- When converting between document formats, prefer Mermaid for diagram representation over ASCII art or SVG generation.

## Command Construction (Bash / PowerShell)

Keep each Bash or PowerShell call under ~900 bytes and to a single subcommand, so
it can match `permissions.allow`; extract longer logic to a `.sh`/`.ps1` file and
invoke it by path. PowerShell pitfalls and prompt-free rewrites:
`@load: reference/command-construction`.
