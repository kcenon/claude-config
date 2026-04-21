#Requires -Version 7.0
<#
.SYNOPSIS
    Matrix tests for global/hooks/lib/LanguageValidator.psm1 (issue #410).
.DESCRIPTION
    PowerShell mirror of tests/hooks/test-language-validator.sh. Asserts
    Test-ContentLanguage and Test-CommitDescriptionFirstChar behave
    identically to the bash dispatchers across english, korean_plus_english,
    and any policies.

    Uses plain PowerShell assertions - no Pester dependency.
#>

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$Module  = Join-Path $RootDir 'global' 'hooks' 'lib' 'LanguageValidator.psm1'

Import-Module $Module -Force

$script:PASS = 0
$script:FAIL = 0

function Invoke-LangCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$ExpectedValid,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Policy,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$Commit
    )
    $env:CLAUDE_CONTENT_LANGUAGE = $Policy
    try {
        if ($Commit) {
            $r = Test-CommitDescriptionFirstChar -Description $Text
        } else {
            $r = Test-ContentLanguage -Text $Text
        }
    }
    finally {
        $env:CLAUDE_CONTENT_LANGUAGE = $null
    }

    if ($r.Valid -eq $ExpectedValid) {
        $script:PASS++
        Write-Host "  PASS: $Name"
    } else {
        $script:FAIL++
        Write-Host "  FAIL: $Name (expected Valid=$ExpectedValid, got=$($r.Valid))" -ForegroundColor Red
    }
}

Write-Host "=== LanguageValidator.psm1 — Test-ContentLanguage ==="
Write-Host ""
Write-Host "[english policy]"
Invoke-LangCase -Name "unset policy accepts ASCII"          -ExpectedValid $true  -Policy ''          -Text "simple ASCII"
Invoke-LangCase -Name "english rejects Hangul"              -ExpectedValid $false -Policy 'english'   -Text "한국어"
Invoke-LangCase -Name "english rejects accented Latin"      -ExpectedValid $false -Policy 'english'   -Text "café"
Invoke-LangCase -Name "english rejects emoji"               -ExpectedValid $false -Policy 'english'   -Text "party 🎉"

Write-Host ""
Write-Host "[korean_plus_english policy]"
Invoke-LangCase -Name "korean+en accepts Hangul syllables"  -ExpectedValid $true  -Policy 'korean_plus_english' -Text "한국어"
Invoke-LangCase -Name "korean+en accepts Jamo"              -ExpectedValid $true  -Policy 'korean_plus_english' -Text "ㄱㄴㄷ"
Invoke-LangCase -Name "korean+en accepts mixed"             -ExpectedValid $true  -Policy 'korean_plus_english' -Text "fix 버그"
Invoke-LangCase -Name "korean+en rejects Japanese"          -ExpectedValid $false -Policy 'korean_plus_english' -Text "こんにちは"
Invoke-LangCase -Name "korean+en rejects Chinese"           -ExpectedValid $false -Policy 'korean_plus_english' -Text "你好"
Invoke-LangCase -Name "korean+en rejects emoji"             -ExpectedValid $false -Policy 'korean_plus_english' -Text "rocket 🚀"

Write-Host ""
Write-Host "[any policy]"
Invoke-LangCase -Name "any accepts Japanese"                -ExpectedValid $true  -Policy 'any'       -Text "こんにちは"
Invoke-LangCase -Name "any accepts emoji"                   -ExpectedValid $true  -Policy 'any'       -Text "fête 🎉"
Invoke-LangCase -Name "any accepts mixed unicode"           -ExpectedValid $true  -Policy 'any'       -Text "Ω Я 中"

Write-Host ""
Write-Host "[empty input always valid]"
Invoke-LangCase -Name "english + empty"                     -ExpectedValid $true  -Policy 'english'              -Text ""
Invoke-LangCase -Name "korean+en + empty"                   -ExpectedValid $true  -Policy 'korean_plus_english'  -Text ""
Invoke-LangCase -Name "any + empty"                         -ExpectedValid $true  -Policy 'any'                  -Text ""

Write-Host ""
Write-Host "[unknown policy falls back to english]"
Invoke-LangCase -Name "martian rejects Hangul"              -ExpectedValid $false -Policy 'martian'   -Text "한국어"
Invoke-LangCase -Name "martian accepts ASCII"               -ExpectedValid $true  -Policy 'martian'   -Text "plain"

Write-Host ""
Write-Host "=== Test-CommitDescriptionFirstChar ==="
Write-Host ""
Write-Host "[english policy — lowercase ASCII only]"
Invoke-LangCase -Name "english accepts 'add feature'"       -ExpectedValid $true  -Policy 'english'  -Text "add feature" -Commit
Invoke-LangCase -Name "english rejects 'Add feature'"       -ExpectedValid $false -Policy 'english'  -Text "Add feature" -Commit
Invoke-LangCase -Name "english rejects '기능 추가'"           -ExpectedValid $false -Policy 'english'  -Text "기능 추가" -Commit

Write-Host ""
Write-Host "[korean_plus_english policy — accepts Hangul first char]"
Invoke-LangCase -Name "korean+en accepts 'add'"             -ExpectedValid $true  -Policy 'korean_plus_english'  -Text "add"       -Commit
Invoke-LangCase -Name "korean+en accepts '기능 추가'"         -ExpectedValid $true  -Policy 'korean_plus_english'  -Text "기능 추가"  -Commit
Invoke-LangCase -Name "korean+en rejects 'Add'"             -ExpectedValid $false -Policy 'korean_plus_english'  -Text "Add"       -Commit

Write-Host ""
Write-Host "[any policy — Rule 2 bypassed]"
Invoke-LangCase -Name "any accepts 'Mixed Case'"            -ExpectedValid $true  -Policy 'any'      -Text "Mixed Case" -Commit
Invoke-LangCase -Name "any accepts 'Начало'"                -ExpectedValid $true  -Policy 'any'      -Text "Начало"    -Commit

Write-Host ""
Write-Host "=== Results: $($script:PASS) passed, $($script:FAIL) failed ==="

if ($script:FAIL -gt 0) { exit 1 }
exit 0
