#!/usr/bin/env pwsh
#Requires -Version 7.0
# Plugin smoke test - validates plugin directory structure
# Run: pwsh tests/plugin/smoke-test.ps1

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:Passed = 0
$script:Failed = 0

function Pass {
    param([string]$Label)
    $script:Passed++
    Write-Host "  PASS: $Label" -ForegroundColor Green
}

function Fail {
    param([string]$Label)
    $script:Failed++
    Write-Host "  FAIL: $Label" -ForegroundColor Red
}

function Test-JsonFile {
    param([string]$FilePath)
    if ((Test-Path -LiteralPath $FilePath) ) {
        try {
            $null = Get-Content -Raw -LiteralPath $FilePath | ConvertFrom-Json
            Pass "$FilePath is valid JSON"
        } catch {
            Fail "$FilePath missing or invalid JSON"
        }
    } else {
        Fail "$FilePath missing or invalid JSON"
    }
}

function Test-DirectoryExists {
    param([string]$Dir, [string]$Label)
    if (Test-Path -LiteralPath $Dir -PathType Container) {
        Pass "$Label directory exists"
    } else {
        Fail "$Label directory missing: $Dir"
    }
}

function Test-Frontmatter {
    param([string]$FilePath, [string]$Field)
    $baseName = Split-Path -Leaf $FilePath
    $lines = Get-Content -LiteralPath $FilePath -TotalCount 20
    $found = $false
    foreach ($line in $lines) {
        if ($line -match "^${Field}:") {
            $found = $true
            break
        }
    }
    if ($found) {
        Pass "$baseName has '$Field' in frontmatter"
    } else {
        Fail "$baseName missing '$Field' in frontmatter"
    }
}

function Test-Plugin {
    param([string]$PluginDir)
    $name = Split-Path -Leaf $PluginDir

    Write-Host ''
    Write-Host "=== Validating $name ==="

    $manifest = Join-Path $PluginDir '.claude-plugin' 'plugin.json'
    Test-JsonFile -FilePath $manifest

    # Check referenced directories from manifest
    if (Test-Path -LiteralPath $manifest) {
        try {
            $manifestData = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json

            $agentsRef = $manifestData.agents
            $skillsRef = $manifestData.skills
            $hooksRef  = $manifestData.hooks

            if ($agentsRef) {
                Test-DirectoryExists -Dir (Join-Path $PluginDir $agentsRef) -Label "$name/agents"
            }
            if ($skillsRef) {
                Test-DirectoryExists -Dir (Join-Path $PluginDir $skillsRef) -Label "$name/skills"
            }
            if ($hooksRef) {
                $hooksPath = Join-Path $PluginDir $hooksRef
                if (Test-Path -LiteralPath $hooksPath) {
                    Pass "$name hooks file exists"
                } else {
                    Fail "$name hooks file missing: $hooksPath"
                }
            }
        } catch {
            # Manifest parse failed, already reported above
        }
    }

    # Validate SKILL.md frontmatter
    $skillFiles = Get-ChildItem -Path $PluginDir -Recurse -Filter 'SKILL.md' -ErrorAction SilentlyContinue
    foreach ($skillFile in $skillFiles) {
        Test-Frontmatter -FilePath $skillFile.FullName -Field 'name'
        Test-Frontmatter -FilePath $skillFile.FullName -Field 'description'
    }

    # Validate agent .md frontmatter
    $agentsDir = Join-Path $PluginDir 'agents'
    if (Test-Path -LiteralPath $agentsDir -PathType Container) {
        $agentFiles = Get-ChildItem -Path $agentsDir -Recurse -Filter '*.md' -ErrorAction SilentlyContinue
        foreach ($agentFile in $agentFiles) {
            Test-Frontmatter -FilePath $agentFile.FullName -Field 'name'
            Test-Frontmatter -FilePath $agentFile.FullName -Field 'description'
        }
    }
}

# Run validation for each plugin
foreach ($pluginName in @('plugin', 'plugin-lite')) {
    $pluginDir = Join-Path $RepoRoot $pluginName
    if (Test-Path -LiteralPath $pluginDir -PathType Container) {
        Test-Plugin -PluginDir $pluginDir
    } else {
        Write-Host ''
        Write-Host "=== Skipping $pluginName (not found) ==="
    }
}

# Summary
Write-Host ''
Write-Host '================================'
Write-Host "Summary: $($script:Passed) passed, $($script:Failed) failed"
Write-Host '================================'

if ($script:Failed -gt 0) {
    exit 1
}
exit 0
