# test-install-manifest-helpers.ps1

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path

. (Join-Path $repoRoot "scripts\install-manifest.ps1")

$testDir = Join-Path ([System.IO.Path]::GetTempPath()) "claude_test_$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $testDir | Out-Null

try {
    $env:HOME = $testDir
    $claudeDir = Join-Path $testDir ".claude"
    New-Item -ItemType Directory -Path $claudeDir | Out-Null
    
    $manifestPath = Join-Path $claudeDir ".install-manifest.json"
    $env:MANIFEST_PATH = $manifestPath

    # Test Update-ClaudeSettingsJson
    $settingsPath = Join-Path $testDir "settings.json"
    '{"test": 1}' | Set-Content -LiteralPath $settingsPath -Encoding UTF8

    Update-ClaudeSettingsJson -SettingsPath $settingsPath -AgentLang "english" -ContentLang "korean_plus_english" | Out-Null

    $content = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
    if ($content.language -ne "english") {
        throw "FAIL: Agent language not updated"
    }
    if ($content.env.CLAUDE_CONTENT_LANGUAGE -ne "korean_plus_english") {
        throw "FAIL: Content language not updated"
    }
    Write-Host "Update-ClaudeSettingsJson: PASS"

    # Test Invoke-GuardedTemplateCopy
    $tmplPath = Join-Path $testDir "tmpl.md"
    $destPath = Join-Path $testDir "dest.md"
    "Language policy: {{AGENT_LANGUAGE_POLICY}}" | Set-Content -LiteralPath $tmplPath -Encoding UTF8

    $global:ManifestForceOverride = $true

    Invoke-GuardedTemplateCopy -SrcTmpl $tmplPath -Dest $destPath -Key "dest.md" -DisplayLang "Korean" | Out-Null

    $destContent = Get-Content -Raw -LiteralPath $destPath
    if (-not ($destContent -match "Language policy: Korean")) {
        throw "FAIL: Template not rendered properly"
    }

    $manifestContent = Get-Content -Raw -LiteralPath $manifestPath
    if (-not ($manifestContent -match "dest.md")) {
        throw "FAIL: Manifest not updated"
    }

    Write-Host "Invoke-GuardedTemplateCopy: PASS"

    # Test Invoke-ManifestPrune
    $pruneRoot = Join-Path $testDir "prune-root"
    New-Item -ItemType Directory -Path $pruneRoot | Out-Null
    $env:MANIFEST_PATH = Join-Path $pruneRoot ".install-manifest.json"

    $obsoleteClean = Join-Path $pruneRoot "obsolete-clean.md"
    $obsoleteEdited = Join-Path $pruneRoot "obsolete-edited.md"
    $currentManaged = Join-Path $pruneRoot "current.md"
    $outsideFile = Join-Path $testDir "outside.md"

    "old managed content" | Set-Content -LiteralPath $obsoleteClean -Encoding UTF8
    "user baseline content" | Set-Content -LiteralPath $obsoleteEdited -Encoding UTF8
    "current managed content" | Set-Content -LiteralPath $currentManaged -Encoding UTF8
    "outside content" | Set-Content -LiteralPath $outsideFile -Encoding UTF8

    Write-ManifestEntry -Key "obsolete-clean.md" -Sha (Get-FileSha256 -Path $obsoleteClean)
    Write-ManifestEntry -Key "obsolete-edited.md" -Sha (Get-FileSha256 -Path $obsoleteEdited)
    Write-ManifestEntry -Key "missing-old.md" -Sha "abc123"
    Write-ManifestEntry -Key "current.md" -Sha (Get-FileSha256 -Path $currentManaged)
    Write-ManifestEntry -Key "../outside.md" -Sha (Get-FileSha256 -Path $outsideFile)

    "user edited content" | Set-Content -LiteralPath $obsoleteEdited -Encoding UTF8

    $pruneResult = Invoke-ManifestPrune -Root $pruneRoot -ManagedKeys @("current.md")
    if ($pruneResult.Deleted -ne 1) {
        throw "FAIL: prune did not delete exactly one unchanged obsolete file"
    }
    if ($pruneResult.Preserved -ne 1) {
        throw "FAIL: prune did not preserve exactly one locally edited obsolete file"
    }
    if ($pruneResult.Missing -ne 1) {
        throw "FAIL: prune did not remove exactly one missing stale manifest entry"
    }
    if ($pruneResult.Unsafe -ne 1) {
        throw "FAIL: prune did not report exactly one unsafe obsolete path"
    }
    if (Test-Path -LiteralPath $obsoleteClean) {
        throw "FAIL: prune left unchanged obsolete file on disk"
    }
    if (-not (Test-Path -LiteralPath $obsoleteEdited)) {
        throw "FAIL: prune removed locally edited obsolete file"
    }
    if (-not (Test-Path -LiteralPath $currentManaged)) {
        throw "FAIL: prune removed current managed file"
    }
    if (-not (Test-Path -LiteralPath $outsideFile)) {
        throw "FAIL: prune removed file outside managed root"
    }

    $manifestAfterPrune = Get-Content -Raw -LiteralPath $env:MANIFEST_PATH
    if ($manifestAfterPrune -match "obsolete-clean.md") {
        throw "FAIL: prune left deleted obsolete file in manifest"
    }
    if (-not ($manifestAfterPrune -match "obsolete-edited.md")) {
        throw "FAIL: prune removed preserved obsolete file from manifest"
    }
    if ($manifestAfterPrune -match "missing-old.md") {
        throw "FAIL: prune left missing file in manifest"
    }
    if (-not ($manifestAfterPrune -match "current.md")) {
        throw "FAIL: prune removed current managed file from manifest"
    }
    Write-Host "Invoke-ManifestPrune: PASS"

    # Test Copy-ManifestTree + Invoke-ManifestPruneTracked
    $treeRoot = Join-Path $testDir "tree-root"
    $treeSource = Join-Path $testDir "tree-source"
    $env:MANIFEST_PATH = Join-Path $treeRoot ".install-manifest.json"
    New-Item -ItemType Directory -Path (Join-Path $treeSource "nested") -Force | Out-Null
    New-Item -ItemType Directory -Path $treeRoot -Force | Out-Null
    "active" | Set-Content -LiteralPath (Join-Path $treeSource "nested/active.md") -Encoding UTF8
    "stale" | Set-Content -LiteralPath (Join-Path $treeRoot "stale.md") -Encoding UTF8
    Write-ManifestEntry -Key "stale.md" -Sha (Get-FileSha256 -Path (Join-Path $treeRoot "stale.md"))
    Reset-ManifestManagedKeys
    Copy-ManifestTree -SourceDir $treeSource -DestinationDir $treeRoot -KeyPrefix ""
    Invoke-ManifestPruneTracked -Root $treeRoot | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $treeRoot "nested/active.md"))) {
        throw "FAIL: Copy-ManifestTree did not copy active file"
    }
    if (Test-Path -LiteralPath (Join-Path $treeRoot "stale.md")) {
        throw "FAIL: Invoke-ManifestPruneTracked did not prune stale managed file"
    }
    Write-Host "Copy-ManifestTree/Invoke-ManifestPruneTracked: PASS"

    # Test retired ownership seeding
    $retiredRoot = Join-Path $testDir "retired-root"
    $retiredCommands = Join-Path $retiredRoot "commands"
    New-Item -ItemType Directory -Path $retiredCommands -Force | Out-Null
    $retiredFile = Join-Path $retiredCommands "old-command.md"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($retiredFile, "retired upstream command`n", $utf8NoBom)
    $retiredSha = Get-FileSha256 -Path $retiredFile
    [System.IO.File]::WriteAllText($retiredFile, "retired upstream command`r`n", $utf8NoBom)
    $previousManifestPath = $env:MANIFEST_PATH
    $env:MANIFEST_PATH = Join-Path $retiredRoot ".install-manifest.json"
    Add-RetiredManagedManifestEntries -Root $retiredRoot -Entries @{ 'commands/old-command.md' = $retiredSha }
    Invoke-ManifestPrune -Root $retiredRoot -ManagedKeys @('commands/_policy.md') | Out-Null
    $env:MANIFEST_PATH = $previousManifestPath
    if (Test-Path -LiteralPath $retiredFile) {
        throw "FAIL: retired ownership seed did not enable pruning"
    }
    Write-Host "Add-RetiredManagedManifestEntries: PASS"

    # Idempotent reset: english policy must remove .env.CLAUDE_CONTENT_LANGUAGE
    # and prune an empty .env object left over from a prior non-default selection.
    '{"test": 1}' | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    Update-ClaudeSettingsJson -SettingsPath $settingsPath -AgentLang "english" -ContentLang "korean_plus_english" | Out-Null
    $stage1 = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
    if ($stage1.env.CLAUDE_CONTENT_LANGUAGE -ne "korean_plus_english") {
        throw "FAIL: idempotent setup did not write CLAUDE_CONTENT_LANGUAGE"
    }

    Update-ClaudeSettingsJson -SettingsPath $settingsPath -AgentLang "english" -ContentLang "english" | Out-Null
    $stage2 = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
    if ($stage2.PSObject.Properties.Name -contains 'env') {
        throw "FAIL: idempotent reset left an empty .env object"
    }
    $rawAfter = Get-Content -Raw -LiteralPath $settingsPath
    if ($rawAfter -match 'CLAUDE_CONTENT_LANGUAGE') {
        throw "FAIL: idempotent reset did not remove CLAUDE_CONTENT_LANGUAGE"
    }
    Write-Host "Update-ClaudeSettingsJson idempotent reset: PASS"

    Write-Host "All helper tests passed!"
} finally {
    Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
}
