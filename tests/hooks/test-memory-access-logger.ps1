#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for memory-access-logger.ps1 and Resolve-HookPath (issue #983)
# Run: pwsh tests/hooks/test-memory-access-logger.ps1
#
# PowerShell counterpart of test-memory-access-logger.sh. The hook logs a Read
# only when the resolved path is under the memory root. Before #983 neither side
# followed a link, and a new file went through `Split-Path -LiteralPath`, which
# throws on PowerShell 7, so another spelling of a file left no line or a line
# with a raw `..` in it.
#
# Links need a privilege on some Windows hosts; without one the link rows print
# SKIP. The windows-powershell-hooks job has to show them running.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'memory-access-logger.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

Import-Module (Join-Path $script:RepoRoot 'global' 'hooks' 'lib' 'CommonHelpers.psm1') -Force -WarningAction SilentlyContinue

function Assert-Condition {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label$(if ($Detail) { " - $Detail" })")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

# One call of the hook from an empty log. Returns the raw log text, or ''.
function Invoke-Logger {
    param([string]$HomeDir, [string]$Tool, [string]$Path)
    $log = Join-Path $HomeDir '.claude' 'logs' 'memory-access.log'
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $env:HOME = $HomeDir
    $env:USERPROFILE = $HomeDir
    $json = @{ tool_name = $Tool; session_id = 's1'; tool_input = @{ file_path = $Path } } | ConvertTo-Json -Compress
    $json | & pwsh -NoProfile -File $script:HookPath 2>$null | Out-Null
    if (Test-Path -LiteralPath $log) { return (Get-Content -LiteralPath $log -Raw) }
    return ''
}

# The expected key, or '' for no line.
function Assert-Key {
    param([string]$Expected, [string]$HomeDir, [string]$Tool, [string]$Path, [string]$Label)
    $raw = Invoke-Logger -HomeDir $HomeDir -Tool $Tool -Path $Path
    $got = ($raw.Trim() -replace '^\S+ \S+ read ', '')
    Assert-Condition ($got -ceq $Expected) $Label "expected '$Expected', got '$got'"
}

function Assert-Path {
    param([string]$Actual, [string]$Expected, [string]$Label)
    Assert-Condition ($Actual -ceq $Expected) $Label "expected '$Expected', got '$Actual'"
}

# Returns $true when the link could be created. A dangling target is allowed.
function New-TestLink {
    param([string]$Path, [string]$Target)
    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

$savedHome = $env:HOME
$savedProfile = $env:USERPROFILE
$root = Join-Path ([System.IO.Path]::GetTempPath()) "mal-ps-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"

try {
    $real = Join-Path $root 'real'
    $link = Join-Path $root 'link'
    $shared = Join-Path $real '.claude' 'memory-shared'
    $mem = Join-Path $shared 'memories'
    $viaLink = Join-Path $link '.claude' 'memory-shared' 'memories'
    New-Item -ItemType Directory -Path $mem, (Join-Path $real '.claude' 'other'), (Join-Path $real 'notes'), (Join-Path $real 'a' 'b') -Force | Out-Null
    foreach ($f in (Join-Path $mem 'e.md'), (Join-Path $shared 'MEMORY.md'), (Join-Path $real 'notes' 'n.md'), (Join-Path $real 'a' 'b' 'f.md')) {
        New-Item -ItemType File -Path $f -Force | Out-Null
    }
    $canLink = New-TestLink -Path $link -Target $real

    # The temporary directory itself may sit behind a link (macOS: /var).
    $base = Resolve-HookPath $real

    Write-Host '=== memory-access-logger.ps1 tests ==='
    Write-Host "  links: $(if ($canLink) { 'yes' } else { 'no' })"
    Write-Host ''

    Write-Host '[Path spellings of one memory file]'
    Assert-Key 'memories/e.md' $real 'Read' (Join-Path $mem 'e.md') 'real HOME, real path'
    Assert-Key 'memories/e.md' $real 'Read' (Join-Path $mem '..' 'memories' 'e.md') 'existing file, dot segment'
    if ($canLink) {
        Assert-Key 'memories/e.md' $real 'Read' (Join-Path $viaLink 'e.md') 'real HOME, path through a link'
        Assert-Key 'memories/e.md' $link 'Read' (Join-Path $viaLink 'e.md') 'HOME on a link, path through the link'
        Assert-Key 'memories/e.md' $link 'Read' (Join-Path $mem 'e.md') 'HOME on a link, real path'
    } else {
        Write-Host '  SKIP: spellings through a link'
    }

    Write-Host ''
    Write-Host '[A file that does not exist yet]'
    Assert-Key 'memories/n.md' $real 'Read' (Join-Path $mem '..' 'memories' 'n.md') 'dot segment inside the memory root'
    Assert-Key 'memories/n.md' $real 'Read' (Join-Path $real '.claude' 'other' '..' 'memory-shared' 'memories' 'n.md') 'dot segment outside the memory root'
    if ($canLink) {
        Assert-Key 'memories/n.md' $link 'Read' (Join-Path $viaLink 'n.md') 'HOME on a link'
        Assert-Key 'memories/n.md' $link 'Read' (Join-Path $mem 'n.md') 'HOME on a link, real path'
    } else {
        Write-Host '  SKIP: new files through a link'
    }

    Write-Host ''
    Write-Host '[A memories directory that is itself a link]'
    $home2 = Join-Path $root 'home2'
    $store = Join-Path $root 'store'
    New-Item -ItemType Directory -Path (Join-Path $home2 '.claude' 'memory-shared'), $store -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $store 'e.md') -Force | Out-Null
    if (New-TestLink -Path (Join-Path $home2 '.claude' 'memory-shared' 'memories') -Target $store) {
        Assert-Key 'memories/e.md' $home2 'Read' (Join-Path $home2 '.claude' 'memory-shared' 'memories' 'e.md') 'path through the link'
        Assert-Key 'memories/e.md' $home2 'Read' (Join-Path $store 'e.md') 'path to the link target'
    } else {
        Write-Host '  SKIP: linked memories directory'
    }

    Write-Host ''
    Write-Host '[Not logged]'
    Assert-Key '' $real 'Read' (Join-Path $real 'notes' 'n.md') 'a file outside the memory root'
    Assert-Key '' $real 'Read' (Join-Path $shared 'MEMORY.md') 'the top-level index'
    Assert-Key '' $real 'Read' (Join-Path $real '.claude' 'memory-shared' 'memories-other' 'e.md') 'a sibling that only shares the prefix'
    Assert-Key '' $real 'Edit' (Join-Path $mem 'e.md') 'a tool other than Read'

    Write-Host ''
    Write-Host '[Line shape]'
    $raw = Invoke-Logger -HomeDir $real -Tool 'Read' -Path (Join-Path $mem 'e.md')
    Assert-Condition ($raw.Trim() -cmatch '^\d{4}-\d{2}-\d{2}T[\d:]{8}Z s1 read memories/e\.md$') 'timestamp, session id, verb, key' "got '$raw'"

    Write-Host ''
    Write-Host '[Resolve-HookPath]'
    Assert-Path (Resolve-HookPath '') '' 'empty input stays empty'
    Assert-Path (Resolve-HookPath (Join-Path $real 'a' 'b' 'f.md')) (Join-Path $base 'a' 'b' 'f.md') 'a plain path keeps its shape'
    Assert-Path (Resolve-HookPath (Join-Path $real 'a' '.' 'b' '..' 'b' 'f.md')) (Join-Path $base 'a' 'b' 'f.md') 'dot segments collapse'
    Assert-Path (Resolve-HookPath (Join-Path $real 'no-dir' 'x' 'new.md')) (Join-Path $base 'no-dir' 'x' 'new.md') 'a missing tail is kept'
    Assert-Path (Resolve-HookPath (Join-Path $real 'no-dir' '..' 'a' 'b')) (Join-Path $base 'a' 'b') 'dot segments collapse in a missing tail'
    Push-Location $real
    try {
        Assert-Path (Resolve-HookPath (Join-Path 'a' 'b' 'f.md')) (Join-Path $base 'a' 'b' 'f.md') 'a relative path resolves against the location'
    } finally { Pop-Location }
    $homeBase = Resolve-HookPath $HOME
    Assert-Path (Resolve-HookPath '~/x.md') (Join-Path $homeBase 'x.md') 'a leading ~/ expands'
    Assert-Path (Resolve-HookPath '$HOME/x.md') (Join-Path $homeBase 'x.md') 'a leading $HOME/ expands'

    if ($canLink) {
        Assert-Path (Resolve-HookPath $link) $base 'the link itself'
        Assert-Path (Resolve-HookPath (Join-Path $link 'a' 'b' 'f.md')) (Join-Path $base 'a' 'b' 'f.md') 'a link in the middle'
        Assert-Path (Resolve-HookPath (Join-Path $link 'a' 'new.md')) (Join-Path $base 'a' 'new.md') 'a new file under a link'
        Assert-Path (Resolve-HookPath (Join-Path $link 'no-dir' 'new.md')) (Join-Path $base 'no-dir' 'new.md') 'a new directory under a link'

        # '..' applies to the link's target, not to the spelling of the path.
        $deepLink = Join-Path $root 'deep'
        $null = New-TestLink -Path $deepLink -Target (Join-Path $real 'a' 'b')
        Assert-Path (Resolve-HookPath (Join-Path $deepLink '..' 'x.md')) (Join-Path $base 'a' 'x.md') '.. after a link applies to its target'

        $chain = Join-Path $root 'chain'
        $null = New-TestLink -Path $chain -Target $link
        Assert-Path (Resolve-HookPath (Join-Path $chain 'a')) (Join-Path $base 'a') 'a link to a link'

        $fileLink = Join-Path $real 'flink.md'
        $null = New-TestLink -Path $fileLink -Target (Join-Path $real 'a' 'b' 'f.md')
        Assert-Path (Resolve-HookPath $fileLink) (Join-Path $base 'a' 'b' 'f.md') 'a file that is itself a link'

        # A loop through a parent: the walk has to stop on its own bound.
        $loopA = Join-Path $root 'loop-a'
        $loopB = Join-Path $root 'loop-b'
        if ((New-TestLink -Path $loopA -Target (Join-Path $loopB 'x')) -and (New-TestLink -Path $loopB -Target (Join-Path $loopA 'y'))) {
            $looped = Resolve-HookPath (Join-Path $loopA 'z.md')
            Assert-Condition (-not [string]::IsNullOrEmpty($looped)) 'a link loop returns instead of hanging' "got '$looped'"
        } else {
            Write-Host '  SKIP: link loop (this platform refused a dangling target)'
        }
    } else {
        Write-Host '  SKIP: Resolve-HookPath through links'
    }
}
finally {
    $env:HOME = $savedHome
    $env:USERPROFILE = $savedProfile
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
# Repo-standard summary shape; test-runner.ps1 aggregates /(\d+)\s+passed/ and
# /(\d+)\s+failed/.
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Failed -gt 0) {
    Write-Host ''
    $script:Errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}
exit 0
