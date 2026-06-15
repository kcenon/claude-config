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

### Compound commands erode the matchable prefix

Length is not the only trigger. A *compound* PowerShell command — even a short
one — often cannot be reduced to a matchable prefix, so the permission engine
stores the **entire command string** as a one-off literal. The next call with
any argument changed no longer matches, so "Yes, and don't ask again" never
accumulates reusable coverage. The fix is to make the **first token a plain
cmdlet** and keep each call to a single subcommand.

Three rules of thumb:

1. **First token must be a cmdlet.** A leading variable assignment
   (`$env:X='y'; ...`, `$work = ...`) or a `cd <path>; ...` chain makes the
   whole line the prefix. Pass paths/values inline instead
   (`gh ... --repo <owner/repo>`, `git -C <path> ...`, `python -X utf8 ...`).
2. **Break the chain.** `A; B; foreach {...}` and deep `A | B | C | D` require
   every subcommand to be allow-listed; split into focused calls.
3. **Prefer the dedicated tool.** File discovery -> Glob; content search ->
   Grep; file read -> Read. These bypass shell permission matching entirely.

Prompt-free rewrites (generalized):

| Instead of | Use |
|------------|-----|
| `cd <repo>; gh issue view <n> ... \| ConvertFrom-Json \| ...` | `gh issue view <n> --repo <owner/repo> --json number,title,state,body` |
| `cd <repo>; foreach ($n in <a>,<b>) { gh issue view $n ... }` | one `gh issue view <n>` per number, or `gh issue list --search "<a> <b>"` |
| `$env:PYTHONIOENCODING='utf-8'; python -m <mod>` | `python -X utf8 -m <mod>` |
| `$work = ...; if (...) {...}; git -C $work ...` | `git -C <literal-path> ...` |
| `Get-ChildItem X -Recurse \| Where-Object {...} \| Select-Object ...` | Glob tool, or `Get-ChildItem X -Recurse -Filter *.ts -Name` |
| `Select-String -Path X -Pattern Y \| ... \| ForEach-Object {...}` | Grep tool, or `Select-String -Path X -Pattern Y` |
| `(Get-Content X \| Measure-Object -Line).Lines` | Read tool, or `Get-Content X -TotalCount <n>` |
| `if (Test-Path X) { Get-Content X } else {...}` | Read tool on X (a not-found error signals absence), or `Get-Content X -ErrorAction SilentlyContinue` |

> **Sandbox note**: `autoAllowBashIfSandboxed` auto-approves the Bash tool only,
> never PowerShell tool calls, and the sandbox does not run on Windows — so
> PowerShell prompts are governed by `permissions.allow` matching alone.

See `HOOKS.md` (Windows permission profile) for why the allow-list is not
widened to auto-approve arbitrary `pwsh -File` invocations.
