#Requires -Version 7.0
# LanguageValidator.psm1 — Shared PowerShell content-language validators.
#
# PowerShell mirror of hooks/lib/validate-language.sh and Rule 2 of
# hooks/lib/validate-commit-message.sh. The bash libraries are the
# authoritative source of truth; keep the character sets in sync with them.
#
# The CLAUDE_CONTENT_LANGUAGE environment variable selects the policy:
#   - english (default, unset, or empty) → ASCII printable + whitespace only
#   - korean_plus_english → ASCII + Hangul syllables/Jamo/Compat Jamo
#   - any → validation skipped (always valid)
#
# NOTE: These validators do NOT gate AI/Claude attribution. attribution-guard.ps1
# and the attribution checks in commit-message-guard.ps1 remain active for
# every policy value — attribution blocking is a hard rule, not a language
# concern. See issue #410 for the scope boundary.

# Get-ContentLanguagePolicy
# Returns the resolved policy string (english | korean_plus_english | any).
# Unknown values fall back to english and write a warning to stderr.
function Get-ContentLanguagePolicy {
    $policy = $env:CLAUDE_CONTENT_LANGUAGE
    if ([string]::IsNullOrEmpty($policy)) {
        return 'english'
    }
    switch ($policy) {
        'english'              { return 'english' }
        'korean_plus_english'  { return 'korean_plus_english' }
        'any'                  { return 'any' }
        default {
            [Console]::Error.WriteLine("CLAUDE_CONTENT_LANGUAGE has unknown value '$policy'. Valid values: english, korean_plus_english, any.")
            return 'english'
        }
    }
}

# Test-CodePointAllowed
# Internal helper — returns $true if the code point is inside one of the
# allowed ranges for the given policy.
function Test-CodePointAllowed {
    param(
        [Parameter(Mandatory)][int]$CodePoint,
        [Parameter(Mandatory)][string]$Policy
    )
    # ASCII printable + whitespace (shared across english and korean_plus_english)
    if (($CodePoint -ge 0x20 -and $CodePoint -le 0x7E) -or
        ($CodePoint -ge 0x09 -and $CodePoint -le 0x0D)) {
        return $true
    }
    if ($Policy -eq 'korean_plus_english') {
        # Hangul Syllables / Jamo / Compat Jamo
        if (($CodePoint -ge 0xAC00 -and $CodePoint -le 0xD7A3) -or
            ($CodePoint -ge 0x1100 -and $CodePoint -le 0x11FF) -or
            ($CodePoint -ge 0x3130 -and $CodePoint -le 0x318F)) {
            return $true
        }
    }
    return $false
}

# Find-FirstDisallowedElement
# Returns the first grapheme cluster that is not allowed under the given
# policy, or $null if every element is allowed. Uses StringInfo so
# surrogate pairs count as a single element.
function Find-FirstDisallowedElement {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Policy
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $null
    }

    $info = [System.Globalization.StringInfo]::new($Text)
    for ($i = 0; $i -lt $info.LengthInTextElements; $i++) {
        $elem = $info.SubstringByTextElements($i, 1)
        $cp = [Char]::ConvertToUtf32($elem, 0)
        if (-not (Test-CodePointAllowed -CodePoint $cp -Policy $Policy)) {
            return $elem
        }
    }
    return $null
}

# Test-ContentLanguage
# Returns a PSCustomObject with:
#   Valid  [bool]   - $true when the text satisfies the resolved policy
#   Policy [string] - the resolved policy
#   Reason [string] - user-facing rejection message when Valid is $false
# Callers translate Reason into New-HookDenyResponse payloads.
function Test-ContentLanguage {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $policy = Get-ContentLanguagePolicy

    if ([string]::IsNullOrEmpty($Text) -or $policy -eq 'any') {
        return [PSCustomObject]@{
            Valid  = $true
            Policy = $policy
            Reason = ''
        }
    }

    $bad = Find-FirstDisallowedElement -Text $Text -Policy $policy
    if ($null -eq $bad) {
        return [PSCustomObject]@{
            Valid  = $true
            Policy = $policy
            Reason = ''
        }
    }

    switch ($policy) {
        'korean_plus_english' {
            $reason = "Text contains characters outside the English+Korean policy (first: '$bad'). CLAUDE_CONTENT_LANGUAGE=korean_plus_english allows ASCII and Hangul only."
        }
        default {
            $reason = "Text contains non-ASCII characters (first: '$bad'). GitHub Issues and Pull Requests must be written in English only — see commit-settings.md."
        }
    }

    return [PSCustomObject]@{
        Valid  = $false
        Policy = $policy
        Reason = $reason
    }
}

# Test-CommitDescriptionFirstChar
# Applies Rule 2 of the commit-message validator under the resolved policy.
# Returns a PSCustomObject mirroring Test-ContentLanguage.
function Test-CommitDescriptionFirstChar {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Description
    )

    $policy = Get-ContentLanguagePolicy

    if ($policy -eq 'any') {
        return [PSCustomObject]@{ Valid = $true; Policy = $policy; Reason = '' }
    }

    if ([string]::IsNullOrEmpty($Description)) {
        return [PSCustomObject]@{
            Valid  = $false
            Policy = $policy
            Reason = 'Commit message description must not be empty.'
        }
    }

    $first = $Description[0]

    if ($policy -eq 'korean_plus_english') {
        $cp = [Char]::ConvertToUtf32($Description, 0)
        $isLowerAscii = ($first -ge 'a' -and $first -le 'z')
        $isHangul = (($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or
                     ($cp -ge 0x1100 -and $cp -le 0x11FF) -or
                     ($cp -ge 0x3130 -and $cp -le 0x318F))
        if ($isLowerAscii -or $isHangul) {
            return [PSCustomObject]@{ Valid = $true; Policy = $policy; Reason = '' }
        }
        return [PSCustomObject]@{
            Valid  = $false
            Policy = $policy
            Reason = 'Commit message description must start with a lowercase letter or a Hangul character (CLAUDE_CONTENT_LANGUAGE=korean_plus_english).'
        }
    }

    # english (default)
    if ($first -cmatch '[a-z]') {
        return [PSCustomObject]@{ Valid = $true; Policy = $policy; Reason = '' }
    }
    return [PSCustomObject]@{
        Valid  = $false
        Policy = $policy
        Reason = 'Commit message description must start with a lowercase letter.'
    }
}

Export-ModuleMember -Function @(
    'Get-ContentLanguagePolicy'
    'Test-CodePointAllowed'
    'Find-FirstDisallowedElement'
    'Test-ContentLanguage'
    'Test-CommitDescriptionFirstChar'
)
