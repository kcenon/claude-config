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

function Get-PolicyPhrase {
    # Issue #411: map CLAUDE_CONTENT_LANGUAGE value to a short phrase.
    # Reads the script-scope $contentLanguage set after the install-type prompt.
    switch ($script:contentLanguage) {
        'english'             { return 'English' }
        'korean_plus_english' { return 'English or Korean' }
        'exclusive_bilingual' { return 'English or Korean (document-exclusive)' }
        'any'                 { return 'any language' }
        default               { return 'English' }
    }
}

function Invoke-PolicyTemplate {
    # Renders a .md.tmpl file by replacing {{CONTENT_LANGUAGE_POLICY}}
    # with the resolved phrase and writes the result to $Destination as UTF-8.
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    $phrase = Get-PolicyPhrase
    
    # Note: Agent language substitution is handled by Invoke-GuardedTemplateCopy.

    $content = [System.IO.File]::ReadAllText($Source)
    $rendered = $content -replace '\{\{CONTENT_LANGUAGE_POLICY\}\}', $phrase
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Destination, $rendered, $utf8NoBom)
}

function Invoke-PolicyTemplatesInDir {
    # Walks a directory, renders every *.md.tmpl to its *.md sibling,
    # then deletes the .tmpl source. Used after bulk copy of rules/.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-ChildItem -Path $Path -Filter '*.md.tmpl' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = $_.FullName.Substring(0, $_.FullName.Length - '.tmpl'.Length)
        Invoke-PolicyTemplate -Source $_.FullName -Destination $dest
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
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

# ── Content language policy (CLAUDE_CONTENT_LANGUAGE) ─────────
# Default "english" preserves current behavior byte-for-byte. The
# dispatcher falls back to english when the env var is unset, so we skip
# writing settings.json at all for option 1.
Write-Host ""
Write-Info "Select content-language policy (commit / PR / issue validation scope):"
Write-Host "  1) English (Default, identical to current behavior)"
Write-Host "  2) Korean + English (Allows Hangul, inline mixing permitted)"
Write-Host "  3) Exclusive bilingual (English or Korean per document, no inline mixing)"
Write-Host "  4) Any (No language validation — AI attribution block maintained)"
Write-Host ""

$langType = Read-Host "Selection (1-4) [default: 1]"
if ([string]::IsNullOrEmpty($langType)) { $langType = '1' }
switch ($langType) {
    '1'     { $contentLanguage = 'english' }
    '2'     { $contentLanguage = 'korean_plus_english' }
    '3'     { $contentLanguage = 'exclusive_bilingual' }
    '4'     { $contentLanguage = 'any' }
    default {
        Write-Warn "Unknown selection: $langType. Using english."
        $contentLanguage = 'english'
    }
}

# ── Agent Conversation Language ──────────────────────────────────
Write-Host ""
Write-Info "Select Agent Conversation Language:"
Write-Host "  1) English"
Write-Host "  2) Korean"
Write-Host ""

$agentLangType = Read-Host "Selection (1-2) [default: 2]"
if ([string]::IsNullOrEmpty($agentLangType)) { $agentLangType = '2' }
switch ($agentLangType) {
    '1'     { $agentLanguage = 'english' }
    '2'     { $agentLanguage = 'korean' }
    default {
        Write-Warn "Unknown selection: $agentLangType. Using korean."
        $agentLanguage = 'korean'
    }
}

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

    # Copy configuration files (manifest-guarded)
    $globalFiles = @('CLAUDE.md', 'commit-settings.md', 'git-identity.md', 'token-management.md')
    foreach ($gf in $globalFiles) {
        $src = Join-Path $BackupDir "global/$gf"
        # Issue #411: prefer .tmpl + substitution when present
        $srcTmpl = "$src.tmpl"
        if (Test-Path $srcTmpl) {
            # Render to a temporary file using the existing policy substitution
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "policy_$([guid]::NewGuid()).md"
            Invoke-PolicyTemplate -Source $srcTmpl -Destination $tmpFile
            if (Invoke-GuardedCopy -Src $tmpFile -Dest (Join-Path $claudeDir $gf) -Key $gf) {
                Write-Success "$gf installed (policy phrase: $(Get-PolicyPhrase))"
            } else {
                Write-Info "$gf local changes preserved"
            }
            Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        } elseif (Test-Path $src) {
            if (Invoke-GuardedCopy -Src $src -Dest (Join-Path $claudeDir $gf) -Key $gf) {
                Write-Success "$gf installed"
            } else {
                Write-Info "$gf local changes preserved"
            }
        }
    }

    # conversation-language.md template rendering
    $tmplPath = Join-Path $BackupDir "global/conversation-language.md.tmpl"
    if (Test-Path $tmplPath) {
        if ($agentLanguage -eq 'english') {
            $displayLang = "English"
        } else {
            $displayLang = "Korean"
        }
        
        if (Invoke-GuardedTemplateCopy -SrcTmpl $tmplPath -Dest (Join-Path $claudeDir "conversation-language.md") -Key "conversation-language.md" -DisplayLang $displayLang) {
            Write-Success "conversation-language.md installed (Language: $displayLang)"
        } else {
            Write-Info "conversation-language.md local changes preserved"
        }
    }

    # Install settings.windows.json as settings.json
    # Intentionally bypasses Invoke-GuardedCopy: policy attributes (.language,
    # .env.CLAUDE_CONTENT_LANGUAGE) must be enforced on every install.
    # Update-ClaudeSettingsJson (below) injects them and is responsible
    # for idempotent reset when the policy returns to default ("english").
    $settingsSource = Join-Path $BackupDir "global/settings.windows.json"
    if (Test-Path $settingsSource) {
        $destSettings = Join-Path $claudeDir "settings.json"
        Copy-Item -Path $settingsSource -Destination $destSettings -Force
        Write-Success "Hook settings (settings.json) installed! [Windows version]"

        # Write CLAUDE_CONTENT_LANGUAGE under env, and update agent language
        if (Update-ClaudeSettingsJson -SettingsPath $destSettings -AgentLang $agentLanguage -ContentLang $contentLanguage) {
            Write-Success "settings.json updated with language=$agentLanguage and CLAUDE_CONTENT_LANGUAGE=$contentLanguage"
        } else {
            Write-Warn "Failed to automatically update settings.json"
            Write-Host "  Please update ~/.claude/settings.json manually with language settings."
        }
    }

    # Install hook scripts — dual-variant deployment.
    #
    # Why both .ps1 and .sh (Issue #407): When the Windows host's ~/.claude is
    # bind-mounted into a Linux Claude Code container (claude-docker), the
    # container entrypoint rewrites every `pwsh ... -File foo.ps1` command to
    # `foo.sh`. The rewrite only works when the matching .sh file is present.
    # Shipping .ps1 alone leaves every hook reporting "not found" inside the
    # container even though the host works correctly.
    $hooksSource = Join-Path $BackupDir "global/hooks"
    if (Test-Path $hooksSource) {
        $hooksDir = Join-Path $claudeDir "hooks"
        Ensure-Directory $hooksDir

        try {
            $ps1Items = Get-ChildItem -Path $hooksSource -Filter '*.ps1' -File
            if ($ps1Items.Count -gt 0) {
                Copy-Item -Path "$hooksSource\*.ps1" -Destination $hooksDir -Force -ErrorAction Stop
            }
        } catch {
            Write-Err "Failed to copy hook scripts: $_"
        }
        Get-ChildItem -Path $hooksSource -Filter '*.sh' -File -ErrorAction SilentlyContinue | ForEach-Object {
            Install-BashScript -SourcePath $_.FullName -DestinationPath (Join-Path $hooksDir $_.Name)
        }

        $hooksLibSource = Join-Path $hooksSource 'lib'
        if (Test-Path $hooksLibSource) {
            $hooksLibDir = Join-Path $hooksDir 'lib'
            Ensure-Directory $hooksLibDir
            try {
                $ps1Items = Get-ChildItem -Path $hooksLibSource -Filter '*.ps1' -File
                if ($ps1Items.Count -gt 0) {
                    Copy-Item -Path "$hooksLibSource\*.ps1" -Destination $hooksLibDir -Force -ErrorAction Stop
                }
                $psm1Items = Get-ChildItem -Path $hooksLibSource -Filter '*.psm1' -File
                if ($psm1Items.Count -gt 0) {
                    Copy-Item -Path "$hooksLibSource\*.psm1" -Destination $hooksLibDir -Force -ErrorAction Stop
                }
            } catch {
                Write-Err "Failed to copy hook lib scripts: $_"
            }
            Get-ChildItem -Path $hooksLibSource -Filter '*.sh' -File -ErrorAction SilentlyContinue | ForEach-Object {
                Install-BashScript -SourcePath $_.FullName -DestinationPath (Join-Path $hooksLibDir $_.Name)
            }
        }

        # Shared bash validator library (issue #447 Phase 1). Mirrors the
        # install.sh block that copies repo-root hooks/lib/*.sh into
        # ~/.claude/hooks/lib/. pr-language-guard.sh and commit-message-guard.sh
        # source this library at runtime; without it the hooks fall back to the
        # inline english-only dispatcher regardless of CLAUDE_CONTENT_LANGUAGE.
        $sharedLibSource = Join-Path $BackupDir 'hooks/lib'
        if (Test-Path $sharedLibSource) {
            $hooksLibDir = Join-Path $hooksDir 'lib'
            Ensure-Directory $hooksLibDir
            foreach ($lib in @('validate-commit-message.sh', 'validate-language.sh')) {
                $libSrc = Join-Path $sharedLibSource $lib
                if (Test-Path $libSrc) {
                    Install-BashScript -SourcePath $libSrc -DestinationPath (Join-Path $hooksLibDir $lib)
                }
            }
        }

        try {
            $jsonItems = Get-ChildItem -Path $hooksSource -Filter '*.json' -File
            if ($jsonItems.Count -gt 0) {
                Copy-Item -Path "$hooksSource\*.json" -Destination $hooksDir -Force -ErrorAction Stop
            }
        } catch {
            Write-Err "Failed to copy json configurations: $_"
        }

        Write-Success "Hook scripts installed (hooks/*.ps1 + *.sh + lib/ + *.json)!"

        # Full-suite probe (issue #423): advertise which canonical guards the
        # plugin surface should stand down for. Written atomically via
        # Move-Item so a partial write cannot produce a half-valid probe.
        $probeFile = Join-Path $claudeDir ".full-suite-active"
        $probeTmp  = Join-Path $claudeDir ".full-suite-active.tmp"
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

    # Install utility scripts — dual-variant, same rationale as hooks.
    $scriptsSource = Join-Path $BackupDir "global/scripts"
    if (Test-Path $scriptsSource) {
        $scriptsDir = Join-Path $claudeDir "scripts"
        Ensure-Directory $scriptsDir

        try {
            $ps1Items = Get-ChildItem -Path $scriptsSource -Filter '*.ps1' -File
            if ($ps1Items.Count -gt 0) {
                Copy-Item -Path "$scriptsSource\*.ps1" -Destination $scriptsDir -Force -ErrorAction Stop
            }
        } catch {
            Write-Err "Failed to copy utility scripts: $_"
        }
        Get-ChildItem -Path $scriptsSource -Filter '*.sh' -File -ErrorAction SilentlyContinue | ForEach-Object {
            Install-BashScript -SourcePath $_.FullName -DestinationPath (Join-Path $scriptsDir $_.Name)
        }

        Write-Success "Utility scripts installed (scripts/*.ps1 + *.sh)!"
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
    Write-Warn "Important: Modify git-identity.md with your personal info!"
    Write-Host "  Edit: notepad `$HOME\.claude\git-identity.md"
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

    # Copy files
    Copy-Item -Path (Join-Path $BackupDir "project/CLAUDE.md") -Destination $projectDir -Force

    # .claude directory
    $projectClaudeDir = Join-Path $projectDir ".claude"
    Ensure-Directory $projectClaudeDir

    # settings.json
    $projectSettings = Join-Path $BackupDir "project/.claude/settings.json"
    if (Test-Path $projectSettings) {
        Copy-Item -Path $projectSettings -Destination $projectClaudeDir -Force
        Write-Success "Project hook settings (.claude/settings.json) installed!"
    }

    # rules directory
    $sourceRules = Join-Path $BackupDir "project/.claude/rules"
    if (Test-Path $sourceRules) {
        Copy-Item -Path $sourceRules -Destination $projectClaudeDir -Recurse -Force
        # Issue #411: render any .md.tmpl found under rules/ with the chosen policy phrase.
        Invoke-PolicyTemplatesInDir -Path (Join-Path $projectClaudeDir 'rules')
        Write-Success "Rules directory installed! (policy phrase: $(Get-PolicyPhrase))"
    }

    # Skills directory
    $sourceSkills = Join-Path $BackupDir "project/.claude/skills"
    if (Test-Path $sourceSkills) {
        Copy-Item -Path $sourceSkills -Destination $projectClaudeDir -Recurse -Force
        Write-Success "Skills directory installed!"
    }

    # commands directory
    $sourceCommands = Join-Path $BackupDir "project/.claude/commands"
    if (Test-Path $sourceCommands) {
        Copy-Item -Path $sourceCommands -Destination $projectClaudeDir -Recurse -Force
        Write-Success "Commands directory installed!"
    }

    # agents directory
    $sourceAgents = Join-Path $BackupDir "project/.claude/agents"
    if (Test-Path $sourceAgents) {
        Copy-Item -Path $sourceAgents -Destination $projectClaudeDir -Recurse -Force
        Write-Success "Agents directory installed!"
    }

    # .claudeignore (token optimization)
    $claudeIgnore = Join-Path $BackupDir "project/.claudeignore"
    if (Test-Path $claudeIgnore) {
        Copy-Item -Path $claudeIgnore -Destination $projectDir -Force
        Write-Success ".claudeignore installed!"
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
    Write-Host "    - ~/.config/ccstatusline/ (ccstatusline settings)"
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
Write-Host "4. Statusline npm packages (if not installed):"
Write-Host "     npm install -g ccstatusline claude-limitline"
Write-Host ""
Write-Host "5. Verify settings:"
Write-Host "     Get-Content `$HOME\.claude\CLAUDE.md"
Write-Host ""

Write-Success "Installation complete!"
