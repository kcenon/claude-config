#Requires -Version 7.0

# Claude Configuration Verification Tool
# =======================================
# Ported from verify.sh

param(
    # Deployed global layer to compare with global/.
    [string]$ClaudeDir = (Join-Path $HOME '.claude'),
    # Installed project to compare with project/. When omitted, the current
    # directory is used if it holds a project install manifest and is not this
    # checkout; otherwise the project comparison is skipped.
    [string]$ProjectDir
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Import shared module
$ModulePath = Join-Path (Split-Path $PSScriptRoot) 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
if (-not (Test-Path $ModulePath)) {
    $ModulePath = Join-Path $PSScriptRoot '..' 'global' 'hooks' 'lib' 'CommonHelpers.psm1'
}
Import-Module $ModulePath -Force

# Script and backup directory paths
$ScriptDir = $PSScriptRoot
$BackupDir = Split-Path -Parent $ScriptDir

Write-Banner -Title 'Claude Configuration Verification Tool'

# Counters
$script:TOTAL_CHECKS   = 0
$script:PASSED_CHECKS  = 0
$script:FAILED_CHECKS  = 0
$script:WARNING_CHECKS = 0

# ── Verification functions ───────────────────────────────────

function Test-FileExists {
    param(
        [string]$FilePath,
        [string]$Description
    )
    $script:TOTAL_CHECKS++

    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        $size = (Get-Item -LiteralPath $FilePath).Length
        Write-SuccessMessage "$Description (${size} bytes)"
        $script:PASSED_CHECKS++
        return $true
    }
    else {
        Write-ErrorMessage "$Description (없음)"
        $script:FAILED_CHECKS++
        return $false
    }
}

function Test-DirExists {
    param(
        [string]$DirPath,
        [string]$Description
    )
    $script:TOTAL_CHECKS++

    if (Test-Path -LiteralPath $DirPath -PathType Container) {
        $count = (Get-ChildItem -LiteralPath $DirPath -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-SuccessMessage "$Description (${count} 파일)"
        $script:PASSED_CHECKS++
        return $true
    }
    else {
        Write-ErrorMessage "$Description (없음)"
        $script:FAILED_CHECKS++
        return $false
    }
}

function Test-ExecutableFile {
    param(
        [string]$FilePath,
        [string]$Description
    )
    $script:TOTAL_CHECKS++

    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        # On Windows all files are "executable"; on Unix check execute bit
        if ($IsWindows) {
            Write-SuccessMessage "$Description (실행 가능)"
            $script:PASSED_CHECKS++
            return $true
        }
        else {
            $mode = (Get-Item -LiteralPath $FilePath).UnixMode
            if ($mode -and $mode -match 'x') {
                Write-SuccessMessage "$Description (실행 가능)"
                $script:PASSED_CHECKS++
                return $true
            }
            else {
                Write-WarningMessage "$Description (실행 권한 없음)"
                $script:FAILED_CHECKS++
                return $false
            }
        }
    }
    else {
        Write-WarningMessage "$Description (실행 권한 없음)"
        $script:FAILED_CHECKS++
        return $false
    }
}

function Test-NpmPackage {
    param(
        [string]$Package,
        [string]$Description
    )
    $script:TOTAL_CHECKS++

    $cmd = Get-Command $Package -ErrorAction SilentlyContinue
    if ($cmd) {
        $version = 'unknown'
        try { $version = & $Package --version 2>$null } catch {}
        Write-SuccessMessage "$Description (v${version})"
        $script:PASSED_CHECKS++
        return $true
    }
    else {
        Write-WarningMessage "$Description (미설치 - 선택사항)"
        $script:WARNING_CHECKS++
        $script:PASSED_CHECKS++
        return $false
    }
}

function Test-ImportSyntax {
    <#
    .SYNOPSIS
        Validates @import syntax in CLAUDE.md / SKILL.md files.
    #>
    param([string]$FilePath)

    $lines = Get-Content -LiteralPath $FilePath -ErrorAction SilentlyContinue
    $invalidLines = @()

    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        # Lines starting with @ but not ./ ~/ / or known directives
        if ($line -match '^@[^./~@]') {
            # Skip known patterns
            if ($line -match '^@https')    { continue }
            if ($line -match '^@load:')    { continue }
            if ($line -match '^@skip:')    { continue }
            if ($line -match '^@focus:')   { continue }
            if ($line -match '^@context:') { continue }
            if ($line -match '@app\.')     { continue }
            if ($line -match '@pytest\.')  { continue }
            if ($line -match '@limiter\.') { continue }
            if ($line -match '@before_')   { continue }
            if ($line -match '@after_')    { continue }
            $invalidLines += "${lineNum}: $line"
        }
    }

    if ($invalidLines.Count -gt 0) {
        Write-ErrorMessage "Invalid import syntax in $FilePath"
        Write-Host "  Use @./path for relative or @~/path for home directory"
        Write-Host "  Found:"
        foreach ($il in $invalidLines) {
            Write-Host "    $il"
        }
        return $false
    }
    return $true
}

# ── Backup directory structure verification ──────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "백업 구조 검증"
Write-Host "======================================================"
Write-Host ""

Write-Host "디렉토리 구조:"
Test-DirExists (Join-Path $BackupDir 'global')  '글로벌 설정 디렉토리' | Out-Null
Test-DirExists (Join-Path $BackupDir 'project') '프로젝트 설정 디렉토리' | Out-Null
Test-DirExists (Join-Path $BackupDir 'scripts') '스크립트 디렉토리' | Out-Null

# ── Global settings file verification ────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "글로벌 설정 파일 검증"
Write-Host "======================================================"
Write-Host ""

Test-FileExists (Join-Path $BackupDir 'global' 'CLAUDE.md')           'CLAUDE.md' | Out-Null
Test-FileExists (Join-Path $BackupDir 'global' 'commit-settings.md')  'commit-settings.md' | Out-Null
Test-FileExists (Join-Path $BackupDir 'global' 'settings.json')       'settings.json (Hook 설정)' | Out-Null
Test-FileExists (Join-Path $BackupDir 'global' 'ccstatusline' 'settings.json') 'ccstatusline/settings.json (설치 대상: ~/.config/ccstatusline/)' | Out-Null

# JSON validity check for settings.json
$settingsJson = Join-Path $BackupDir 'global' 'settings.json'
if (Test-Path -LiteralPath $settingsJson -PathType Leaf) {
    $script:TOTAL_CHECKS++
    try {
        Get-Content -LiteralPath $settingsJson -Raw | ConvertFrom-Json | Out-Null
        Write-SuccessMessage "settings.json JSON 유효성 검사 통과"
        $script:PASSED_CHECKS++
    }
    catch {
        Write-ErrorMessage "settings.json JSON 유효성 검사 실패"
        $script:FAILED_CHECKS++
    }
}

# Hook shared library verification (issue #586 regression guard).
# Catches a backup that ships without the canonical .sh libraries the two
# installers (install.sh / install.ps1) deploy to ~/.claude/hooks/lib/.
# dangerous-command-guard, gh-write-verb-guard, bash-write-guard and
# bash-sensitive-read-guard source tokenize-shell.sh; missing files weaken
# the Bash-channel guards.
$hookLibDir = Join-Path $BackupDir 'global' 'hooks' 'lib'
foreach ($lib in @('tokenize-shell.sh', 'path-utils.sh', 'timeout-wrapper.sh', 'rotate.sh')) {
    Test-FileExists (Join-Path $hookLibDir $lib) "global/hooks/lib/$lib" | Out-Null
}

# ── Project settings file verification ───────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "프로젝트 설정 파일 검증"
Write-Host "======================================================"
Write-Host ""

Test-FileExists (Join-Path $BackupDir 'project' 'CLAUDE.md')                 '프로젝트 CLAUDE.md' | Out-Null
Test-DirExists  (Join-Path $BackupDir 'project' '.claude')                   '.claude 디렉토리' | Out-Null
Test-DirExists  (Join-Path $BackupDir 'project' '.claude' 'rules')           '.claude/rules 디렉토리' | Out-Null
Test-DirExists  (Join-Path $BackupDir 'project' '.claude' 'reference')       '.claude/reference 디렉토리' | Out-Null
Test-FileExists (Join-Path $BackupDir 'project' '.claude' 'settings.json')   '프로젝트 settings.json (Hook 설정)' | Out-Null

# Project settings.json JSON validity
$projSettings = Join-Path $BackupDir 'project' '.claude' 'settings.json'
if (Test-Path -LiteralPath $projSettings -PathType Leaf) {
    $script:TOTAL_CHECKS++
    try {
        Get-Content -LiteralPath $projSettings -Raw | ConvertFrom-Json | Out-Null
        Write-SuccessMessage "프로젝트 settings.json JSON 유효성 검사 통과"
        $script:PASSED_CHECKS++
    }
    catch {
        Write-ErrorMessage "프로젝트 settings.json JSON 유효성 검사 실패"
        $script:FAILED_CHECKS++
    }
}

# ── Skills directory verification ────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "Skills 디렉토리 검증"
Write-Host "======================================================"
Write-Host ""

Test-DirExists (Join-Path $BackupDir 'project' '.claude' 'skills') 'skills 디렉토리' | Out-Null

$skillsDir = Join-Path $BackupDir 'project' '.claude' 'skills'
if (Test-Path -LiteralPath $skillsDir -PathType Container) {
    foreach ($skillDir in (Get-ChildItem -LiteralPath $skillsDir -Directory)) {
        $skillName = $skillDir.Name
        $script:TOTAL_CHECKS++
        $skillMd = Join-Path $skillDir.FullName 'SKILL.md'
        if (Test-Path -LiteralPath $skillMd -PathType Leaf) {
            Write-SuccessMessage "${skillName}/SKILL.md 존재"
            $script:PASSED_CHECKS++
        }
        else {
            Write-WarningMessage "${skillName}/SKILL.md 없음"
            $script:FAILED_CHECKS++
        }
    }
}

$rulesBase = Join-Path $BackupDir 'project' '.claude' 'rules'
if (Test-Path -LiteralPath $rulesBase -PathType Container) {
    Test-DirExists (Join-Path $rulesBase 'coding')             'rules/coding' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'operations')         'rules/operations' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'project-management') 'rules/project-management' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'workflow')           'rules/workflow' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'api')                'rules/api' | Out-Null
    Test-DirExists (Join-Path $rulesBase 'core')               'rules/core' | Out-Null
}

# ── Script verification ──────────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "스크립트 검증"
Write-Host "======================================================"
Write-Host ""

Test-FileExists     (Join-Path $BackupDir 'scripts' 'install.sh') 'install.sh' | Out-Null
Test-ExecutableFile (Join-Path $BackupDir 'scripts' 'install.sh') 'install.sh 실행 권한' | Out-Null

Test-FileExists     (Join-Path $BackupDir 'scripts' 'backup.sh')  'backup.sh' | Out-Null
Test-ExecutableFile (Join-Path $BackupDir 'scripts' 'backup.sh')  'backup.sh 실행 권한' | Out-Null

Test-FileExists     (Join-Path $BackupDir 'scripts' 'sync.sh')    'sync.sh' | Out-Null
Test-ExecutableFile (Join-Path $BackupDir 'scripts' 'sync.sh')    'sync.sh 실행 권한' | Out-Null

# ── npm package verification (optional) ──────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "npm 패키지 검증 (선택사항)"
Write-Host "======================================================"
Write-Host ""

Test-NpmPackage 'ccstatusline'    'ccstatusline (Statusline 디스플레이)' | Out-Null
Test-NpmPackage 'claude-limitline' 'claude-limitline (사용량 표시)' | Out-Null

if ($script:WARNING_CHECKS -gt 0) {
    Write-Host ""
    Write-InfoMessage "누락된 npm 패키지 설치:"
    Write-Host "    npm install -g ccstatusline claude-limitline"
}

# ── Documentation verification ───────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "문서 검증"
Write-Host "======================================================"
Write-Host ""

Test-FileExists (Join-Path $BackupDir 'README.md')    'README.md' | Out-Null
Test-FileExists (Join-Path $BackupDir 'QUICKSTART.md') 'QUICKSTART.md' | Out-Null
Test-FileExists (Join-Path $BackupDir 'HOOKS.md')      'HOOKS.md (Hook 가이드)' | Out-Null

# ── Import syntax verification ───────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "Import 문법 검증 (@import syntax)"
Write-Host "======================================================"
Write-Host ""

$importCheckFiles = @(
    (Join-Path $BackupDir 'global'  'CLAUDE.md')
    (Join-Path $BackupDir 'project' 'CLAUDE.md')
)

foreach ($checkFile in $importCheckFiles) {
    if (Test-Path -LiteralPath $checkFile -PathType Leaf) {
        $script:TOTAL_CHECKS++
        if (Test-ImportSyntax $checkFile) {
            $parent = Split-Path (Split-Path $checkFile) -Leaf
            $name   = Split-Path $checkFile -Leaf
            Write-SuccessMessage "${parent}/${name} import 문법 검증 통과"
            $script:PASSED_CHECKS++
        }
        else {
            $script:FAILED_CHECKS++
        }
    }
}

# SKILL.md import syntax verification
$skillsDirProject = Join-Path $BackupDir 'project' '.claude' 'skills'
if (Test-Path -LiteralPath $skillsDirProject -PathType Container) {
    foreach ($sf in (Get-ChildItem -LiteralPath $skillsDirProject -Recurse -Filter 'SKILL.md')) {
        $skillName = $sf.Directory.Name
        $script:TOTAL_CHECKS++
        if (Test-ImportSyntax $sf.FullName) {
            Write-SuccessMessage "skills/${skillName}/SKILL.md import 문법 검증 통과"
            $script:PASSED_CHECKS++
        }
        else {
            $script:FAILED_CHECKS++
        }
    }
}

$pluginSkillsDir = Join-Path $BackupDir 'plugin' 'skills'
if (Test-Path -LiteralPath $pluginSkillsDir -PathType Container) {
    foreach ($sf in (Get-ChildItem -LiteralPath $pluginSkillsDir -Recurse -Filter 'SKILL.md')) {
        $skillName = $sf.Directory.Name
        $script:TOTAL_CHECKS++
        if (Test-ImportSyntax $sf.FullName) {
            Write-SuccessMessage "plugin/skills/${skillName}/SKILL.md import 문법 검증 통과"
            $script:PASSED_CHECKS++
        }
        else {
            $script:FAILED_CHECKS++
        }
    }
}

# ── System sync verification ─────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "시스템 동기화 검증 (source vs ~/.claude/)"
Write-Host "======================================================"
Write-Host ""

$SYNC_TOTAL = 0
$SYNC_OK    = 0
$SYNC_DIFF  = 0
$SYNC_MISS  = 0

function Get-SyncText {
    # File content as the installers leave it: a UTF-8 BOM dropped and CRLF
    # folded to LF (Install-BashScript rewrites every .sh that way). The
    # comparison is exact and case-sensitive after that; Compare-Object, used
    # before #944, ignored line order and case.
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $start = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $start = 3
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes, $start, $bytes.Length - $start).Replace("`r`n", "`n")
}

function Test-SyncFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Label
    )

    $script:SYNC_TOTAL++

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        Write-WarningMessage "MISS: $Label"
        $script:SYNC_MISS++
    }
    elseif ((Get-SyncText -Path $Source) -ceq (Get-SyncText -Path $Destination)) {
        Write-SuccessMessage "SYNC: $Label"
        $script:SYNC_OK++
    }
    else {
        Write-ErrorMessage "DIFF: $Label"
        $script:SYNC_DIFF++
    }
}

function Test-SyncRendered {
    # A rule rendered from X.md.tmpl at install time carries the chosen
    # language policy, so it cannot equal any source file. Check instead that
    # it exists and that no placeholder or tmpl-contract marker survived.
    param(
        [string]$Destination,
        [string]$Label
    )

    $script:SYNC_TOTAL++

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        Write-WarningMessage "MISS: $Label"
        $script:SYNC_MISS++
    }
    elseif ((Get-SyncText -Path $Destination) -cmatch '\{\{[A-Z_]+\}\}|tmpl-contract') {
        Write-ErrorMessage "DIFF: $Label (unrendered placeholder)"
        $script:SYNC_DIFF++
    }
    else {
        Write-SuccessMessage "SYNC: $Label (rendered)"
        $script:SYNC_OK++
    }
}

function Test-SyncTree {
    # Compares the files under $SourceDir that match $Filters with their
    # copies under $DestDir, the way Copy-ManifestTree and
    # Copy-InstallHookFiles deploy them. The installers render X.md.tmpl over
    # its X.md sibling, so X.md is checked with Test-SyncRendered instead.
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [string]$LabelPrefix,
        [string[]]$Filters = @('*'),
        [switch]$Recurse
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) { return }
    $root = [System.IO.Path]::GetFullPath($SourceDir).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $files = @(foreach ($filter in $Filters) {
        Get-ChildItem -LiteralPath $SourceDir -Filter $filter -File -Recurse:$Recurse -ErrorAction SilentlyContinue
    }) | Sort-Object FullName -Unique

    $rendered = @{}
    foreach ($tmpl in ($files | Where-Object { $_.Name -like '*.md.tmpl' })) {
        $rendered[$tmpl.FullName.Substring(0, $tmpl.FullName.Length - '.tmpl'.Length)] = $true
    }
    foreach ($srcFile in $files) {
        $full = $srcFile.FullName
        if ($full -like '*.md.tmpl') { $full = $full.Substring(0, $full.Length - '.tmpl'.Length) }
        elseif ($rendered.ContainsKey($full)) { continue }
        $rel = $full.Substring($root.Length + 1) -replace '\\', '/'
        $dest = Join-Path $DestDir $rel
        if ($rendered.ContainsKey($full)) {
            Test-SyncRendered -Destination $dest -Label "$LabelPrefix/$rel"
        }
        else {
            Test-SyncFile -Source $srcFile.FullName -Destination $dest -Label "$LabelPrefix/$rel"
        }
    }
}

function ConvertTo-CanonicalJson {
    # Order-insensitive rendering of a settings subtree: object keys sorted,
    # array order preserved (hook order within a matcher is significant).
    param($Node)

    if ($null -eq $Node) { return 'null' }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        $parts = foreach ($p in ($Node.PSObject.Properties | Sort-Object Name)) {
            '"{0}":{1}' -f $p.Name, (ConvertTo-CanonicalJson -Node $p.Value)
        }
        return '{' + ($parts -join ',') + '}'
    }
    if (($Node -is [System.Collections.IEnumerable]) -and ($Node -isnot [string])) {
        $items = foreach ($i in $Node) { ConvertTo-CanonicalJson -Node $i }
        return '[' + ($items -join ',') + ']'
    }
    return ($Node | ConvertTo-Json -Compress -Depth 32)
}

function Test-SyncSettings {
    # settings.json cannot be line-compared against its source profile: the
    # installer republishes it through ConvertTo-Json (install-manifest.ps1)
    # rather than copying bytes, so the deployed file is machine-serialized
    # while the profile is hand-formatted -- 11 of ~516 lines matched in order
    # when issue #914 measured it, for two semantically near-identical files.
    #
    # What the repo actually owns here is `permissions` (security) and `hooks`
    # (the runtime guards settings.json points at). Scalar preferences such as
    # model and effortLevel are machine-local; see issue #915.
    param([string]$Source, [string]$Destination)

    $script:SYNC_TOTAL++
    $label = 'settings.json (hooks + permissions)'

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        Write-WarningMessage "MISS: $label"
        $script:SYNC_MISS++
        return
    }

    try {
        $src = Get-Content -Raw -LiteralPath $Source | ConvertFrom-Json
        $dst = Get-Content -Raw -LiteralPath $Destination | ConvertFrom-Json
    }
    catch {
        Write-ErrorMessage "DIFF: $label (unparseable JSON)"
        $script:SYNC_DIFF++
        return
    }

    foreach ($key in @('permissions', 'hooks')) {
        if ((ConvertTo-CanonicalJson -Node $src.$key) -ne (ConvertTo-CanonicalJson -Node $dst.$key)) {
            Write-ErrorMessage "DIFF: $label -- $key"
            $script:SYNC_DIFF++
            return
        }
    }

    Write-SuccessMessage "SYNC: $label"
    $script:SYNC_OK++
}

$GlobalDst = $ClaudeDir
$installCmd = if ($IsWindows) { './scripts/install.ps1' } else { './scripts/install.sh' }

# Global config files. settings.json is excluded from the byte-wise loop and
# handled by Test-SyncSettings below.
Write-InfoMessage "글로벌 설정 파일 동기화:"
foreach ($f in @('CLAUDE.md', 'commit-settings.md', '.claudeignore')) {
    $src = Join-Path $BackupDir 'global' $f
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        Test-SyncFile -Source $src -Destination (Join-Path $GlobalDst $f) -Label $f
    }
}

# Windows publishes settings.windows.json as ~/.claude/settings.json; comparing
# against the POSIX profile reported a permanent DIFF here before #914.
$settingsProfile = if ($IsWindows) { 'settings.windows.json' } else { 'settings.json' }
$settingsSrc = Join-Path $BackupDir 'global' $settingsProfile
if (Test-Path -LiteralPath $settingsSrc -PathType Leaf) {
    Test-SyncSettings -Source $settingsSrc -Destination (Join-Path $GlobalDst 'settings.json')
}

# Global skills
Write-Host ""
Write-InfoMessage "글로벌 스킬 동기화:"
# Every file, not only *.md: skills also ship scripts and JSON (#944).
Test-SyncTree -SourceDir (Join-Path $BackupDir 'global' 'skills') -DestDir (Join-Path $GlobalDst 'skills') `
    -LabelPrefix 'skills' -Recurse

# Global hooks: the same file lists the installer deploys. Windows runs the
# .ps1 hooks and also receives .sh/.json for WSL and container parity
# (install.ps1 Deploy-InstallHooks); POSIX receives .sh only (install.sh
# deploy_install_hooks). Before #944 only the top-level .sh files were checked.
Write-Host ""
Write-InfoMessage "글로벌 Hook 스크립트 동기화:"
$globalHooksDir = Join-Path $BackupDir 'global' 'hooks'
$hookFilters = if ($IsWindows) { @('*.ps1', '*.sh', '*.json') } else { @('*.sh') }
$hookLibFilters = if ($IsWindows) { @('*.ps1', '*.psm1', '*.sh') } else { @('*.sh') }
Test-SyncTree -SourceDir $globalHooksDir -DestDir (Join-Path $GlobalDst 'hooks') -LabelPrefix 'hooks' -Filters $hookFilters
Test-SyncTree -SourceDir (Join-Path $globalHooksDir 'lib') -DestDir (Join-Path $GlobalDst 'hooks' 'lib') `
    -LabelPrefix 'hooks/lib' -Filters $hookLibFilters
foreach ($lib in @('validate-commit-message.sh', 'validate-language.sh', 'validate-traceability.sh')) {
    $src = Join-Path $BackupDir 'hooks' 'lib' $lib
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        Test-SyncFile -Source $src -Destination (Join-Path $GlobalDst 'hooks' 'lib' $lib) -Label "hooks/lib/$lib"
    }
}

# Installed project, compared with project/ the way install.ps1 and install.sh
# deploy it. A directory is detected only through its install manifest, so
# running verify inside an unrelated project skips this section.
Write-Host ""
if (-not $ProjectDir) {
    $cwd = (Get-Location).Path
    $cwdIsCheckout = [System.IO.Path]::GetFullPath($cwd).TrimEnd('\', '/') -eq
        [System.IO.Path]::GetFullPath($BackupDir).TrimEnd('\', '/')
    if (-not $cwdIsCheckout -and (Test-Path -LiteralPath (Join-Path $cwd '.claude' '.install-manifest.json') -PathType Leaf)) {
        $ProjectDir = $cwd
    }
}
if (-not $ProjectDir) {
    Write-InfoMessage "프로젝트 설치본 동기화: 건너뜀 (-ProjectDir <경로>로 지정)"
}
elseif (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) {
    Write-InfoMessage "프로젝트 설치본 동기화: $ProjectDir"
    Write-WarningMessage "MISS: project directory $ProjectDir"
    $SYNC_TOTAL++
    $SYNC_MISS++
}
else {
    Write-InfoMessage "프로젝트 설치본 동기화: $ProjectDir"
    $projectSrc = Join-Path $BackupDir 'project'
    foreach ($f in @('CLAUDE.md', '.claudeignore', '.claude/settings.json')) {
        $src = Join-Path $projectSrc $f
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Test-SyncFile -Source $src -Destination (Join-Path $ProjectDir $f) -Label "project/$f"
        }
    }
    foreach ($d in @('rules', 'reference', 'skills', 'commands', 'agents')) {
        Test-SyncTree -SourceDir (Join-Path $projectSrc '.claude' $d) -DestDir (Join-Path $ProjectDir '.claude' $d) `
            -LabelPrefix "project/.claude/$d" -Recurse
    }
}

# Sync summary
Write-Host ""
Write-Host "  ─────────────────────────────────────────"
Write-Host "  동기화 검사:   ${SYNC_TOTAL}개"
Write-Host "  일치:          ${SYNC_OK}개" -ForegroundColor Green
if ($SYNC_DIFF -gt 0) {
    Write-Host "  불일치:        ${SYNC_DIFF}개" -ForegroundColor Red
}
if ($SYNC_MISS -gt 0) {
    Write-Host "  미설치:        ${SYNC_MISS}개" -ForegroundColor Yellow
}
Write-Host "  ─────────────────────────────────────────"

if ($SYNC_DIFF -gt 0 -or $SYNC_MISS -gt 0) {
    Write-Host ""
    Write-WarningMessage "시스템이 소스와 동기화되지 않았습니다."
    Write-InfoMessage "동기화 방법: $installCmd (1: 글로벌, 2: 프로젝트, 3: 둘 다)"
}

# Add sync failures to main failure count
$script:FAILED_CHECKS += ($SYNC_DIFF + $SYNC_MISS)
$script:PASSED_CHECKS += $SYNC_OK
$script:TOTAL_CHECKS  += $SYNC_TOTAL

# ── Statistics ───────────────────────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "통계 정보"
Write-Host "======================================================"
Write-Host ""

$totalFiles = (Get-ChildItem -LiteralPath $BackupDir -Recurse -File -ErrorAction SilentlyContinue).Count
Write-InfoMessage "총 파일 수: $totalFiles"

# Total size
$totalBytes = (Get-ChildItem -LiteralPath $BackupDir -Recurse -File -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
if ($totalBytes -ge 1MB) {
    $totalSize = '{0:N1}M' -f ($totalBytes / 1MB)
}
elseif ($totalBytes -ge 1KB) {
    $totalSize = '{0:N1}K' -f ($totalBytes / 1KB)
}
else {
    $totalSize = "${totalBytes}B"
}
Write-InfoMessage "전체 크기: $totalSize"

$mdCount = (Get-ChildItem -LiteralPath $BackupDir -Recurse -Filter '*.md' -ErrorAction SilentlyContinue).Count
$shCount = (Get-ChildItem -LiteralPath $BackupDir -Recurse -Filter '*.sh' -ErrorAction SilentlyContinue).Count
Write-InfoMessage "Markdown 파일: $mdCount"
Write-InfoMessage "Shell 스크립트: $shCount"

# ── Verification result summary ──────────────────────────────

Write-Host ""
Write-Host "======================================================"
Write-InfoMessage "검증 결과 요약"
Write-Host "======================================================"
Write-Host ""

Write-Host "  총 검사 항목:   $($script:TOTAL_CHECKS)"
Write-Host "  통과:          $($script:PASSED_CHECKS)"
Write-Host "  실패:          $($script:FAILED_CHECKS)"
Write-Host "  경고 (선택사항): $($script:WARNING_CHECKS)"

if ($script:TOTAL_CHECKS -gt 0) {
    $successRate = [math]::Floor($script:PASSED_CHECKS * 100 / $script:TOTAL_CHECKS)
}
else {
    $successRate = 0
}

Write-Host ""
if ($script:FAILED_CHECKS -eq 0) {
    Write-SuccessMessage "모든 검증 통과! (100%)"
    Write-Host ""
    Write-InfoMessage "백업이 완전하고 사용 가능합니다."
    Write-Host ""
    Write-Host "다음 단계:"
    Write-Host "  1. 다른 시스템에 복사"
    Write-Host "  2. $installCmd 실행"
    exit 0
}
else {
    Write-WarningMessage "일부 검증 실패 (성공률: ${successRate}%)"
    # Sync failures are fixed by reinstalling; only the remaining failures
    # concern the backup tree itself.
    if (($SYNC_DIFF + $SYNC_MISS) -gt 0) {
        Write-Host ""
        Write-InfoMessage "설치본이 소스와 다릅니다. 다시 설치하세요:"
        Write-Host "  $installCmd"
    }
    if (($script:FAILED_CHECKS - $SYNC_DIFF - $SYNC_MISS) -gt 0) {
        Write-Host ""
        Write-InfoMessage "누락된 파일이 있습니다. 백업을 다시 생성하세요:"
        Write-Host "  ./scripts/backup.sh"
    }
    exit 1
}
