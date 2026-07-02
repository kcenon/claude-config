#Requires -Version 7.0
<#
Regression tests for the PowerShell installer prompt helpers.

Run:
  pwsh -NoProfile -File tests/scripts/test-install-prompts-ps1.ps1
#>

$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$ModulePath = Join-Path $RootDir 'scripts/lib/InstallPrompts.psm1'
Import-Module $ModulePath -Force -DisableNameChecking

$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Check-Equal {
    param(
        [string]$Name,
        [string]$Expected,
        [AllowNull()][string]$Actual
    )
    if ($Expected -eq $Actual) {
        $script:Passed++
        Write-Host "  PASS: $Name" -ForegroundColor Green
    }
    else {
        $script:Failed++
        $script:Errors.Add("FAIL: ${Name}: expected '$Expected', got '$Actual'")
        Write-Host "  FAIL: $Name" -ForegroundColor Red
        Write-Host "    expected: $Expected"
        Write-Host "    actual:   $Actual"
    }
}

function Check-True {
    param([string]$Name, [bool]$Actual)
    Check-Equal -Name $Name -Expected 'True' -Actual ([string]$Actual)
}

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "install-prompts-ps1-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    $settings = Join-Path $tmpDir 'settings.json'
    @'
{
  "language": "english",
  "env": {
    "CLAUDE_CONTENT_LANGUAGE": "exclusive_bilingual"
  }
}
'@ | Set-Content -LiteralPath $settings -NoNewline

    Write-Host '=== InstallPrompts.psm1 language seed tests ==='
    Write-Host ''

    Write-Host '[settings readers]'
    Check-Equal 'read agent language' 'english' (Read-SettingsAgentLanguage -Path $settings)
    Check-Equal 'read content language' 'exclusive_bilingual' (Read-SettingsContentLanguage -Path $settings)

    Write-Host ''
    Write-Host '[reinstall seed]'
    $seed = Seed-LanguageFromSettings -SettingsPath $settings -AgentLanguage '' -ContentLanguage ''
    Check-True 'seed reports changed values' $seed.Seeded
    Check-Equal 'seed agent from settings' 'english' $seed.AgentLanguage
    Check-Equal 'seed content from settings' 'exclusive_bilingual' $seed.ContentLanguage

    $profile = Show-LanguageProfilePrompt -AgentLanguage $seed.AgentLanguage -ContentLanguage $seed.ContentLanguage
    Check-Equal 'profile keeps seeded agent' 'english' $profile.AgentLanguage
    Check-Equal 'profile keeps seeded content' 'exclusive_bilingual' $profile.ContentLanguage
    Check-Equal 'profile display follows seeded agent' 'English' $profile.AgentDisplay

    Write-Host ''
    Write-Host '[env override wins independently]'
    $seed = Seed-LanguageFromSettings -SettingsPath $settings -AgentLanguage 'korean' -ContentLanguage ''
    Check-Equal 'explicit agent preserved' 'korean' $seed.AgentLanguage
    Check-Equal 'unset content seeded' 'exclusive_bilingual' $seed.ContentLanguage

    Write-Host ''
    Write-Host '[regex fallback on invalid JSON]'
    Set-Content -LiteralPath $settings -NoNewline -Value '{ "language": "korean", "env": { "CLAUDE_CONTENT_LANGUAGE": "english" }'
    Check-Equal 'fallback reads agent language' 'korean' (Read-SettingsAgentLanguage -Path $settings)
    Check-Equal 'fallback reads content language' 'english' (Read-SettingsContentLanguage -Path $settings)
}
finally {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) { Write-Host "  $err" }
    exit 1
}
exit 0
