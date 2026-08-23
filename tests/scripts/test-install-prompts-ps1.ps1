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

    Write-Host ''
    Write-Host '[Set-GitIdentitySeed (#916)]'
    # GIT_CONFIG_GLOBAL keeps these deterministic and lets the "no git config"
    # branch be exercised without touching the developer's real config.
    $savedGitConfig = $env:GIT_CONFIG_GLOBAL
    try {
        $gitCfg = Join-Path $tmpDir 'fake-gitconfig'
        Set-Content -LiteralPath $gitCfg -Value "[user]`n`tname = Ada `$1 Lovelace`n`temail = ada@example.org`n"
        $env:GIT_CONFIG_GLOBAL = $gitCfg

        $identity = Join-Path $tmpDir 'git-identity.md'
        $body = @(
            '# Git Identity',
            '',
            'The installer auto-seeds the two fields below. If either git-config',
            'value is missing, replace the `YOUR NAME` / `YOUR EMAIL` placeholders',
            'by hand.',
            '',
            'name: YOUR NAME',
            'email: YOUR EMAIL',
            ''
        ) -join "`n"
        Set-Content -LiteralPath $identity -NoNewline -Value $body

        $result = Set-GitIdentitySeed -Path $identity
        $lines = (Get-Content -Raw -LiteralPath $identity) -split "`n"

        Check-Equal 'seeds the name field'  'name: Ada $1 Lovelace' $lines[6]
        Check-Equal 'seeds the email field' 'email: ada@example.org' $lines[7]
        # The defect: a document-wide replace rewrote the sentence that names
        # the placeholders, leaving it pointing at the substituted values.
        Check-Equal 'leaves the explanatory sentence intact' `
            'value is missing, replace the `YOUR NAME` / `YOUR EMAIL` placeholders' $lines[3]
        # A literal insert, not a regex substitution: `$1` must survive.
        Check-True 'inserts the name literally' ($lines[6] -like '*Ada $1 Lovelace*')
        # The function is in a module, so $script: cannot reach the caller.
        Check-Equal 'returns the seeded name'  'Ada $1 Lovelace'  $result.Name
        Check-Equal 'returns the seeded email' 'ada@example.org' $result.Email

        # Second run: the field lines no longer hold placeholders, so nothing is
        # seeded even though the sentence still mentions the tokens.
        $before = Get-Content -Raw -LiteralPath $identity
        $again = Set-GitIdentitySeed -Path $identity
        Check-True 'second run reports nothing seeded' ($null -eq $again)
        Check-Equal 'second run leaves the file byte-identical' $before (Get-Content -Raw -LiteralPath $identity)

        # CRLF checkout: line endings survive the rewrite.
        $crlf = Join-Path $tmpDir 'git-identity-crlf.md'
        [System.IO.File]::WriteAllText($crlf, ($body -replace "`n", "`r`n"))
        $null = Set-GitIdentitySeed -Path $crlf
        $crlfRaw = [System.IO.File]::ReadAllText($crlf)
        Check-True 'CRLF endings preserved' ($crlfRaw -like "*name: Ada `$1 Lovelace`r`n*")
        Check-True 'no bare LF introduced' (-not (($crlfRaw -replace "`r`n", '').Contains("`n")))

        # No git config at all: no-op, file untouched.
        Set-Content -LiteralPath $gitCfg -Value ''
        $fresh = Join-Path $tmpDir 'git-identity-nocfg.md'
        Set-Content -LiteralPath $fresh -NoNewline -Value $body
        $none = Set-GitIdentitySeed -Path $fresh
        Check-True 'missing git config seeds nothing' ($null -eq $none)
        Check-Equal 'missing git config leaves the file untouched' $body (Get-Content -Raw -LiteralPath $fresh)
    }
    finally {
        $env:GIT_CONFIG_GLOBAL = $savedGitConfig
    }
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
