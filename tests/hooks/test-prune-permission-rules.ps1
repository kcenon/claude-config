#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for prune-permission-rules.ps1
# Run: pwsh tests/hooks/test-prune-permission-rules.ps1
#
# The bash suite already cross-checks the two halves wherever pwsh is present,
# but that check only runs on the Linux/macOS job. This suite is what covers the
# PowerShell half on the native Windows runner, where test-runner.ps1 is the
# only sweep that executes.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'prune-permission-rules.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "test-prune-permission-rules-$PID"
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

try {
    function Assert-Equal {
        param([string]$Label, [string]$Expected, [string]$Actual)
        if ($Expected -eq $Actual) {
            $script:Passed++
            Write-Host "  PASS: $Label"
        }
        else {
            $script:Failed++
            $script:Errors.Add("FAIL: $Label -- expected [$Expected], got [$Actual]")
            Write-Host "  FAIL: $Label"
            Write-Host "        expected: $Expected"
            Write-Host "        actual:   $Actual"
        }
    }

    function New-Project {
        param([string]$Name, [string]$Body)
        $dir = Join-Path $TestRoot $Name
        New-Item -ItemType Directory -Path (Join-Path $dir '.claude') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dir '.claude' 'settings.local.json'), $Body)
        return $dir
    }

    function Get-SettingsPath {
        param([string]$Dir)
        return (Join-Path $Dir '.claude' 'settings.local.json')
    }

    function Invoke-PruneHook {
        param([string]$Dir)
        $payload = @{ cwd = $Dir; session_id = 'test'; hook_event_name = 'SessionEnd' } | ConvertTo-Json -Compress
        $payload | & pwsh -NoProfile -File $script:HookPath 2>$null | Out-Null
        return $LASTEXITCODE
    }

    function Get-AllowCompact {
        param([string]$Dir)
        $obj = Get-Content -LiteralPath (Get-SettingsPath $Dir) -Raw | ConvertFrom-Json
        return ($obj.permissions.allow | ConvertTo-Json -Compress)
    }

    function Get-Sha {
        param([string]$Path)
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }

    $Mixed = @'
{
  "permissions": {
    "allow": [
      "Bash(gh:*)",
      "Bash(gh pr list --limit 5)",
      "PowerShell(Remove-Item *)",
      "PowerShell(docker run *)",
      "Bash(git commit -m ':*)",
      "Bash(cd /tmp/claude-501/592fccf2-dd2a-4e3f-8107-d18162a879df/scratchpad)",
      "Bash(echo one; echo two)",
      "Bash(cat a | grep b)",
      "Read",
      "WebFetch",
      "Skill",
      "Bash(npm run build:*)"
    ],
    "deny": []
  }
}
'@

    Write-Host '=== prune-permission-rules.ps1 tests ==='
    Write-Host ''

    # --- Classification ---------------------------------------------------
    Write-Host '[Classification]'
    $dir = New-Project 'mixed' $Mixed
    $code = Invoke-PruneHook $dir
    $expected = @('Bash(gh:*)', 'Read', 'WebFetch', 'Skill', 'Bash(npm run build:*)') | ConvertTo-Json -Compress
    Assert-Equal 'Keeps prefix rules and bare strings, drops the rest' $expected (Get-AllowCompact $dir)
    Assert-Equal 'Exit code is 0' '0' "$code"

    # --- Removal classes --------------------------------------------------
    Write-Host ''
    Write-Host '[Removal classes]'

    function Get-OneEntryResult {
        param([string]$Name, [string]$EntryJson)
        $body = @"
{
  "permissions": {
    "allow": [
      "Bash(keepme:*)",
      $EntryJson
    ]
  }
}
"@
        $d = New-Project $Name $body
        Invoke-PruneHook $d | Out-Null
        return (Get-AllowCompact $d)
    }

    $keepOnly = @('Bash(keepme:*)') | ConvertTo-Json -Compress

    Assert-Equal 'Denylist: unbounded-argument rule removed' $keepOnly (Get-OneEntryResult 'deny1' '"PowerShell(Remove-Item *)"')
    Assert-Equal 'Denylist: quote-anchored prefix removed' $keepOnly (Get-OneEntryResult 'deny2' '"Bash(git commit -m '':*)"')
    Assert-Equal 'Session UUID path removed' $keepOnly (Get-OneEntryResult 'uuid' '"Bash(ls /tmp/592fccf2-dd2a-4e3f-8107-d18162a879df/x)"')
    Assert-Equal 'Compound with semicolon removed' $keepOnly (Get-OneEntryResult 'semi' '"Bash(a; b)"')
    Assert-Equal 'Compound with pipe removed' $keepOnly (Get-OneEntryResult 'pipe' '"Bash(a | b)"')

    $long = 'x' * 130
    Assert-Equal 'Over-long literal removed' $keepOnly (Get-OneEntryResult 'long' "`"Bash(echo $long)`"")

    # --- Subsumption ------------------------------------------------------
    Write-Host ''
    Write-Host '[Subsumption]'
    $dir = New-Project 'subsume' @'
{
  "permissions": {
    "allow": [
      "Bash(gh:*)",
      "Bash(gh api repos/foo)",
      "Bash(ghost-command run)"
    ]
  }
}
'@
    Invoke-PruneHook $dir | Out-Null
    $expected = @('Bash(gh:*)', 'Bash(ghost-command run)') | ConvertTo-Json -Compress
    Assert-Equal 'Subsumed entry removed, similarly-named command kept' $expected (Get-AllowCompact $dir)

    # --- Bracket safety ---------------------------------------------------
    Write-Host ''
    Write-Host '[Bracket safety]'
    $dir = New-Project 'bracket' @'
{
  "permissions": {
    "allow": [
      "Bash(sed -i '' 's/[*_~]//g' f.txt)",
      "PowerShell(Remove-Item *)",
      "Read"
    ]
  }
}
'@
    Invoke-PruneHook $dir | Out-Null
    $expected = @("Bash(sed -i '' 's/[*_~]//g' f.txt)", 'Read') | ConvertTo-Json -Compress
    Assert-Equal 'A ] inside a rule string is not read as the array terminator' $expected (Get-AllowCompact $dir)

    # --- Fail-open --------------------------------------------------------
    Write-Host ''
    Write-Host '[Fail-open]'

    $dir = New-Project 'malformed' '{ "permissions": { "allow": [ "Bash(a; b)", ] '
    $path = Get-SettingsPath $dir
    $before = Get-Sha $path
    $code = Invoke-PruneHook $dir
    Assert-Equal 'Malformed JSON leaves the file byte-identical' $before (Get-Sha $path)
    Assert-Equal 'Malformed JSON still exits 0' '0' "$code"

    $dir = New-Project 'collapsed' '{ "permissions": { "allow": ["Bash(a; b)", "Read"] } }'
    $path = Get-SettingsPath $dir
    $before = Get-Sha $path
    Invoke-PruneHook $dir | Out-Null
    Assert-Equal 'Collapsed array left byte-identical' $before (Get-Sha $path)

    $dir = New-Project 'nochange' @'
{
  "permissions": {
    "allow": [
      "Bash(gh:*)",
      "Read"
    ]
  }
}
'@
    $path = Get-SettingsPath $dir
    $before = Get-Sha $path
    Invoke-PruneHook $dir | Out-Null
    Assert-Equal 'No removable entries leaves the file byte-identical' $before (Get-Sha $path)

    $missing = Join-Path $TestRoot 'does-not-exist'
    $code = Invoke-PruneHook $missing
    Assert-Equal 'Missing settings file exits 0' '0' "$code"

    '{"hook_event_name":"SessionEnd"}' | & pwsh -NoProfile -File $script:HookPath 2>$null | Out-Null
    Assert-Equal 'Payload without cwd exits 0' '0' "$LASTEXITCODE"

    'not json at all' | & pwsh -NoProfile -File $script:HookPath 2>$null | Out-Null
    Assert-Equal 'Non-JSON payload exits 0' '0' "$LASTEXITCODE"

    # --- Key preservation -------------------------------------------------
    Write-Host ''
    Write-Host '[Key preservation]'
    $dir = New-Project 'keys' @'
{
  "permissions": {
    "allow": [
      "Bash(gh:*)",
      "Bash(echo one; echo two)"
    ],
    "deny": ["Bash(rm:*)"]
  },
  "skillOverrides": { "some-skill": true, "other-skill": false },
  "hooks": { "SessionEnd": [{ "hooks": [] }] },
  "env": { "FOO": "bar" }
}
'@
    Invoke-PruneHook $dir | Out-Null
    $obj = Get-Content -LiteralPath (Get-SettingsPath $dir) -Raw | ConvertFrom-Json
    Assert-Equal 'skillOverrides survives' 'True|False' "$($obj.skillOverrides.'some-skill')|$($obj.skillOverrides.'other-skill')"
    Assert-Equal 'hooks survives' 'True' "$($null -ne $obj.hooks.SessionEnd)"
    Assert-Equal 'permissions.deny survives' (@('Bash(rm:*)') | ConvertTo-Json -Compress) ($obj.permissions.deny | ConvertTo-Json -Compress)
    Assert-Equal 'env survives' 'bar' "$($obj.env.FOO)"
    Assert-Equal 'allow was still pruned' (@('Bash(gh:*)') | ConvertTo-Json -Compress) (Get-AllowCompact $dir)

    # --- Housekeeping -----------------------------------------------------
    Write-Host ''
    Write-Host '[Housekeeping]'
    $leftovers = @(Get-ChildItem -Path (Join-Path $dir '.claude') -Filter '*.prune.*' -ErrorAction SilentlyContinue).Count
    Assert-Equal 'No temp file left in the target directory' '0' "$leftovers"

    # --- Idempotency ------------------------------------------------------
    Write-Host ''
    Write-Host '[Idempotency]'
    $dir = New-Project 'idem' $Mixed
    Invoke-PruneHook $dir | Out-Null
    $first = Get-Sha (Get-SettingsPath $dir)
    Invoke-PruneHook $dir | Out-Null
    Assert-Equal 'Second run is a no-op' $first (Get-Sha (Get-SettingsPath $dir))

    # --- Hook contract ----------------------------------------------------
    Write-Host ''
    Write-Host '[Hook contract]'
    $dir = New-Project 'quiet' $Mixed
    $payload = @{ cwd = $dir; hook_event_name = 'SessionEnd' } | ConvertTo-Json -Compress
    $out = $payload | & pwsh -NoProfile -File $script:HookPath 2>$null
    Assert-Equal 'Produces no stdout' '' "$out"

    $header = Get-Content -LiteralPath $script:HookPath -Raw
    Assert-Equal 'Declares Hook Type: SessionEnd' 'True' "$($header -match 'Hook Type: SessionEnd')"

    Write-Host ''
    Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
    if ($script:Errors.Count -gt 0) {
        Write-Host ''
        foreach ($e in $script:Errors) { Write-Host "  $e" }
        exit 1
    }
    exit 0
}
finally {
    if (Test-Path $TestRoot) { Remove-Item -Recurse -Force $TestRoot -ErrorAction SilentlyContinue }
}
