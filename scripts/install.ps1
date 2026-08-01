# Claude Configuration Auto-Installer (PowerShell)
# =================================================
# Installs backed up CLAUDE.md settings to a new Windows system
# Requires: PowerShell 7+ (pwsh) recommended

#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Script and backup directory paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupDir = Split-Path -Parent $ScriptDir

# ── Helper functions ──────────────────────────────────────────

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Red
}

function Ensure-Directory {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        Write-Success "Directory created: $Dir"
    }
}

function Install-BashScript {
    # Copy a .sh file with UTF-8 (no BOM) encoding and LF-only line endings.
    # Windows PowerShell's default Copy-Item preserves CRLF, which makes the
    # script fail when executed by bash in a Linux container bind-mounted
    # from a Windows host. See Issue #407.
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $content = [System.IO.File]::ReadAllText($SourcePath) -replace "`r`n", "`n"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($DestinationPath, $content, $utf8NoBom)
}

function Ensure-InstallDirectory {
    param([Parameter(Mandatory)][string]$Dir)

    if (Test-Path -LiteralPath $Dir -PathType Container) { return }
    if (Test-Path -LiteralPath $Dir) {
        throw "path exists but is not a directory: $Dir"
    }
    New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop | Out-Null
}

function Copy-InstallHookFiles {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$DestinationDir,
        [Parameter(Mandatory)][string[]]$Filters,
        [string]$KeyPrefix = ''
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) { return }
    Ensure-InstallDirectory -Dir $DestinationDir

    foreach ($filter in $Filters) {
        Get-ChildItem -LiteralPath $SourceDir -Filter $filter -File -ErrorAction SilentlyContinue | ForEach-Object {
            $dest = Join-Path $DestinationDir $_.Name
            if ($KeyPrefix -and (Get-Command Invoke-ManifestTrackedCopy -ErrorAction SilentlyContinue)) {
                $key = (($KeyPrefix, $_.Name) -join '/') -replace '\\', '/'
                if ($_.Extension -eq '.sh') {
                    $tmpScript = Join-Path ([System.IO.Path]::GetTempPath()) "claude-script-$([guid]::NewGuid()).sh"
                    Install-BashScript -SourcePath $_.FullName -DestinationPath $tmpScript
                    $null = Invoke-ManifestTrackedCopy -Src $tmpScript -Dest $dest -Key $key
                    Remove-Item -LiteralPath $tmpScript -Force -ErrorAction SilentlyContinue
                } else {
                    $null = Invoke-ManifestTrackedCopy -Src $_.FullName -Dest $dest -Key $key
                }
            } else {
                if ($_.Extension -eq '.sh') {
                    Install-BashScript -SourcePath $_.FullName -DestinationPath $dest
                } else {
                    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop
                }
            }
        }
    }
}

function Deploy-InstallHooks {
    param([Parameter(Mandatory)][string]$ClaudeDir)

    $hooksSource = Join-Path $BackupDir "global/hooks"
    if (-not (Test-Path -LiteralPath $hooksSource -PathType Container)) {
        throw "hook source directory missing: $hooksSource"
    }

    $hooksDir = Join-Path $ClaudeDir "hooks"
    # Windows hooks use `pwsh -File ...ps1`; .sh/.json are deployed for WSL and
    # parity with container-side command rewriting.
    Copy-InstallHookFiles -SourceDir $hooksSource -DestinationDir $hooksDir -Filters @('*.ps1', '*.sh', '*.json') -KeyPrefix 'hooks'

    # Deploy global/hooks/lib/ shared libraries. The top-level hook copy is
    # non-recursive, and several runtime guards source these libraries.
    $hooksLibSource = Join-Path $hooksSource 'lib'
    if (Test-Path -LiteralPath $hooksLibSource -PathType Container) {
        $hooksLibDir = Join-Path $hooksDir 'lib'
        Copy-InstallHookFiles -SourceDir $hooksLibSource -DestinationDir $hooksLibDir -Filters @('*.ps1', '*.psm1', '*.sh') -KeyPrefix 'hooks/lib'
    }

    # Shared bash validator libraries used by deployed bash hook variants.
    $sharedLibSource = Join-Path $BackupDir 'hooks/lib'
    if (Test-Path -LiteralPath $sharedLibSource -PathType Container) {
        $hooksLibDir = Join-Path $hooksDir 'lib'
        Copy-InstallHookFiles -SourceDir $sharedLibSource -DestinationDir $hooksLibDir -Filters @(
            'validate-commit-message.sh',
            'validate-language.sh',
            'validate-traceability.sh'
        ) -KeyPrefix 'hooks/lib'
    }

    $requiredLibs = @(
        'tokenize-shell.sh',
        'path-utils.sh',
        'timeout-wrapper.sh',
        'rotate.sh',
        'CommonHelpers.psm1',
        'LanguageValidator.psm1',
        'AttributionValidator.psm1',
        'validate-commit-message.sh',
        'validate-language.sh',
        'validate-traceability.sh'
    )
    foreach ($lib in $requiredLibs) {
        if (-not (Test-Path -LiteralPath (Join-Path $hooksDir 'lib' $lib) -PathType Leaf)) {
            throw "required hook runtime library missing after deploy: hooks/lib/$lib"
        }
    }
}

function Write-FullSuiteProbe {
    param([Parameter(Mandatory)][string]$ClaudeDir)

    $hooksDir = Join-Path $ClaudeDir "hooks"
    $probeFile = Join-Path $ClaudeDir ".full-suite-active"
    $probeTmp  = Join-Path $ClaudeDir ".full-suite-active.tmp"
    $probeDoc  = [ordered]@{
        schema = 1
        hooks  = [ordered]@{
            'sensitive-file-guard'    = (Test-Path (Join-Path $hooksDir 'sensitive-file-guard.sh'))
            'dangerous-command-guard' = (Test-Path (Join-Path $hooksDir 'dangerous-command-guard.sh'))
        }
    }

    try {
        ($probeDoc | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $probeTmp -Encoding UTF8
        Move-Item -LiteralPath $probeTmp -Destination $probeFile -Force
        Write-Success "Full-suite probe written (.full-suite-active)"
    }
    catch {
        Write-Warn "Failed to write full-suite probe: $_"
        if (Test-Path $probeTmp) { Remove-Item -LiteralPath $probeTmp -Force -ErrorAction SilentlyContinue }
    }
}

function Install-GlobalSettingsAndHooks {
    param([Parameter(Mandatory)][string]$ClaudeDir)

    # Intentionally bypasses Invoke-GuardedCopy: policy attributes (.language,
    # .env.CLAUDE_CONTENT_LANGUAGE) must be enforced on every install.
    # Update-ClaudeSettingsJson injects them into a staged file first; the
    # final settings.json is published only after hook deployment succeeds.
    $settingsSource = Join-Path $BackupDir "global/settings.windows.json"
    if (-not (Test-Path -LiteralPath $settingsSource)) {
        $hooksSource = Join-Path $BackupDir "global/hooks"
        if (Test-Path -LiteralPath $hooksSource -PathType Container) {
            try {
                Deploy-InstallHooks -ClaudeDir $ClaudeDir
                Write-Success "Hook scripts installed (hooks/*.ps1 + *.sh + lib/ + *.json)!"
                Write-FullSuiteProbe -ClaudeDir $ClaudeDir
            }
            catch {
                Write-Err "Hook scripts deployment failed. $_"
                exit 1
            }
        }
        return
    }

    $destSettings = Join-Path $ClaudeDir "settings.json"
    $settingsTmp = Join-Path $ClaudeDir ".settings.json.tmp.$PID"
    $settingsUpdated = $false

    try {
        Remove-Item -LiteralPath $settingsTmp -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $settingsSource -Destination $settingsTmp -Force -ErrorAction Stop

        $settingsUpdated = Update-ClaudeSettingsJson -SettingsPath $settingsTmp -AgentLang $agentLanguage -ContentLang $contentLanguage

        Deploy-InstallHooks -ClaudeDir $ClaudeDir

        Move-Item -LiteralPath $settingsTmp -Destination $destSettings -Force -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $settingsTmp -Force -ErrorAction SilentlyContinue
        Write-Err "Hook scripts deployment or settings publish failed. settings.json을 변경하지 않았습니다. $_"
        exit 1
    }

    Write-Success "Hook settings (settings.json) installed! [Windows version]"
    if ($settingsUpdated) {
        Write-Success "settings.json updated with language=$agentLanguage and CLAUDE_CONTENT_LANGUAGE=$contentLanguage"
    } else {
        Write-Warn "Failed to automatically update settings.json"
        Write-Host "  Please update ~/.claude/settings.json manually with language settings."
    }

    Write-Success "Hook scripts installed (hooks/*.ps1 + *.sh + lib/ + *.json)!"
    Write-FullSuiteProbe -ClaudeDir $ClaudeDir
}

function New-LocalClaude {
    param([string]$ProjectDir)
    $localFile = Join-Path $ProjectDir "CLAUDE.local.md"
    $templateFile = Join-Path $BackupDir "project/CLAUDE.local.md.template"

    # Create CLAUDE.local.md from template if not exists
    if (-not (Test-Path $localFile)) {
        if (Test-Path $templateFile) {
            Copy-Item -Path $templateFile -Destination $localFile -Force
            Write-Success "Created $localFile from template"
        }
    } else {
        Write-Info "CLAUDE.local.md already exists, skipping..."
    }

    # Ensure gitignore entry
    $gitignore = Join-Path $ProjectDir ".gitignore"
    if (Test-Path $gitignore) {
        $content = Get-Content $gitignore -Raw -ErrorAction SilentlyContinue
        if ($content -notmatch 'CLAUDE\.local\.md') {
            Add-Content -Path $gitignore -Value "`n# Claude Code local settings (personal, do not commit)`nCLAUDE.local.md"
            Write-Success "Added CLAUDE.local.md to .gitignore"
        }
    }
}

# Note: Get-PolicyPhrase, Invoke-PolicyTemplate, and Invoke-PolicyTemplatesInDir
# are provided by scripts/lib/InstallPrompts.psm1, imported in the language-prompt
# section below. The render helpers were moved into the module (issue #760) so
# the bootstrap install path can render the copied rules too; both install.ps1
# and bootstrap.ps1 now call the same single source. Because PowerShell modules
# have their own $script: scope, callers pass the three language values
# explicitly (-ContentLanguage/-AgentDisplay/-AgentLanguage). The bash,
# PowerShell, and drift-test tables stay in lockstep.

function Get-EnterpriseDir {
    if ($IsWindows -or ($env:OS -eq 'Windows_NT')) {
        return "C:\Program Files\ClaudeCode"
    } elseif ($IsMacOS) {
        return "/Library/Application Support/ClaudeCode"
    } else {
        return "/etc/claude-code"
    }
}

function Test-Administrator {
    if ($IsWindows -or ($env:OS -eq 'Windows_NT')) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } else {
        return ($(id -u) -eq 0)
    }
}

# Verify Claude Code CLI presence and offer interactive installation.
# version-check.ps1 hook and batch-* scripts call `claude --version` / `claude`
# directly; deploying configuration without the CLI causes silent failures.
# Uses Anthropic's official native installer (recommended method).
# Reference: https://code.claude.com/docs/en/setup
function Confirm-ClaudeCli {
    Write-Info "Checking Claude Code CLI..."

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        try {
            $ccVersion = (& claude --version 2>$null | Select-Object -First 1)
        }
        catch {
            $ccVersion = $null
        }
        if ([string]::IsNullOrWhiteSpace($ccVersion)) { $ccVersion = 'version unknown' }
        Write-Success "Claude Code CLI already installed: $ccVersion"
        return
    }

    Write-Warn "Claude Code CLI is not installed."
    Write-Host "  Hooks (version-check) and batch scripts (issue-work, pr-work) call the"
    Write-Host "  'claude' command directly. Some features will not work without it."
    Write-Host ""

    $installClaude = Read-Host "Install Claude Code CLI now? (y/n) [default: y]"
    if ([string]::IsNullOrEmpty($installClaude)) { $installClaude = 'y' }

    if ($installClaude -ne 'y') {
        Write-Warn "Skipping Claude Code CLI install. Manual install:"
        Write-Host "    irm https://claude.ai/install.ps1 | iex"
        return
    }

    # Native installer is the official recommended method and supports background auto-update.
    # Install path: $env:USERPROFILE\.local\bin\claude.exe (Windows) /
    #               ~/.local/bin/claude (macOS, Linux, WSL)
    $installerUrl = 'https://claude.ai/install.ps1'
    Write-Info "Running native installer: $installerUrl"
    try {
        $installerScript = Invoke-RestMethod -Uri $installerUrl -ErrorAction Stop
        Invoke-Expression $installerScript

        # The newly created ~/.local/bin may not yet be on PATH for this session.
        $localBin = Join-Path $HOME '.local' 'bin'
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
            if (Test-Path $localBin) {
                $env:PATH = "$localBin$([System.IO.Path]::PathSeparator)$env:PATH"
            }
        }

        if (Get-Command claude -ErrorAction SilentlyContinue) {
            try {
                $ccVersion = (& claude --version 2>$null | Select-Object -First 1)
            }
            catch {
                $ccVersion = $null
            }
            if ([string]::IsNullOrWhiteSpace($ccVersion)) { $ccVersion = 'version unknown' }
            Write-Success "Claude Code CLI installed: $ccVersion"
            $claudePath = (Get-Command claude -ErrorAction SilentlyContinue).Source
            if ($claudePath) { Write-Host "  Install location: $claudePath" }
        }
        else {
            Write-Warn "Native installer finished but 'claude' is not on PATH."
            Write-Host "  Open a new PowerShell session or refresh your PATH."
        }
    }
    catch {
        Write-Warn "Claude Code CLI auto-install failed: $($_.Exception.Message)"
        Write-Host "  Manual install: irm https://claude.ai/install.ps1 | iex"
        Write-Host "  Or follow the official guide: https://code.claude.com/docs/en/setup"
    }
}

# ── Enterprise installation ──────────────────────────────────

function Install-Enterprise {
    $enterpriseDir = Get-EnterpriseDir

    Write-Host ""
    Write-Host "======================================================"
    Write-Info "Enterprise settings installation..."
    Write-Host "======================================================"
    Write-Host ""

    # Check if template has been customized
    $enterpriseMd = Join-Path $BackupDir "enterprise/CLAUDE.md"
    if (Test-Path $enterpriseMd) {
        $content = Get-Content $enterpriseMd -Raw -ErrorAction SilentlyContinue
        if ($content -match '^\*This is a template\.') {
            Write-Host ""
            Write-Warn "============================================================"
            Write-Warn "enterprise/CLAUDE.md has NOT been customized yet!"
            Write-Warn "============================================================"
            Write-Host ""
            Write-Host "The managed policy path has the HIGHEST priority in Claude Code." -ForegroundColor Yellow
            Write-Host "Deploying an uncustomized template will enforce requirements" -ForegroundColor Yellow
            Write-Host "that have no supporting implementation:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  - GPG signing for all commits (no guidance configured)"
            Write-Host "  - Sign-off required (--signoff not mentioned elsewhere)"
            Write-Host "  - 80% test coverage minimum (conflicts with testing.md)"
            Write-Host "  - Security team approval (no process defined)"
            Write-Host "  - Squash merge preferred (not in PR guidelines)"
            Write-Host ""
            Write-Host "Recommendation: Customize enterprise/CLAUDE.md first, then re-run." -ForegroundColor Yellow
            Write-Host ""

            $deployTemplate = Read-Host "Deploy uncustomized template anyway? (y/n) [default: n]"
            if ([string]::IsNullOrEmpty($deployTemplate)) { $deployTemplate = 'n' }
            if ($deployTemplate -ne 'y') {
                Write-Info "Enterprise installation skipped. Customize enterprise/CLAUDE.md first."
                return
            }
            Write-Warn "Proceeding with uncustomized template deployment."
        }
    }

    Write-Info "Enterprise path: $enterpriseDir"
    Write-Warn "Administrator privileges may be required."
    Write-Host ""

    # Check admin rights on Windows
    if (($IsWindows -or ($env:OS -eq 'Windows_NT')) -and -not (Test-Administrator)) {
        Write-Err "This operation requires administrator privileges."
        Write-Info "Please run PowerShell as Administrator and try again."
        Write-Info "  Right-click PowerShell -> 'Run as administrator'"
        return
    }

    # Create directories
    New-Item -ItemType Directory -Path $enterpriseDir -Force | Out-Null
    $rulesDir = Join-Path $enterpriseDir "rules"
    New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null

    # Copy files
    Copy-Item -Path $enterpriseMd -Destination $enterpriseDir -Force
    Write-Success "CLAUDE.md installed"

    # Copy rules directory
    $sourceRules = Join-Path $BackupDir "enterprise/rules"
    if (Test-Path $sourceRules) {
        $items = Get-ChildItem -Path $sourceRules
        if ($items.Count -gt 0) {
            try {
                Copy-Item -Path "$sourceRules\*" -Destination $rulesDir -Recurse -Force -ErrorAction Stop
                Write-Success "rules directory installed"
            } catch {
                Write-Err "Failed to copy rules: $_"
            }
        }
    }

    Write-Success "Enterprise settings installation complete!"
    Write-Host ""
    Write-Warn "Important: Customize enterprise/CLAUDE.md for your organization's policies!"
}

# ── Banner ────────────────────────────────────────────────────

Write-Host ""
Write-Host "==================================================" -ForegroundColor Blue
Write-Host "                                                    " -ForegroundColor Blue
Write-Host "    Claude Configuration Auto-Installer             " -ForegroundColor Blue
Write-Host "    (PowerShell Edition)                            " -ForegroundColor Blue
Write-Host "                                                    " -ForegroundColor Blue
Write-Host "==================================================" -ForegroundColor Blue
Write-Host ""

# ── Claude Code CLI presence check ────────────────────────────

Confirm-ClaudeCli

# ── Installation type selection ───────────────────────────────

Write-Info "Select installation type:"
Write-Host "  1) Global settings only (~/.claude/)"
Write-Host "  2) Project settings only (current directory)"
Write-Host "  3) Both (recommended)"
Write-Host "  4) Enterprise settings only (admin required)"
Write-Host "  5) All (Enterprise + Global + Project)"
Write-Host ""

$installType = Read-Host "Selection (1-5) [default: 3]"
if ([string]::IsNullOrEmpty($installType)) { $installType = '3' }

# ── Language selection prompts ────────────────────────────────
# Single source of truth in scripts/lib/InstallPrompts.psm1 (mirrored by
# scripts/lib/install-prompts.sh for bash). The simplified UI offers
# English/Korean only; advanced policies (korean_plus_english, any) remain
# accepted by the validator but must be set via direct settings.json edit.
# Only the Global / Enterprise install paths touch settings.json; "english"
# leaves the dispatcher at its default and skips writing settings.json.
$promptsModule = Join-Path $ScriptDir 'lib' 'InstallPrompts.psm1'
Import-Module $promptsModule -Force -DisableNameChecking

$settingsPath = Join-Path $HOME '.claude/settings.json'
$seededPolicy = Seed-LanguageFromSettings -SettingsPath $settingsPath
$profileChoice = Show-LanguageProfilePrompt -AgentLanguage $seededPolicy.AgentLanguage -ContentLanguage $seededPolicy.ContentLanguage
$agentLanguage = $profileChoice.AgentLanguage
$agentDisplayLang = $profileChoice.AgentDisplay
$contentLanguage = $profileChoice.ContentLanguage

# Legacy settings.json migration warning (informational only).
$null = Show-LegacySettingsWarning -SettingsPath $settingsPath -NewSelection $contentLanguage

# ── Enterprise CLAUDE.md conflict detection (issue #411) ───────
# Enterprise policy takes the highest precedence; warn when the chosen
# language policy contradicts an existing English-only enterprise doc.
if ($contentLanguage -ne 'english') {
    $enterpriseClaude = Join-Path (Get-EnterpriseDir) 'CLAUDE.md'
    if (Test-Path -LiteralPath $enterpriseClaude) {
        $enterpriseContent = Get-Content -Raw -LiteralPath $enterpriseClaude -ErrorAction SilentlyContinue
        if ($enterpriseContent -and $enterpriseContent -imatch 'written in english') {
            Write-Host ""
            Write-Warn "Enterprise policy conflict detected"
            Write-Warn "  Path: $enterpriseClaude"
            Write-Warn "  The enterprise CLAUDE.md requires English, but you selected '$contentLanguage'."
            Write-Warn "  The enterprise path loads at the highest precedence; your choice may violate enterprise policy."
            Write-Host ""
            $override = Read-Host "Continue with '$contentLanguage' anyway? (y/n) [default: n]"
            if ([string]::IsNullOrEmpty($override)) { $override = 'n' }
            if ($override -ne 'y') {
                Write-Info "Resetting to english."
                $contentLanguage = 'english'
            }
        }
    }
}

# ── Enterprise installation ──────────────────────────────────

if ($installType -eq '4' -or $installType -eq '5') {
    Install-Enterprise
}

# ── Global settings installation ──────────────────────────────

if ($installType -eq '1' -or $installType -eq '3' -or $installType -eq '5') {
    Write-Host ""
    Write-Host "======================================================"
    Write-Info "Global settings installation..."
    Write-Host "======================================================"
    Write-Host ""

    # Create ~/.claude directory
    $claudeDir = Join-Path $HOME ".claude"
    Ensure-Directory $claudeDir

    # Load install-manifest helper (fail-fast — fallback paths assume this loaded)
    $manifestHelper = Join-Path $BackupDir 'scripts\install-manifest.ps1'
    if (-not (Test-Path -LiteralPath $manifestHelper)) {
        throw "install-manifest.ps1 helper not found at: $manifestHelper"
    }
    . $manifestHelper
    Reset-ManifestManagedKeys

    # Copy configuration files (manifest-guarded)
    $globalFiles = @('CLAUDE.md', 'commit-settings.md', 'git-identity.md', 'token-management.md')
    foreach ($gf in $globalFiles) {
        $src = Join-Path $BackupDir "global/$gf"
        # Issue #411: prefer .tmpl + substitution when present
        $srcTmpl = "$src.tmpl"
        if (Test-Path $srcTmpl) {
            # Render to a temporary file using the existing policy substitution
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "policy_$([guid]::NewGuid()).md"
            Invoke-PolicyTemplate -Source $srcTmpl -Destination $tmpFile `
                -ContentLanguage $script:contentLanguage -AgentDisplay $script:agentDisplayLang -AgentLanguage $script:agentLanguage
            if (Invoke-ManifestTrackedCopy -Src $tmpFile -Dest (Join-Path $claudeDir $gf) -Key $gf) {
                Write-Success "$gf installed (policy phrase: $(Get-PolicyPhrase -Policy $script:contentLanguage))"
            } else {
                Write-Info "$gf local changes preserved"
            }
            Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        } elseif (Test-Path $src) {
            if (Invoke-ManifestTrackedCopy -Src $src -Dest (Join-Path $claudeDir $gf) -Key $gf) {
                Write-Success "$gf installed"
            } else {
                Write-Info "$gf local changes preserved"
            }
        }
    }

    # Auto-seed git identity from `git config --global` (issue #777). Shared
    # with bootstrap.ps1 via Set-GitIdentitySeed in InstallPrompts.psm1, so a
    # fresh install produces a usable git-identity.md without manual editing.
    if (Get-Command Set-GitIdentitySeed -ErrorAction SilentlyContinue) {
        $gitIdTarget = Join-Path $claudeDir 'git-identity.md'
        if (Set-GitIdentitySeed -Path $gitIdTarget) {
            Write-Success "git-identity.md auto-filled from git config ($($script:SeededGitName) <$($script:SeededGitEmail)>)"
        }
    }

    # conversation-language.md template rendering.
    # $agentDisplayLang is populated by Show-LanguageProfilePrompt (derived
    # from $profileChoice); fall back to deriving from $agentLanguage if the
    # prompt was skipped (e.g. project-only install path).
    $tmplPath = Join-Path $BackupDir "global/conversation-language.md.tmpl"
    if (Test-Path $tmplPath) {
        if (-not $agentDisplayLang) {
            $agentDisplayLang = if ($agentLanguage -eq 'english') { 'English' } else { 'Korean' }
        }

        if (Invoke-GuardedTemplateCopy -SrcTmpl $tmplPath -Dest (Join-Path $claudeDir "conversation-language.md") -Key "conversation-language.md" -DisplayLang $agentDisplayLang) {
            Add-ManifestManagedKey -Key 'conversation-language.md'
            Write-Success "conversation-language.md installed (Language: $agentDisplayLang)"
        } else {
            Add-ManifestManagedKey -Key 'conversation-language.md'
            Write-Info "conversation-language.md local changes preserved"
        }
    }

    # settings.json + hooks directory install. The Windows settings file points
    # at runtime hooks, so publish settings only after hook deployment succeeds.
    Install-GlobalSettingsAndHooks -ClaudeDir $claudeDir

    # Install utility scripts — dual-variant, same rationale as hooks.
    $scriptsSource = Join-Path $BackupDir "global/scripts"
    if (Test-Path $scriptsSource) {
        $scriptsDir = Join-Path $claudeDir "scripts"
        Ensure-Directory $scriptsDir

        try {
            $ps1Items = Get-ChildItem -Path $scriptsSource -Filter '*.ps1' -File
            if ($ps1Items.Count -gt 0) {
                foreach ($item in $ps1Items) {
                    $null = Invoke-ManifestTrackedCopy -Src $item.FullName -Dest (Join-Path $scriptsDir $item.Name) -Key "scripts/$($item.Name)"
                }
            }
        } catch {
            Write-Err "Failed to copy utility scripts: $_"
        }
        Get-ChildItem -Path $scriptsSource -Filter '*.sh' -File -ErrorAction SilentlyContinue | ForEach-Object {
            $tmpScript = Join-Path ([System.IO.Path]::GetTempPath()) "claude-script-$([guid]::NewGuid()).sh"
            Install-BashScript -SourcePath $_.FullName -DestinationPath $tmpScript
            $null = Invoke-ManifestTrackedCopy -Src $tmpScript -Dest (Join-Path $scriptsDir $_.Name) -Key "scripts/$($_.Name)"
            Remove-Item -LiteralPath $tmpScript -Force -ErrorAction SilentlyContinue
        }

        Write-Success "Utility scripts installed (scripts/*.ps1 + *.sh)!"
    }

    # Install policy files (if present).
    $policiesSource = Join-Path $BackupDir "global/policies"
    if (Test-Path $policiesSource) {
        $policiesDir = Join-Path $claudeDir "policies"
        Ensure-Directory $policiesDir
        try {
            $jsonItems = Get-ChildItem -Path $policiesSource -Filter '*.json' -File
            if ($jsonItems.Count -gt 0) {
                foreach ($item in $jsonItems) {
                    $null = Invoke-ManifestTrackedCopy -Src $item.FullName -Dest (Join-Path $policiesDir $item.Name) -Key "policies/$($item.Name)"
                }
            }
            Write-Success "Policy files (policies/*.json) installed!"
        } catch {
            Write-Err "Failed to copy policy files: $_"
        }
    }

    # Hook pairing audit: warn on orphans so Docker-side rewrites don't silently
    # resolve to missing files.
    $hooksDirForAudit = Join-Path $claudeDir "hooks"
    if (Test-Path $hooksDirForAudit) {
        $ps1Stems = @(Get-ChildItem -Path $hooksDirForAudit -Filter '*.ps1' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
        $shStems  = @(Get-ChildItem -Path $hooksDirForAudit -Filter '*.sh'  -File -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
        $missingSh  = @($ps1Stems | Where-Object { $_ -notin $shStems })
        $missingPs1 = @($shStems  | Where-Object { $_ -notin $ps1Stems })
        if ($missingSh.Count -gt 0 -or $missingPs1.Count -gt 0) {
            Write-Warn "Hook pairing audit found orphans:"
            foreach ($stem in $missingSh)  { Write-Host "    - $stem.ps1 has no matching $stem.sh (Linux container hook will 'not found')" }
            foreach ($stem in $missingPs1) { Write-Host "    - $stem.sh has no matching $stem.ps1 (Windows host hook will 'not found')" }
            Write-Host "  Add the missing variant to global/hooks/ and re-run install.ps1 to fix."
        } else {
            Write-Success "Hook pairing audit passed (all .ps1/.sh stems matched)."
        }
    }

    # Install global skills (mirrors install.sh:473-484).
    # `_internal/` 하위 격리 + `disable-model-invocation: true`가 적용된 스킬군은
    # Claude Code 슬래시 카탈로그에 노출되지 않으며, 글로벌 CLAUDE.md의
    # "Skill Aliases" 표에 따라 leading keyword 호출로만 실행된다.
    # `Copy-Item -Path "$src\*"` 패턴으로 _policy.md 같은 루트 레벨 파일까지 복사한다.
    $skillsSource = Join-Path $BackupDir "global/skills"
    if (Test-Path $skillsSource) {
        $skillsDir = Join-Path $claudeDir "skills"
        Ensure-Directory $skillsDir
        try {
            Copy-ManifestTree -SourceDir $skillsSource -DestinationDir $skillsDir -KeyPrefix 'skills'
            $skillCount = (Get-ChildItem -Path $skillsDir -Filter SKILL.md -Recurse -ErrorAction SilentlyContinue).Count
            Write-Success "Global Skills ($skillCount) installed!"
        } catch {
            Write-Err "Failed to copy global skills: $_"
        }
    }

    # Install global commands (mirrors install.sh:485-489).
    $commandsSource = Join-Path $BackupDir "global/commands"
    if (Test-Path $commandsSource) {
        $commandsDir = Join-Path $claudeDir "commands"
        Ensure-Directory $commandsDir
        try {
            Copy-ManifestTree -SourceDir $commandsSource -DestinationDir $commandsDir -KeyPrefix 'commands'
            Write-Success "Global Commands installed!"
        } catch {
            Write-Err "Failed to copy global commands: $_"
        }
    }

    Add-RetiredManagedManifestEntries -Root $claudeDir -Entries @{
        'commands/branch-cleanup.md' = '3e7fc38c324cfc9cea639e95394d7819e7768364d12023ec0b36b91f9230b09d'
        'commands/doc-review.md' = 'be659114c43ef29423c74d7b33e0f594b80c134b38fb7c5b61e6935cae88c26f'
        'commands/implement-all-levels.md' = 'b675f8e689e8aca71eb67e8666acc98018ad70b746d16655476b5939380737be'
        'commands/issue-create.md' = 'c654ab412f320b9d97553f92a510cf5de13a5d0a7ed5e14212ca62534887ae71'
        'commands/issue-work.md' = '048a26140b03862c5b10630853115ee656056f45cedfd0a0b6ec814bf7225684'
        'commands/pr-work.md' = '2ecf1a78271c553e2310b57b2a1deb026a07ae01b84c1f856638293ab41f1199'
        'commands/release.md' = '93fd6d2f7800deada2868b97b65ef486f42482b5e2f1224c35f732ebfeb1c013'
    }
    $null = Invoke-ManifestPruneTracked -Root $claudeDir

    # Install ccstatusline settings (~/.config/ccstatusline/ — ccstatusline default settings path)
    $ccstatuslineSource = Join-Path $BackupDir "global/ccstatusline"
    if (Test-Path $ccstatuslineSource) {
        $ccstatuslineDir = Join-Path $HOME ".config/ccstatusline"
        Ensure-Directory $ccstatuslineDir
        Copy-Item -Path "$ccstatuslineSource\settings.json" -Destination $ccstatuslineDir -Force
        Write-Success "ccstatusline settings (~/.config/ccstatusline/settings.json) installed!"
    }

    # npm package installation (statusline dependencies)
    Write-Host ""
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $installNpm = Read-Host "Install statusline npm packages? (ccstatusline, claude-limitline) (y/n) [default: y]"
        if ([string]::IsNullOrEmpty($installNpm)) { $installNpm = 'y' }
        if ($installNpm -eq 'y') {
            Write-Info "Installing npm packages..."
            try {
                $npmOutput = npm install -g ccstatusline claude-limitline 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "npm packages installed! (ccstatusline, claude-limitline)"
                } else {
                    Write-Warn "npm package installation failed. Install manually:"
                    Write-Host "    npm install -g ccstatusline claude-limitline"
                }
            } catch {
                Write-Warn "npm package installation failed. Install manually:"
                Write-Host "    npm install -g ccstatusline claude-limitline"
            }
        } else {
            Write-Info "npm package installation skipped"
            Write-Host "  Manual install: npm install -g ccstatusline claude-limitline"
        }
    } else {
        Write-Warn "npm is not installed."
        Write-Host "  After installing Node.js/npm, run:"
        Write-Host "    npm install -g ccstatusline claude-limitline"
    }

    Write-Success "Global settings installation complete!"

    # Git identity personalization notice
    Write-Host ""
    $gitIdentityPath = Join-Path $claudeDir 'git-identity.md'
    $needsGitIdentityEdit = $false
    if (Test-Path $gitIdentityPath) {
        $needsGitIdentityEdit = [bool](Select-String -Path $gitIdentityPath -Pattern 'YOUR NAME|YOUR EMAIL' -Quiet)
    }
    if ($needsGitIdentityEdit) {
        Write-Warn "git-identity.md still contains default placeholders. Edit it with your personal info."
        Write-Host "  Edit: notepad `$HOME\.claude\git-identity.md"
    }
    else {
        Write-Info "git-identity.md is ready. Review or edit it only if needed."
        Write-Host "  Check: Get-Content `$HOME\.claude\git-identity.md | Select-String '^(name|email):'"
    }
}

# ── Project settings installation ─────────────────────────────

if ($installType -eq '2' -or $installType -eq '3' -or $installType -eq '5') {
    Write-Host ""
    Write-Host "======================================================"
    Write-Info "Project settings installation..."
    Write-Host "======================================================"
    Write-Host ""

    # Project directory
    $defaultProjectDir = (Get-Location).Path
    $projectDir = Read-Host "Project directory path [default: $defaultProjectDir]"
    if ([string]::IsNullOrEmpty($projectDir)) { $projectDir = $defaultProjectDir }

    if (-not (Test-Path $projectDir)) {
        Write-Err "Directory does not exist: $projectDir"
        exit 1
    }

    Write-Info "Install path: $projectDir"

    # .claude directory
    $projectClaudeDir = Join-Path $projectDir ".claude"
    Ensure-Directory $projectClaudeDir
    if (-not (Get-Command Invoke-ManifestTrackedCopy -ErrorAction SilentlyContinue)) {
        $manifestHelper = Join-Path $BackupDir 'scripts\install-manifest.ps1'
        if (-not (Test-Path -LiteralPath $manifestHelper)) {
            throw "install-manifest.ps1 helper not found at: $manifestHelper"
        }
        . $manifestHelper
    }
    $previousManifestPath = $env:MANIFEST_PATH
    $env:MANIFEST_PATH = Join-Path $projectClaudeDir ".install-manifest.json"
    Reset-ManifestManagedKeys

    # Copy files
    $null = Invoke-ManifestTrackedCopy -Src (Join-Path $BackupDir "project/CLAUDE.md") -Dest (Join-Path $projectDir "CLAUDE.md") -Key "CLAUDE.md"

    # settings.json
    $projectSettings = Join-Path $BackupDir "project/.claude/settings.json"
    if (Test-Path $projectSettings) {
        $null = Invoke-ManifestTrackedCopy -Src $projectSettings -Dest (Join-Path $projectClaudeDir "settings.json") -Key ".claude/settings.json"
        Write-Success "Project hook settings (.claude/settings.json) installed!"
    }

    # rules directory
    $sourceRules = Join-Path $BackupDir "project/.claude/rules"
    if (Test-Path $sourceRules) {
        $rulesTmp = Join-Path ([System.IO.Path]::GetTempPath()) "claude-rules-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $rulesTmp -Force | Out-Null
        Copy-Item -Path (Join-Path $sourceRules '*') -Destination $rulesTmp -Recurse -Force
        # Issue #411: render any .md.tmpl found under rules/ with the chosen policy phrase.
        Invoke-PolicyTemplatesInDir -Path $rulesTmp `
            -ContentLanguage $script:contentLanguage -AgentDisplay $script:agentDisplayLang -AgentLanguage $script:agentLanguage
        Copy-ManifestTree -SourceDir $rulesTmp -DestinationDir (Join-Path $projectClaudeDir 'rules') -KeyPrefix '.claude/rules'
        Remove-Item -LiteralPath $rulesTmp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Rules directory installed! (policy phrase: $(Get-PolicyPhrase -Policy $script:contentLanguage))"
    }

    # reference directory (on-demand docs relocated out of rules/ -- issue #714)
    $sourceReference = Join-Path $BackupDir "project/.claude/reference"
    if (Test-Path $sourceReference) {
        Copy-ManifestTree -SourceDir $sourceReference -DestinationDir (Join-Path $projectClaudeDir 'reference') -KeyPrefix '.claude/reference'
        Write-Success "Reference directory installed!"
    }

    # Skills directory
    $sourceSkills = Join-Path $BackupDir "project/.claude/skills"
    if (Test-Path $sourceSkills) {
        Copy-ManifestTree -SourceDir $sourceSkills -DestinationDir (Join-Path $projectClaudeDir 'skills') -KeyPrefix '.claude/skills'
        Write-Success "Skills directory installed!"
    }

    # commands directory
    $sourceCommands = Join-Path $BackupDir "project/.claude/commands"
    if (Test-Path $sourceCommands) {
        Copy-ManifestTree -SourceDir $sourceCommands -DestinationDir (Join-Path $projectClaudeDir 'commands') -KeyPrefix '.claude/commands'
        Write-Success "Commands directory installed!"
    }

    # agents directory
    $sourceAgents = Join-Path $BackupDir "project/.claude/agents"
    if (Test-Path $sourceAgents) {
        Copy-ManifestTree -SourceDir $sourceAgents -DestinationDir (Join-Path $projectClaudeDir 'agents') -KeyPrefix '.claude/agents'
        Write-Success "Agents directory installed!"
    }

    # .claudeignore (token optimization)
    $claudeIgnore = Join-Path $BackupDir "project/.claudeignore"
    if (Test-Path $claudeIgnore) {
        $null = Invoke-ManifestTrackedCopy -Src $claudeIgnore -Dest (Join-Path $projectDir ".claudeignore") -Key ".claudeignore"
        Write-Success ".claudeignore installed!"
    }

    Add-RetiredManagedManifestEntries -Root $projectDir -Entries @{
        '.claude/commands/_policy.md' = '7144bf54352362eb3d523d05a1712732aec8e82fc95ea9db0cbc79269e2bf9b1'
        '.claude/commands/code-quality.md' = '8c1e6ca0470582936fb96491d4aff7e23706da45b96ba38c51d43ba255f8f544'
        '.claude/commands/git-status.md' = '4602f6ea8ffb18b05d5698c85d060b3d6f01913a4258e778bd6b898611ca9d33'
        '.claude/commands/pr-review.md' = '3dbd7d788b1e19b1d04654e03eaf8531c933e6b7462120ffdc03d5d7f9658711'
    }
    $null = Invoke-ManifestPruneTracked -Root $projectDir
    $env:MANIFEST_PATH = $previousManifestPath

    # CLAUDE.local.md creation
    Write-Host ""
    $createLocal = Read-Host "Create personal CLAUDE.local.md? (y/n) [default: y]"
    if ([string]::IsNullOrEmpty($createLocal)) { $createLocal = 'y' }
    if ($createLocal -eq 'y') {
        New-LocalClaude $projectDir
    }

    Write-Success "Project settings installation complete!"

    # Project customization notice
    Write-Host ""
    Write-Info "Customize settings for your project:"
    Write-Host "  - CLAUDE.md: Modify project overview"
    Write-Host "  - .claude/rules/: Adjust coding standards"
    Write-Host "  - CLAUDE.local.md: Personal settings (not committed)"
}

# ── Installation summary ──────────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-Success "Installation complete!"
Write-Host "======================================================"
Write-Host ""

Write-Info "Installed files:"
if ($installType -eq '4' -or $installType -eq '5') {
    $ed = Get-EnterpriseDir
    Write-Host "  Enterprise settings:"
    Write-Host "    - $ed\CLAUDE.md"
    Write-Host "    - $ed\rules\"
}

if ($installType -eq '1' -or $installType -eq '3' -or $installType -eq '5') {
    Write-Host "  Global settings:"
    Write-Host "    - ~/.claude/CLAUDE.md"
    Write-Host "    - ~/.claude/commit-settings.md"
    $optionalGlobal = @('conversation-language.md', 'git-identity.md', 'token-management.md')
    foreach ($og in $optionalGlobal) {
        if (Test-Path (Join-Path $HOME ".claude/$og")) {
            Write-Host "    - ~/.claude/$og"
        }
    }
    Write-Host "    - ~/.claude/settings.json (Hook settings - Windows)"
    Write-Host "    - ~/.claude/hooks/ (PowerShell + bash hook scripts, lib/, data)"
    Write-Host "    - ~/.claude/scripts/ (PowerShell + bash utility scripts)"
    if (Test-Path (Join-Path $HOME ".claude/skills")) {
        Write-Host "    - ~/.claude/skills/ (Global skills — keyword-invoked via CLAUDE.md alias table)"
    }
    if (Test-Path (Join-Path $HOME ".claude/commands")) {
        Write-Host "    - ~/.claude/commands/ (Global commands)"
    }
    Write-Host "    - ~/.config/ccstatusline/ (ccstatusline settings)"
}

if ($installType -eq '2' -or $installType -eq '3' -or $installType -eq '5') {
    Write-Host "  Project settings:"
    Write-Host "    - $projectDir\CLAUDE.md"
    Write-Host "    - $projectDir\.claude\rules\ (Guidelines)"
    Write-Host "    - $projectDir\.claude\reference\ (On-demand reference docs)"
    Write-Host "    - $projectDir\.claude\settings.json (Hook settings)"
    $sourceSkills = Join-Path $BackupDir "project/.claude/skills"
    if (Test-Path $sourceSkills) {
        Write-Host "    - $projectDir\.claude\skills\ (Skills)"
    }
    $sourceCommands = Join-Path $BackupDir "project/.claude/commands"
    if (Test-Path $sourceCommands) {
        Write-Host "    - $projectDir\.claude\commands\ (Commands)"
    }
    $sourceAgents = Join-Path $BackupDir "project/.claude/agents"
    if (Test-Path $sourceAgents) {
        Write-Host "    - $projectDir\.claude\agents\ (Agents)"
    }
}

Write-Host ""
Write-Host "======================================================"
Write-Info "Next steps"
Write-Host "======================================================"
Write-Host ""
Write-Host "1. Verify Git identity:"
Write-Host "     Get-Content `$HOME\.claude\git-identity.md | Select-String '^(name|email):'"
Write-Host "     # Edit with notepad `$HOME\.claude\git-identity.md if placeholders remain"
Write-Host ""
Write-Host "2. Set PowerShell execution policy (if needed):"
Write-Host "     Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
Write-Host ""
Write-Host "3. Restart Claude Code:"
Write-Host "     Open a new terminal or restart current session"
Write-Host ""
Write-Host "4. Statusline npm packages (if not installed):"
Write-Host "     npm install -g ccstatusline claude-limitline"
Write-Host ""
Write-Host "5. Verify settings:"
Write-Host "     Get-Content `$HOME\.claude\CLAUDE.md"
Write-Host ""

Write-Success "Installation complete!"
