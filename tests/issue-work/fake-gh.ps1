#Requires -Version 7.0
# fake-gh.ps1
# Fake gh for triage state machine tests.
# ======================================
# PowerShell parity port of tests/issue-work/fake-gh.sh. Serves the same canned
# responses from $env:FAKE_GH_DIR and records mutations so tests can assert
# exact side-effect counts (comments posted, children created, assigns). Only
# the gh surface that scripts/triage.ps1 and scripts/cleanup-workspace.ps1 touch
# is implemented -- the same subset fake-gh.sh covers, no more and no less.
#
# Fixture files under $env:FAKE_GH_DIR (identical layout to fake-gh.sh):
#   user                      current-user login (default "me")
#   autoselect                number returned by `issue list --limit 1` auto-select
#   issue-<n>.json            issue object for `issue view <n>`
#   issue-<n>.postclaim.json  optional swap returned after an edit (race sim)
#   issue-<n>.comments        comment text (markers live here; appended on post)
#   children-<n>.json         array for `issue list --search "Part of #<n>"`
#   pr-<n>.json               array for `pr list --search <n>` (default [])
#   pr-view-<n>.json          object for `pr view <n>` (default {}); #840 reconcile
#   mutations.log             appended: COMMENT <n> / CREATE <title> / ASSIGN <n> / UNASSIGN <n>
#   edited-<n>                marker touched on `issue edit <n>`
#
# Invocation contract (verified on pwsh 7.6.3)
# --------------------------------------------
# triage.ps1 and cleanup-workspace.ps1 reach their gh seam as
# `& $script:GhBin @GhArgs`. When $env:GH_BIN points at this .ps1, PowerShell
# runs it *in-process* as a script rather than as a native child process, so:
#   * no executable bit, shebang, or `pwsh -File` shim is needed -- unlike
#     fake-gh.sh, which the bash suites must copy to an executable path first;
#   * responses go to the PowerShell success stream (Write-Output), which is
#     what the caller's `$out = _triage_gh ...` capture reads. Writing to the
#     process stdout handle instead ([Console]::Out) would bypass that capture
#     and the caller would observe empty output;
#   * `exit <n>` returns to the caller and sets $LASTEXITCODE; it does not
#     terminate the calling session;
#   * the caller's `Set-StrictMode -Version Latest` is inherited here, so every
#     argument index and object member access below is existence-checked.
# Set-StrictMode is also asserted locally (it does not leak back to the caller),
# so behavior is identical when the script is run standalone as
# `pwsh -NoProfile -File fake-gh.ps1 <args>`.
#
# Every call site funnels output through `| Out-String` then `.Trim()`, so the
# line-vs-array shape and trailing-newline differences against `cat` are
# normalized away.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Mirrors fake-gh.sh's `${FAKE_GH_DIR:?FAKE_GH_DIR must be set}`: an unset seam
# is a hard error (exit 1, nothing on stdout), not a silent no-op.
if ([string]::IsNullOrEmpty($env:FAKE_GH_DIR)) {
    Write-Error 'fake-gh.ps1: FAKE_GH_DIR must be set' -ErrorAction Continue
    exit 1
}

$script:Dir = $env:FAKE_GH_DIR
$script:Log = Join-Path $script:Dir 'mutations.log'
$script:Argv = @($args)

# ── Argument helpers ─────────────────────────────────────────────────

# Positional read with the `${N:-}` default. Bounds-checked because StrictMode
# turns an out-of-range $args index into a terminating error.
function Get-Positional {
    param([int]$Index)
    if ($Index -lt $script:Argv.Count) { return [string]$script:Argv[$Index] }
    return ''
}

# Positional read with fake-gh.sh's `set -u` semantics: the issue/PR number
# arguments are read as bare `$3`, so their absence aborts the script with a
# non-zero status instead of yielding an empty string.
function Get-RequiredPositional {
    param([int]$Index)
    if ($Index -ge $script:Argv.Count) {
        Write-Error "fake-gh.ps1: `$$($Index + 1): unbound variable" -ErrorAction Continue
        exit 1
    }
    return [string]$script:Argv[$Index]
}

# Pull a flag value out of the argument list (first match wins), mirroring the
# arg_value helper in fake-gh.sh.
function Get-ArgValue {
    param([string]$Flag)
    for ($i = 0; $i -lt $script:Argv.Count; $i++) {
        if ([string]$script:Argv[$i] -ceq $Flag) {
            if (($i + 1) -lt $script:Argv.Count) { return [string]$script:Argv[$i + 1] }
            return ''
        }
    }
    return ''
}

# ── Fixture I/O helpers ──────────────────────────────────────────────

# `cat <file>` equivalent. Emits nothing for a missing or empty file, matching
# `cat` on an empty file and `cat ... 2>/dev/null` on a missing one. Trailing
# newlines are trimmed because Write-Output re-adds exactly one.
function Write-FixtureFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($raw)) { return }
    Write-Output $raw.TrimEnd("`r", "`n")
}

# `>>` equivalent, pinned to LF and UTF-8 without BOM so the bash and PowerShell
# suites read each other's mutations.log byte for byte. Write failures are
# swallowed to mirror bash carrying on (and still exiting 0) when the fixture
# directory is missing.
function Add-FixtureText {
    param([string]$Path, [string]$Text)
    try {
        [System.IO.File]::AppendAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
    } catch {
        # Matches `echo ... >> "$LOG"` on a missing directory: reported on
        # stderr by the shell, non-fatal, final status still 0.
    }
}

# `: > <file>` equivalent -- truncate-or-create an empty marker file.
function Set-FixtureMarker {
    param([string]$Path)
    try {
        [System.IO.File]::WriteAllText($Path, '', [System.Text.UTF8Encoding]::new($false))
    } catch {
        # Same tolerance as Add-FixtureText.
    }
}

# Parse a fixture JSON file, replacing the embedded python3 json.load in
# fake-gh.sh (this port carries no python3 dependency, matching the other
# issue-work PowerShell ports). Returns $null when the file is missing or
# unparseable, so callers can emit nothing exactly as `python3 ... 2>/dev/null`
# does. The comma operator stops PowerShell from unrolling a JSON array payload
# on return.
function Read-FixtureJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return , $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return , $null }
    try {
        return , ($raw | ConvertFrom-Json)
    } catch {
        return , $null
    }
}

# StrictMode-safe `dict.get(name, "")`: a missing member yields '' rather than
# throwing, and a JSON null yields '' the way python's `"" if cur is None` does.
function Get-JsonMember {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return '' }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            $value = $Object[$Name]
            if ($null -eq $value) { return '' }
            return $value
        }
        return ''
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return '' }
    return $prop.Value
}

# Walk a simple dotted path (e.g. .state, .mergeCommit.oid, .headRefName,
# .mergedAt), mirroring the python3 path walker in fake-gh.sh. Descending into a
# non-object yields '' and stops, as in the bash version.
function Get-DottedValue {
    param($Object, [string]$Path)
    $cur = $Object
    foreach ($part in ($Path.TrimStart('.') -split '\.')) {
        if ($part -eq '') { continue }
        if ($null -ne $cur -and
            ($cur -is [System.Management.Automation.PSCustomObject] -or $cur -is [System.Collections.IDictionary])) {
            $cur = Get-JsonMember $cur $part
        } else {
            $cur = ''
            break
        }
    }
    if ($null -eq $cur) { return '' }
    return $cur
}

# ── Command dispatch ─────────────────────────────────────────────────

$cmd = Get-Positional 0
$sub = Get-Positional 1

switch -CaseSensitive ($cmd) {
    'api' {
        # `gh api user --jq .login`
        if ($sub -ceq 'user') {
            $userFile = Join-Path $script:Dir 'user'
            if (Test-Path -LiteralPath $userFile -PathType Leaf) {
                Write-FixtureFile $userFile
            } else {
                Write-Output 'me'
            }
        }
    }

    'issue' {
        switch -CaseSensitive ($sub) {
            'view' {
                $num = Get-RequiredPositional 2
                $jsonFields = Get-ArgValue '--json'
                $jqExpr = Get-ArgValue '--jq'
                if ($jsonFields -ceq 'comments') {
                    $commentsFile = Join-Path $script:Dir "issue-$num.comments"
                    if (Test-Path -LiteralPath $commentsFile -PathType Leaf) {
                        Write-FixtureFile $commentsFile
                    } else {
                        Write-Output '{"comments":[]}'
                    }
                    exit 0
                }
                # Return post-claim swap once an edit has occurred (race sim).
                $src = Join-Path $script:Dir "issue-$num.json"
                $postclaim = Join-Path $script:Dir "issue-$num.postclaim.json"
                if ((Test-Path -LiteralPath (Join-Path $script:Dir "edited-$num")) -and
                    (Test-Path -LiteralPath $postclaim -PathType Leaf)) {
                    $src = $postclaim
                }
                if ($jqExpr -ceq '.state') {
                    $obj = Read-FixtureJson $src
                    if ($null -ne $obj) { Write-Output (Get-JsonMember $obj 'state') }
                } else {
                    Write-FixtureFile $src
                }
            }

            'list' {
                $search = Get-ArgValue '--search'
                $jqExpr = Get-ArgValue '--jq'
                if ($search -clike 'Part of #*') {
                    $match = [regex]::Match($search, '#([0-9]+)')
                    $parent = if ($match.Success) { $match.Groups[1].Value } else { '' }
                    $file = Join-Path $script:Dir "children-$parent.json"
                    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                        Write-Output '[]'
                        exit 0
                    }
                    if ($jqExpr -ceq '.[].title') {
                        $items = Read-FixtureJson $file
                        foreach ($item in @($items)) {
                            Write-Output (Get-JsonMember $item 'title')
                        }
                    } else {
                        Write-FixtureFile $file
                    }
                } else {
                    # Auto-select: `issue list --limit 1 --json number --jq .[0].number`
                    Write-FixtureFile (Join-Path $script:Dir 'autoselect')
                }
            }

            'comment' {
                $num = Get-RequiredPositional 2
                $bodyFile = Get-ArgValue '--body-file'
                if (-not [string]::IsNullOrEmpty($bodyFile) -and
                    (Test-Path -LiteralPath $bodyFile -PathType Leaf)) {
                    $body = Get-Content -LiteralPath $bodyFile -Raw -ErrorAction SilentlyContinue
                    if (-not [string]::IsNullOrEmpty($body)) {
                        Add-FixtureText (Join-Path $script:Dir "issue-$num.comments") $body
                    }
                }
                Add-FixtureText $script:Log "COMMENT $num`n"
            }

            'create' {
                $title = Get-ArgValue '--title'
                Add-FixtureText $script:Log "CREATE $title`n"
                Write-Output 'https://github.com/fake/repo/issues/999'
            }

            'edit' {
                $num = Get-RequiredPositional 2
                if ($script:Argv -ccontains '--remove-assignee') {
                    Add-FixtureText $script:Log "UNASSIGN $num`n"
                } else {
                    Set-FixtureMarker (Join-Path $script:Dir "edited-$num")
                    Add-FixtureText $script:Log "ASSIGN $num`n"
                }
            }
        }
    }

    'pr' {
        switch -CaseSensitive ($sub) {
            'list' {
                $search = Get-ArgValue '--search'
                $match = [regex]::Match($search, '[0-9]+')
                $num = if ($match.Success) { $match.Value } else { '' }
                $file = Join-Path $script:Dir "pr-$num.json"
                if (Test-Path -LiteralPath $file -PathType Leaf) {
                    Write-FixtureFile $file
                } else {
                    Write-Output '[]'
                }
            }

            'view' {
                # #840 reconcile: `pr view <n> --json ... --jq <dotted.path>`.
                $num = Get-RequiredPositional 2
                $jqExpr = Get-ArgValue '--jq'
                $file = Join-Path $script:Dir "pr-view-$num.json"
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                    Write-Output '{}'
                    exit 0
                }
                if (-not [string]::IsNullOrEmpty($jqExpr)) {
                    $obj = Read-FixtureJson $file
                    if ($null -ne $obj) { Write-Output (Get-DottedValue $obj $jqExpr) }
                } else {
                    Write-FixtureFile $file
                }
            }
        }
    }
}
exit 0
