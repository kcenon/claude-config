# Claude Configuration Project Initializer
# ==========================================
# Deploy project-level Claude Code configuration template to a target directory.

param(
    [Parameter(Position=0)]
    [string]$Target,

    [ValidateSet("minimal", "standard", "full")]
    [string]$Profile = "standard",

    [switch]$Force,
    [switch]$DryRun,
    [switch]$InstallHooks,
    [switch]$NoHooks,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$ProjectTemplate = Join-Path $RepoDir "project"
$HooksDir = Join-Path $RepoDir "hooks"

function Show-Usage {
    @"
Usage: init-project.ps1 <target-directory> [-Profile <level>] [-Force] [-DryRun]

Deploy Claude Code project configuration to a target directory.

Parameters:
  -Profile <level>    Configuration profile (default: standard)
                        minimal  - CLAUDE.md + core rules + .claudeignore
                        standard - minimal + coding + workflow rules
                        full     - standard + api + operations + agents + skills
  -Force              Overwrite existing files
  -DryRun             Show what would be copied without copying
  -InstallHooks       Install git hooks without prompting
  -NoHooks            Skip git hooks installation

Examples:
  .\scripts\init-project.ps1 C:\Projects\my-app
  .\scripts\init-project.ps1 C:\Projects\my-app -Profile full
  .\scripts\init-project.ps1 C:\Projects\my-app -Profile minimal -Force
"@
}

if ($Help) { Show-Usage; return }

if (-not $Target) {
    Write-Host "ERROR: Target directory is required." -ForegroundColor Red
    Show-Usage
    return
}

$Target = (Resolve-Path $Target -ErrorAction SilentlyContinue).Path
if (-not $Target -or -not (Test-Path $Target -PathType Container)) {
    Write-Host "ERROR: Target directory does not exist: $Target" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "  Claude Code Project Initializer" -ForegroundColor Blue
Write-Host "  Target:  $Target" -ForegroundColor Blue
Write-Host "  Profile: $Profile" -ForegroundColor Blue
Write-Host ""

$Script:Copied = 0
$Script:Skipped = 0

function Copy-Item-Safe {
    param([string]$Src, [string]$Dst)

    $rel = $Src.Replace($ProjectTemplate, "").TrimStart("\", "/")

    if (-not (Test-Path $Src)) { return }

    if ((Test-Path $Dst) -and -not $Force) {
        if ($DryRun) { Write-Host "  SKIP  $rel (exists)" -ForegroundColor Yellow }
        $Script:Skipped++
        return
    }

    if ($DryRun) {
        Write-Host "  COPY  $rel" -ForegroundColor Green
        $Script:Copied++
        return
    }

    $dstDir = Split-Path -Parent $Dst
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }

    if (Test-Path $Src -PathType Container) {
        Copy-Item -Path $Src -Destination $Dst -Recurse -Force
    } else {
        Copy-Item -Path $Src -Destination $Dst -Force
    }
    $Script:Copied++
}

function Copy-Minimal {
    Copy-Item-Safe "$ProjectTemplate\CLAUDE.md" "$Target\CLAUDE.md"
    Copy-Item-Safe "$ProjectTemplate\.claudeignore" "$Target\.claudeignore"
    Copy-Item-Safe "$ProjectTemplate\.claude\rules\core" "$Target\.claude\rules\core"
    Copy-Item-Safe "$ProjectTemplate\.claude\rules\security.md" "$Target\.claude\rules\security.md"
    Copy-Item-Safe "$ProjectTemplate\.claude\settings.json" "$Target\.claude\settings.json"
}

function Copy-Standard {
    Copy-Minimal
    Copy-Item-Safe "$ProjectTemplate\.claude\rules\coding" "$Target\.claude\rules\coding"
    Copy-Item-Safe "$ProjectTemplate\.claude\rules\workflow" "$Target\.claude\rules\workflow"
    Copy-Item-Safe "$ProjectTemplate\.claude\rules\project-management" "$Target\.claude\rules\project-management"
    Copy-Item-Safe "$ProjectTemplate\.claude\rules\tools" "$Target\.claude\rules\tools"
    Copy-Item-Safe "$ProjectTemplate\.claude\commands" "$Target\.claude\commands"
}

function Copy-Full {
    Copy-Standard
    Copy-Item-Safe "$ProjectTemplate\.claude\rules\api" "$Target\.claude\rules\api"
    Copy-Item-Safe "$ProjectTemplate\.claude\rules\operations" "$Target\.claude\rules\operations"
    Copy-Item-Safe "$ProjectTemplate\.claude\agents" "$Target\.claude\agents"
    Copy-Item-Safe "$ProjectTemplate\.claude\skills" "$Target\.claude\skills"
    Copy-Item-Safe "$ProjectTemplate\.mcp.json.example" "$Target\.mcp.json.example"
    Copy-Item-Safe "$ProjectTemplate\.lsp.json.example" "$Target\.lsp.json.example"
    Copy-Item-Safe "$ProjectTemplate\CLAUDE.local.md.template" "$Target\CLAUDE.local.md.template"
    Copy-Item-Safe "$ProjectTemplate\.claude\settings.local.json.template" "$Target\.claude\settings.local.json.template"
}

switch ($Profile) {
    "minimal"  { Copy-Minimal }
    "standard" { Copy-Standard }
    "full"     { Copy-Full }
}

Write-Host ""
if ($DryRun) {
    Write-Host "  Dry run: $($Script:Copied) would be copied, $($Script:Skipped) would be skipped." -ForegroundColor Blue
    return
}

Write-Host "  $($Script:Copied) items copied, $($Script:Skipped) skipped." -ForegroundColor Green

# Git hooks
$isGitRepo = $false
try {
    Push-Location $Target
    $null = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) { $isGitRepo = $true }
    Pop-Location
} catch { Pop-Location }

if ($isGitRepo -and -not $NoHooks) {
    $installHooksScript = Join-Path $HooksDir "install-hooks.ps1"
    if ($InstallHooks -or (-not $NoHooks)) {
        if (-not $InstallHooks) {
            $answer = Read-Host "Install git hooks (commit-msg, pre-commit) to $Target? [Y/n]"
            if ($answer -match '^[Nn]') { $InstallHooks = $false } else { $InstallHooks = $true }
        }
        if ($InstallHooks -and (Test-Path $installHooksScript)) {
            Write-Host "  Installing git hooks..." -ForegroundColor Blue
            & $installHooksScript $Target
            Write-Host "  Git hooks installed." -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "  Project initialized: $Target" -ForegroundColor Green
Write-Host "  Profile: $Profile | Items: $($Script:Copied) copied, $($Script:Skipped) skipped" -ForegroundColor Blue
