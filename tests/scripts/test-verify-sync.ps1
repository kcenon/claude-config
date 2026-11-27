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
    $settingsProfile = Join-Path $repoRoot 'global' $profileName
    # This .claude has no memory sync, so the installers publish the profile
    # without the memory hooks (#1024). Their own helper drops them here too.
    Remove-Item Env:CLAUDE_MEMORY_REPO_URL -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $settingsProfile -Destination (Join-Path $claude 'settings.json')
    & {
        . (Join-Path $repoRoot 'scripts' 'install-manifest.ps1')
        Remove-MemoryHooksUnlessSynced -SettingsPath (Join-Path $claude 'settings.json') -ClaudeDir $claude | Out-Null
    }
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

    # 3. commit-settings.md is deployed rendered from its .tmpl for the content
    # policy, so verify compares it with the rendering for the policy the
    # installed settings.json records, not with the english-canonical .md
    # (#974).
    Import-Module (Join-Path $repoRoot 'scripts' 'lib' 'InstallPrompts.psm1') -Force -DisableNameChecking
    $settingsPath = Join-Path $claude 'settings.json'
    $settingsOrig = [System.IO.File]::ReadAllText($settingsPath)
    $settings = $settingsOrig | ConvertFrom-Json
    $settings.env | Add-Member -NotePropertyName 'CLAUDE_CONTENT_LANGUAGE' -NotePropertyValue 'exclusive_bilingual' -Force
    [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 32), $utf8NoBom)
    Invoke-PolicyTemplate -Source (Join-Path $repoRoot 'global' 'commit-settings.md.tmpl') `
        -Destination (Join-Path $claude 'commit-settings.md') -ContentLanguage 'exclusive_bilingual'
    $out = Invoke-Verify -Dir $proj -Arguments @()
    if ((Get-Findings $out).Count -ne 0) {
        throw "FAIL: an exclusive_bilingual install reported differences`n$((Get-Findings $out) -join "`n")"
    }
    Assert-Contains $out 'SYNC: commit-settings.md (rendered: exclusive_bilingual)'
    [System.IO.File]::WriteAllText($settingsPath, $settingsOrig, $utf8NoBom)
    $out = Invoke-Verify -Dir $proj -Arguments @()
    Assert-Contains $out 'DIFF: commit-settings.md (rendered: english)'
    if ((Get-Findings $out).Count -ne 1) {
        throw "FAIL: expected exactly 1 finding for a policy mismatch`n$((Get-Findings $out) -join "`n")"
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'global' 'commit-settings.md') -Destination (Join-Path $claude 'commit-settings.md') -Force
    Write-Host 'rendered commit-settings.md: PASS'

    # 4. settings.json is compared with the profile as this machine receives
    # it (#1024). Without memory sync, a deployed file that still registers the
    # memory hooks is stale; with <ClaudeDir>/memory-shared it is what the
    # installer writes.
    $settingsPath = Join-Path $claude 'settings.json'
    $settingsDropped = [System.IO.File]::ReadAllText($settingsPath)
    if ($settingsDropped.Contains('memory-')) {
        throw 'FAIL: the staged settings.json still has a memory hook'
    }
    Copy-Item -LiteralPath $settingsProfile -Destination $settingsPath -Force
    $out = Invoke-Verify -Dir $proj -Arguments @()
    Assert-Contains $out 'DIFF: settings.json (hooks + permissions) -- hooks'
    $sharedDir = Join-Path $claude 'memory-shared'
    New-Item -ItemType Directory -Path $sharedDir | Out-Null
    $out = Invoke-Verify -Dir $proj -Arguments @()
    if ((Get-Findings $out).Count -ne 0) {
        throw "FAIL: with memory-shared, the full profile reported differences`n$((Get-Findings $out) -join "`n")"
    }
    Assert-Contains $out 'SYNC: settings.json (hooks + permissions)'
    Remove-Item -LiteralPath $sharedDir -Force
    [System.IO.File]::WriteAllText($settingsPath, $settingsDropped, $utf8NoBom)
    Write-Host 'memory hooks in settings.json: PASS'

    # 4c. A deployed settings.json that lost the `_note` keys of the profile
    # still registers the profile's hooks, so it is in sync; a changed timeout
    # is not (#1063).
    if (-not $settingsDropped.Contains('"_note"')) {
        throw 'FAIL: the staged settings.json has no _note to drop'
    }
    $settings = $settingsDropped | ConvertFrom-Json
    foreach ($evt in $settings.hooks.PSObject.Properties) {
        foreach ($group in $evt.Value) { $group.PSObject.Properties.Remove('_note') }
    }
    $noNotes = $settings | ConvertTo-Json -Depth 32
    if ($noNotes.Contains('"_note"')) { throw 'FAIL: the _note keys were not dropped' }
    [System.IO.File]::WriteAllText($settingsPath, $noNotes, $utf8NoBom)
    $out = Invoke-Verify -Dir $proj -Arguments @()
    if ((Get-Findings $out).Count -ne 0) {
        throw "FAIL: a settings.json without _note keys reported differences`n$((Get-Findings $out) -join "`n")"
    }
    Assert-Contains $out 'SYNC: settings.json (hooks + permissions)'
    $settings = $settingsDropped | ConvertFrom-Json
    foreach ($evt in $settings.hooks.PSObject.Properties) {
        foreach ($group in $evt.Value) {
            foreach ($handler in $group.hooks) {
                if ($handler.PSObject.Properties['timeout']) { $handler.timeout = $handler.timeout + 1 }
            }
        }
    }
    [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 32), $utf8NoBom)
    $out = Invoke-Verify -Dir $proj -Arguments @()
    Assert-Contains $out 'DIFF: settings.json (hooks + permissions) -- hooks'
    [System.IO.File]::WriteAllText($settingsPath, $settingsDropped, $utf8NoBom)
    Write-Host '_note keys left out of the hooks comparison: PASS'

    # 5. Each kind of drift is reported; a CRLF and BOM rewrite is not.
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
    Add-Content -LiteralPath (Join-Path $proj '.claude' 'rules' 'coding' 'essentials.md') -Value 'drift'
    Add-Content -LiteralPath (Join-Path $proj '.claude' 'rules' 'core' 'communication.md') -Value '{{AGENT_LANGUAGE}}'
    $crlf = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'global' 'CLAUDE.md')).Replace("`r`n", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText((Join-Path $claude 'CLAUDE.md'), $crlf, [System.Text.UTF8Encoding]::new($true))

    $out = Invoke-Verify -Dir $proj -Arguments @()
    Assert-Contains $out "MISS: hooks/$hookVictim"
    Assert-Contains $out "DIFF: hooks/lib/$libVictim"
    Assert-Contains $out "DIFF: skills/$skillVictim"
    Assert-Contains $out "MISS: project/.claude/reference/$refVictim"
    Assert-Contains $out 'DIFF: project/.claude/rules/coding/essentials.md'
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
