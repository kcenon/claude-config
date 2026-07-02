# Test suite for scripts/check_references.ps1 and scripts/sync_references.ps1.
# Run: pwsh -NoProfile -File tests/scripts/test-check-references.ps1

$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Check = Join-Path $RootDir 'scripts/check_references.ps1'
$Sync = Join-Path $RootDir 'scripts/sync_references.ps1'
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("ref-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null

$Pass = 0
$Fail = 0
$Errors = @()

function Write-Fixture {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Assert-Exit {
    param([int]$Expected, [int]$Actual, [string]$Label)
    if ($Expected -eq $Actual) {
        $script:Pass++
        Write-Host "  PASS: $Label"
    } else {
        $script:Fail++
        $script:Errors += "FAIL: $Label -- expected exit $Expected, got $Actual"
        Write-Host "  FAIL: $Label (expected $Expected, got $Actual)"
    }
}

try {
    Write-Host "=== check_references.ps1 tests ==="
    $Repo = Join-Path $Work 'repo'
    New-Item -ItemType Directory -Path $Repo | Out-Null
    Write-Fixture (Join-Path $Repo 'source/exact.md') 'same'
    Write-Fixture (Join-Path $Repo 'target/exact.md') 'same'
    Write-Fixture (Join-Path $Repo 'source/fm.md') "---`ntitle: Source`n---`n`nbody`n"
    Write-Fixture (Join-Path $Repo 'target/fm.md') "body`n"
    Write-Fixture (Join-Path $Repo 'reference-map.yml') @'
version: 1
references:
  - source: source/exact.md
    target: target/exact.md
    mode: exact
  - source: source/fm.md
    target: target/fm.md
    mode: strip-source-frontmatter
'@

    & pwsh -NoProfile -File $Check $Repo (Join-Path $Repo 'reference-map.yml') *> $null
    Assert-Exit 0 $LASTEXITCODE 'exact and strip-source-frontmatter entries pass'

    Write-Fixture (Join-Path $Repo 'target/exact.md') 'drift'
    & pwsh -NoProfile -File $Check $Repo (Join-Path $Repo 'reference-map.yml') *> $null
    Assert-Exit 2 $LASTEXITCODE 'drift exits 2'

    & pwsh -NoProfile -File $Sync $Repo (Join-Path $Repo 'reference-map.yml') *> $null
    Assert-Exit 0 $LASTEXITCODE 'sync exits 0'
    & pwsh -NoProfile -File $Check $Repo (Join-Path $Repo 'reference-map.yml') *> $null
    Assert-Exit 0 $LASTEXITCODE 'sync restores drift'
}
finally {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "  $Pass passed, $Fail failed"
if ($Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Errors:"
    foreach ($err in $Errors) {
        Write-Host "  $err"
    }
    exit 1
}
exit 0
