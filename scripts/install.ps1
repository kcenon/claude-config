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

function New-Backup {
    param([string]$Target)
    if (Test-Path $Target) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupName = "${Target}.backup_${timestamp}"
        Copy-Item -Path $Target -Destination $backupName -Recurse -Force
        Write-Info "Existing file backed up: $backupName"
    }
}

function Ensure-Directory {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        Write-Success "Directory created: $Dir"
    }
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
        Copy-Item -Path "$sourceRules\*" -Destination $rulesDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "rules directory installed"
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

    # Check for existing files
    $backupExisting = 'y'
    $existingMd = Join-Path $claudeDir "CLAUDE.md"
    if (Test-Path $existingMd) {
        Write-Warn "Existing CLAUDE.md found."
        $backupExisting = Read-Host "Backup and overwrite? (y/n) [default: y]"
        if ([string]::IsNullOrEmpty($backupExisting)) { $backupExisting = 'y' }
    }

    if ($backupExisting -eq 'y') {
        # Backup existing files
        New-Backup (Join-Path $claudeDir "CLAUDE.md")
        New-Backup (Join-Path $claudeDir "conversation-language.md")
        New-Backup (Join-Path $claudeDir "git-identity.md")
        New-Backup (Join-Path $claudeDir "token-management.md")

        # Copy configuration files
        Copy-Item -Path (Join-Path $BackupDir "global/CLAUDE.md") -Destination $claudeDir -Force
        Copy-Item -Path (Join-Path $BackupDir "global/conversation-language.md") -Destination $claudeDir -Force
        Copy-Item -Path (Join-Path $BackupDir "global/git-identity.md") -Destination $claudeDir -Force
        Copy-Item -Path (Join-Path $BackupDir "global/token-management.md") -Destination $claudeDir -Force

        # Install settings.windows.json as settings.json
        $settingsSource = Join-Path $BackupDir "global/settings.windows.json"
        if (Test-Path $settingsSource) {
            New-Backup (Join-Path $claudeDir "settings.json")
            Copy-Item -Path $settingsSource -Destination (Join-Path $claudeDir "settings.json") -Force
            Write-Success "Hook settings (settings.json) installed! [Windows version]"
        }

        # Install PowerShell hook scripts
        $hooksSource = Join-Path $BackupDir "global/hooks"
        if (Test-Path $hooksSource) {
            $hooksDir = Join-Path $claudeDir "hooks"
            Ensure-Directory $hooksDir
            Copy-Item -Path "$hooksSource\*.ps1" -Destination $hooksDir -Force -ErrorAction SilentlyContinue
            Write-Success "PowerShell hook scripts (hooks/*.ps1) installed!"
        }

        Write-Success "Global settings installation complete!"

        # Git identity personalization notice
        Write-Host ""
        Write-Warn "Important: Modify git-identity.md with your personal info!"
        Write-Host "  Edit: notepad `$HOME\.claude\git-identity.md"
    } else {
        Write-Info "Global settings installation skipped"
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

    # Backup existing files
    $existingProjectMd = Join-Path $projectDir "CLAUDE.md"
    if (Test-Path $existingProjectMd) {
        New-Backup $existingProjectMd
    }
    $existingRules = Join-Path $projectDir ".claude/rules"
    if (Test-Path $existingRules) {
        New-Backup $existingRules
    }

    # Copy files
    Copy-Item -Path (Join-Path $BackupDir "project/CLAUDE.md") -Destination $projectDir -Force

    # .claude directory
    $projectClaudeDir = Join-Path $projectDir ".claude"
    Ensure-Directory $projectClaudeDir

    # settings.json
    $projectSettings = Join-Path $BackupDir "project/.claude/settings.json"
    if (Test-Path $projectSettings) {
        New-Backup (Join-Path $projectClaudeDir "settings.json")
        Copy-Item -Path $projectSettings -Destination $projectClaudeDir -Force
        Write-Success "Project hook settings (.claude/settings.json) installed!"
    }

    # rules directory
    $sourceRules = Join-Path $BackupDir "project/.claude/rules"
    if (Test-Path $sourceRules) {
        Copy-Item -Path $sourceRules -Destination $projectClaudeDir -Recurse -Force
        Write-Success "Rules directory installed!"
    }

    # Skills directory
    $sourceSkills = Join-Path $BackupDir "project/.claude/skills"
    if (Test-Path $sourceSkills) {
        $existingSkills = Join-Path $projectClaudeDir "skills"
        if (Test-Path $existingSkills) { New-Backup $existingSkills }
        Copy-Item -Path $sourceSkills -Destination $projectClaudeDir -Recurse -Force
        Write-Success "Skills directory installed!"
    }

    # commands directory
    $sourceCommands = Join-Path $BackupDir "project/.claude/commands"
    if (Test-Path $sourceCommands) {
        $existingCommands = Join-Path $projectClaudeDir "commands"
        if (Test-Path $existingCommands) { New-Backup $existingCommands }
        Copy-Item -Path $sourceCommands -Destination $projectClaudeDir -Recurse -Force
        Write-Success "Commands directory installed!"
    }

    # agents directory
    $sourceAgents = Join-Path $BackupDir "project/.claude/agents"
    if (Test-Path $sourceAgents) {
        $existingAgents = Join-Path $projectClaudeDir "agents"
        if (Test-Path $existingAgents) { New-Backup $existingAgents }
        Copy-Item -Path $sourceAgents -Destination $projectClaudeDir -Recurse -Force
        Write-Success "Agents directory installed!"
    }

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
    Write-Host "    - ~/.claude/conversation-language.md"
    Write-Host "    - ~/.claude/git-identity.md"
    Write-Host "    - ~/.claude/token-management.md"
    Write-Host "    - ~/.claude/settings.json (Hook settings - Windows)"
    Write-Host "    - ~/.claude/hooks/ (PowerShell hook scripts)"
}

if ($installType -eq '2' -or $installType -eq '3' -or $installType -eq '5') {
    Write-Host "  Project settings:"
    Write-Host "    - $projectDir\CLAUDE.md"
    Write-Host "    - $projectDir\.claude\rules\ (Guidelines)"
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
Write-Host "1. Personalize Git identity (Required!):"
Write-Host "     notepad `$HOME\.claude\git-identity.md"
Write-Host ""
Write-Host "2. Set PowerShell execution policy (if needed):"
Write-Host "     Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
Write-Host ""
Write-Host "3. Restart Claude Code:"
Write-Host "     Open a new terminal or restart current session"
Write-Host ""
Write-Host "4. Verify settings:"
Write-Host "     Get-Content `$HOME\.claude\CLAUDE.md"
Write-Host ""

Write-Success "Installation complete!"
