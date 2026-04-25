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
    Set-ManifestPath $manifestPath

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
