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
#   - exclusive_bilingual → per-document: english_only when text has no
#                           Hangul syllables, otherwise korean_with_tech_terms
#                           (bare English tokens rejected; only ASCII inside
#                           fenced/inline code, URLs, or 한국어(English)
#                           translation forms is allowed in Korean mode)
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
        'exclusive_bilingual'  { return 'exclusive_bilingual' }
        'any'                  { return 'any' }
        default {
            [Console]::Error.WriteLine("CLAUDE_CONTENT_LANGUAGE has unknown value '$policy'. Valid values: english, korean_plus_english, exclusive_bilingual, any.")
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

# Test-KoreanWithTechTerms
# Korean-mode branch of the exclusive_bilingual policy (issue #447).
# Strips the four allowed ASCII containers (fenced code, inline code,
# URLs, 한국어(English) translation form) and then rejects any residual
# [A-Za-z] character as a bare English token.
#
# Strip ordering matches the bash sibling in
# hooks/lib/validate-language.sh::validate_korean_with_tech_terms:
#   1. Fenced code blocks.
#   2. Inline code.
#   3. URLs.
#   4. 한글(English) translation form.
#
# Returns a PSCustomObject mirroring Test-ContentLanguage.
function Test-KoreanWithTechTerms {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return [PSCustomObject]@{ Valid = $true; Policy = 'exclusive_bilingual'; Reason = '' }
    }

    $stripped = $Text
    # 1. Fenced code blocks — (?s) makes . match newlines; non-greedy.
    $stripped = [regex]::Replace($stripped, '(?s)```.*?```', '')
    # 2. Inline code — single backtick, no newlines crossed.
    $stripped = [regex]::Replace($stripped, '`[^`\n]*`', '')
    # 3. URLs — https?:// runs of non-whitespace.
    $stripped = [regex]::Replace($stripped, 'https?://\S+', '')
    # 4. 한글(English) translation form — Hangul run followed by optional
    #    whitespace and a parenthesized ASCII expression on one line.
    $stripped = [regex]::Replace($stripped, '[가-힣]+\s*\([^)\n]*\)', '')

    $m = [regex]::Match($stripped, '[A-Za-z]+')
    if ($m.Success) {
        $sample = $m.Value
        return [PSCustomObject]@{
            Valid  = $false
            Policy = 'exclusive_bilingual'
            Reason = "Korean-mode policy violation: bare English token '$sample' detected. Wrap in backticks or use the '한국어(English)' form. CLAUDE_CONTENT_LANGUAGE=exclusive_bilingual requires document-level language exclusivity."
        }
    }

    return [PSCustomObject]@{ Valid = $true; Policy = 'exclusive_bilingual'; Reason = '' }
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

    # exclusive_bilingual routes per-document based on Hangul presence
    # (see issue #447). Delegate to the helpers before the generic
    # character whitelist path below.
    if ($policy -eq 'exclusive_bilingual') {
        if ($Text -match '[가-힣]') {
            return Test-KoreanWithTechTerms -Text $Text
        }
        # No Hangul — validate as english. Reuse the whitelist path
        # below by dropping through with a forced english policy.
        $policy = 'english'
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
    'Test-KoreanWithTechTerms'
    'Test-ContentLanguage'
    'Test-CommitDescriptionFirstChar'
)
