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

Keep each Bash or PowerShell tool call small so the harness can parse it and
match it against `permissions.allow`. A command that is too long to parse
cannot match any allow rule and always falls back to a manual permission
prompt, even when every cmdlet it uses is individually allowlisted.

- **Length budget**: target under ~900 bytes per single tool call. The harness
  rejects parsing well below ~1 KB; the exact limit is harness-internal and not
  configurable from this repo, so this is prevention, not a guarantee.
- **Extract long logic to a script**: when logic needs loops, conditionals, or
  several pipes, write it to a `.ps1`/`.sh` file (the Write tool has no length
  limit) and invoke it by path, or split it into several smaller sequential
  calls. Prefer many focused commands over one mega-pipeline.
- **PowerShell pitfalls** that inflate a single call:
  - Verbose formatting on inspection commands
    (`| Format-Table -AutoSize | Out-String -Width 200`) — drop it when you only
    need the data.
  - Multi-statement / control-flow scripts (`foreach`, `if`, `switch`, multiple
    `Write-Output` lines) — these also fail to match single-cmdlet allow rules
    such as `PowerShell(Get-ChildItem:*)`, so they prompt regardless of length.

See `HOOKS.md` (Windows permission profile) for why the allow-list is not
widened to auto-approve arbitrary `pwsh -File` invocations.
