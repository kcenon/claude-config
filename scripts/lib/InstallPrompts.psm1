# scripts/lib/InstallPrompts.psm1
# Shared installer prompts. Imported by bootstrap.ps1 and scripts/install.ps1.
# Mirror of scripts/lib/install-prompts.sh; both files are the single source
# of truth for prompt strings and value mappings. Drift between the two
# implementations is guarded by tests/scripts/test-installer-prompt-drift.sh.
#
# Mapping rationale (see docs/content-language-policy.md):
#   Agent Conversation Language fixes the language of Claude's dialogue.
#     English -> english
#     Korean  -> korean
#   Content Language fixes the language of artifacts (commits, PRs,
#   issues, comments, generated documents).
#     English -> english             (ASCII only, no Hangul)
#     Korean  -> exclusive_bilingual (per-artifact strict, no inline mix)
#   Legacy values korean_plus_english and any are not surfaced in the
#   simplified UI; advanced users may set them directly in settings.json.

# Internal helpers. PowerShell modules cannot see the importer's script
# scope by default, so we ship a self-contained Write-Info/Write-Warn
# pair styled to match the existing installers (Cyan for info, Yellow
# for warn).
function Script:Write-PromptInfo {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Cyan
}

function Script:Write-PromptWarn {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Yellow
}

function Show-AgentLanguagePrompt {
    [CmdletBinding()]
    param()

    Write-Host ""
    Script:Write-PromptInfo "Select Agent Conversation Language:"
    Write-Host "  1) English"
    Write-Host "  2) Korean"
    Write-Host ""

    $sel = Read-Host "Selection (1-2) [default: 2]"
    if ([string]::IsNullOrEmpty($sel)) { $sel = '2' }

    switch ($sel) {
        '1'     { return [pscustomobject]@{ Language = 'english'; Display = 'English' } }
        '2'     { return [pscustomobject]@{ Language = 'korean';  Display = 'Korean'  } }
        default {
            Script:Write-PromptWarn "Unknown selection: $sel. Falling back to korean."
            return [pscustomobject]@{ Language = 'korean'; Display = 'Korean' }
        }
    }
}

function Show-ContentLanguagePrompt {
    [CmdletBinding()]
    param()

    Write-Host ""
    Script:Write-PromptInfo "Select Content Language (artifact validation scope):"
    Script:Write-PromptInfo "  Locks the language of generated documents, commits, PRs, issues, and comments."
    Write-Host "  1) English (ASCII only - no Hangul allowed in artifacts)"
    Write-Host "  2) Korean  (per-artifact strict - Hangul or English document, no inline mixing)"
    Write-Host ""

    $sel = Read-Host "Selection (1-2) [default: 1]"
    if ([string]::IsNullOrEmpty($sel)) { $sel = '1' }

    switch ($sel) {
        '1'     { return 'english' }
        '2'     { return 'exclusive_bilingual' }
        default {
            Script:Write-PromptWarn "Unknown selection: $sel. Falling back to english."
            return 'english'
        }
    }
}

function Get-PolicyPhrase {
    # Maps a CLAUDE_CONTENT_LANGUAGE value to the short phrase substituted
    # into rule documents at install time (issue #411).
    # Callers must pass -Policy explicitly: PowerShell modules have their
    # own $script: scope, so the importer's $script:contentLanguage is not
    # visible here. Empty input falls back to "english".
    [CmdletBinding()]
    param([string]$Policy = 'english')

    if (-not $Policy) { $Policy = 'english' }
    switch ($Policy) {
        'english'             { return 'English' }
        'korean_plus_english' { return 'English or Korean' }
        'exclusive_bilingual' { return 'English or Korean (document-exclusive)' }
        'any'                 { return 'any language' }
        default               { return 'English' }
    }
}

function Get-AllPolicyValues {
    # Emits the four canonical CLAUDE_CONTENT_LANGUAGE values.
    # Used by the drift test to iterate without hard-coding the list.
    return @('english', 'korean_plus_english', 'exclusive_bilingual', 'any')
}

function Test-LegacyContentLanguage {
    # True when the given value is a legacy policy not surfaced in the
    # simplified UI. Used by installers to warn on existing settings.json
    # values that the operator may not realize are legacy.
    [CmdletBinding()]
    param([string]$Value)

    return ($Value -eq 'korean_plus_english') -or ($Value -eq 'any')
}

function Read-SettingsContentLanguage {
    # Reads the current CLAUDE_CONTENT_LANGUAGE value from a settings.json
    # file. Returns empty string when missing or unparseable. ConvertFrom-Json
    # is preferred; we fall back to a regex scan when the file is invalid
    # JSON to avoid masking installer state with parse errors.
    [CmdletBinding()]
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        $json = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop
        if ($json.env -and $json.env.CLAUDE_CONTENT_LANGUAGE) {
            return [string]$json.env.CLAUDE_CONTENT_LANGUAGE
        }
        return ''
    } catch {
        $line = (Select-String -LiteralPath $Path -Pattern '"CLAUDE_CONTENT_LANGUAGE"\s*:\s*"([^"]*)"' -List).Matches
        if ($line) { return $line[0].Groups[1].Value }
        return ''
    }
}

function Show-LegacySettingsWarning {
    # Prints a warning when settings.json holds a legacy CLAUDE_CONTENT_LANGUAGE
    # value the simplified UI no longer surfaces. Returns $true when warned.
    # Informational only - the installer continues with the new selection.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [string]$NewSelection = 'english'
    )

    $current = Read-SettingsContentLanguage -Path $SettingsPath
    if (-not (Test-LegacyContentLanguage -Value $current)) { return $false }

    Script:Write-PromptWarn "Legacy CLAUDE_CONTENT_LANGUAGE detected: '$current'"
    Script:Write-PromptWarn "  This value is still accepted by the validator but is no"
    Script:Write-PromptWarn "  longer surfaced in the installer UI. Your new selection"
    Script:Write-PromptWarn "  ('$NewSelection') will replace it. To keep '$current',"
    Script:Write-PromptWarn "  cancel now and edit ~/.claude/settings.json directly"
    Script:Write-PromptWarn "  without rerunning the installer."
    return $true
}

Export-ModuleMember -Function Show-AgentLanguagePrompt, Show-ContentLanguagePrompt, Get-PolicyPhrase, Get-AllPolicyValues, Test-LegacyContentLanguage, Read-SettingsContentLanguage, Show-LegacySettingsWarning
