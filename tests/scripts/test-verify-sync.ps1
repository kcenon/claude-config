# test-verify-sync.ps1 -- scripts/verify.ps1 compares every file the installers
# deploy: the .ps1 hooks Windows runs, hook libraries, non-markdown skill files
# and an installed project, not only the top-level .sh hooks and *.md skills
# (#944).
#
# Lays out a deployed global layer and project the way the installers do, in a
# temporary directory, and checks that verify.ps1 reports nothing. Then damages
# the tree the ways a stale install differs and checks that each difference is
# reported, and that a line-ending-only change is not.

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$verify = Join-Path $repoRoot 'scripts' 'verify.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "verify_sync_$([guid]::NewGuid())"
$claude = Join-Path $tmp 'home' '.claude'
$proj = Join-Path $tmp 'project'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Copy-Tree {
    param([string]$From, [string]$To)
    if (Test-Path -LiteralPath $From -PathType Container) {
        New-Item -ItemType Directory -Path $To -Force | Out-Null
        Copy-Item -Path (Join-Path $From '*') -Destination $To -Recurse -Force
    }
}

function Invoke-Verify {
    # Runs verify.ps1 in a child process from $Dir and returns its output with
    # ANSI escapes removed.
    param([string]$Dir, [string[]]$Arguments)
    Push-Location $Dir
    try {
        $out = & pwsh -NoProfile -File $verify -ClaudeDir $claude @Arguments 2>&1 | Out-String
    }
    finally {
        Pop-Location
    }
    return $out -replace "`e\[[0-9;]*m", ''
}

function Get-Findings {
    param([string]$Out)
    return @($Out -split "`r?`n" | Where-Object { $_ -match '(DIFF|MISS): ' } | ForEach-Object { $_ -replace '^[^A-Z]*', '' })
}

function Assert-Contains {
    param([string]$Out, [string]$Expected)
    if (-not $Out.Contains($Expected)) {
        throw "FAIL: expected '$Expected'`n$((Get-Findings $Out) -join "`n")"
    }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $claude 'hooks' 'lib') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null

    # Global layer, with the file lists of install.ps1 / install.sh.
    foreach ($f in @('CLAUDE.md', 'commit-settings.md', '.claudeignore')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot 'global' $f) -Destination (Join-Path $claude $f)
    }
    $profileName = if ($IsWindows) { 'settings.windows.json' } else { 'settings.json' }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'global' $profileName) -Destination (Join-Path $claude 'settings.json')
    Copy-Tree -From (Join-Path $repoRoot 'global' 'skills') -To (Join-Path $claude 'skills')
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'global' 'hooks') -File |
        Copy-Item -Destination (Join-Path $claude 'hooks')
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'global' 'hooks' 'lib') -File |
        Copy-Item -Destination (Join-Path $claude 'hooks' 'lib')
    foreach ($lib in @('validate-commit-message.sh', 'validate-language.sh', 'validate-traceability.sh')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot 'hooks' 'lib' $lib) -Destination (Join-Path $claude 'hooks' 'lib' $lib)
    }

    # Project layer. The installers render rules/X.md.tmpl over X.md.
    Copy-Item -LiteralPath (Join-Path $repoRoot 'project' 'CLAUDE.md') -Destination $proj
    Copy-Item -LiteralPath (Join-Path $repoRoot 'project' '.claudeignore') -Destination $proj
    Copy-Item -LiteralPath (Join-Path $repoRoot 'project' '.claude' 'settings.json') -Destination (Join-Path $proj '.claude')
    foreach ($d in @('rules', 'reference', 'skills', 'commands', 'agents')) {
        Copy-Tree -From (Join-Path $repoRoot 'project' '.claude' $d) -To (Join-Path $proj '.claude' $d)
    }
    Get-ChildItem -LiteralPath (Join-Path $proj '.claude' 'rules') -Filter '*.md.tmpl' -File -Recurse | ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName) -replace '\{\{[A-Z_]+\}\}', 'rendered'
        $text = (($text -split "`n") | Where-Object { $_ -notmatch 'tmpl-contract' }) -join "`n"
        [System.IO.File]::WriteAllText($_.FullName.Substring(0, $_.FullName.Length - '.tmpl'.Length), $text, $utf8NoBom)
        Remove-Item -LiteralPath $_.FullName
    }
    [System.IO.File]::WriteAllText((Join-Path $proj '.claude' '.install-manifest.json'), '{"files": {}}', $utf8NoBom)

    # 1. A complete install reports nothing, and cwd detection finds the project.
    $out = Invoke-Verify -Dir $proj -Arguments @()
    if ((Get-Findings $out).Count -ne 0) {
        throw "FAIL: a complete install reported differences`n$((Get-Findings $out) -join "`n")"
    }
    Assert-Contains $out 'SYNC: project/.claude/rules/core/communication.md (rendered)'
    Assert-Contains $out 'SYNC: hooks/lib/'
    Write-Host 'complete install: PASS'

    # 2. Outside a project the section is skipped unless -ProjectDir is given.
    $out = Invoke-Verify -Dir $tmp -Arguments @()
    Assert-Contains $out '-ProjectDir <'
    if ($out.Contains('SYNC: project/')) { throw 'FAIL: project section ran without a project' }
    $out = Invoke-Verify -Dir $tmp -Arguments @('-ProjectDir', $proj)
    Assert-Contains $out 'SYNC: project/CLAUDE.md'
    Write-Host 'project detection: PASS'

    # 3. Each kind of drift is reported; a CRLF and BOM rewrite is not.
    $hookVictim = if ($IsWindows) {
        'edit-guard-dispatcher.ps1'
    } else {
        (Get-ChildItem -LiteralPath (Join-Path $repoRoot 'global' 'hooks') -Filter '*.sh' -File | Sort-Object Name | Select-Object -First 1).Name
    }
    $libVictim = (Get-ChildItem -LiteralPath (Join-Path $repoRoot 'global' 'hooks' 'lib') -Filter '*.sh' -File | Sort-Object Name | Select-Object -First 1).Name
    $skillsRoot = Join-Path $repoRoot 'global' 'skills'
    $skillVictim = (Get-ChildItem -LiteralPath $skillsRoot -File -Recurse | Where-Object { $_.Extension -ne '.md' } |
        Sort-Object FullName | Select-Object -First 1).FullName.Substring($skillsRoot.Length + 1) -replace '\\', '/'
    $refRoot = Join-Path $repoRoot 'project' '.claude' 'reference'
    $refVictim = (Get-ChildItem -LiteralPath $refRoot -File -Recurse | Sort-Object FullName |
        Select-Object -First 1).FullName.Substring($refRoot.Length + 1) -replace '\\', '/'

    Remove-Item -LiteralPath (Join-Path $claude 'hooks' $hookVictim)
    Add-Content -LiteralPath (Join-Path $claude 'hooks' 'lib' $libVictim) -Value '# drift'
    Add-Content -LiteralPath (Join-Path $claude 'skills' $skillVictim) -Value 'drift'
    Remove-Item -LiteralPath (Join-Path $proj '.claude' 'reference' $refVictim)
    Add-Content -LiteralPath (Join-Path $proj '.claude' 'rules' 'security.md') -Value 'drift'
    Add-Content -LiteralPath (Join-Path $proj '.claude' 'rules' 'core' 'communication.md') -Value '{{AGENT_LANGUAGE}}'
    $crlf = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'global' 'CLAUDE.md')).Replace("`r`n", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText((Join-Path $claude 'CLAUDE.md'), $crlf, [System.Text.UTF8Encoding]::new($true))

    $out = Invoke-Verify -Dir $proj -Arguments @()
    Assert-Contains $out "MISS: hooks/$hookVictim"
    Assert-Contains $out "DIFF: hooks/lib/$libVictim"
    Assert-Contains $out "DIFF: skills/$skillVictim"
    Assert-Contains $out "MISS: project/.claude/reference/$refVictim"
    Assert-Contains $out 'DIFF: project/.claude/rules/security.md'
    Assert-Contains $out 'DIFF: project/.claude/rules/core/communication.md (unrendered placeholder)'
    $count = (Get-Findings $out).Count
    if ($count -ne 6) {
        throw "FAIL: expected exactly 6 findings, got $count`n$((Get-Findings $out) -join "`n")"
    }
    Write-Host 'drift detection: PASS'

    Write-Host 'All verify sync tests passed!'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
