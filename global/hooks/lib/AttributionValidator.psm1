#Requires -Version 7.0
# AttributionValidator.psm1 — Shared AI/Claude attribution detection.
#
# Single source of truth for the three-pattern attribution design, imported
# by attribution-guard.ps1 (gh pr/issue/release text fields) and
# commit-message-guard.ps1 (git commit messages). Mirrors the bash authority
# hooks/lib/validate-commit-message.sh. When updating a pattern here, update
# that bash library too so enforcement stays consistent across hosts.
#
# Three-pattern design:
#   1. Trailer-style attribution at line start (Co-Authored-By: Claude ...)
#   2. Bot emoji adjacent to Claude/Anthropic
#   3. Generated|Created|Authored {with|by|using} {Claude|Anthropic} prose
# Casual prose mentions ("Claude API", "Anthropic SDK") are deliberately
# allowed to eliminate false positives on legitimate technical writing.

$script:AttributionTrailerRegex = '(?m)^\s*(Co-[Aa]uthored-[Bb]y|Co-[Aa]uthor|[Gg]enerated[- ]?[Bb]y|[Cc]reated[- ]?[Bb]y|[Aa]uthored[- ]?[Bb]y|[Ss]igned-[Oo]ff-[Bb]y|[Aa]ssisted-[Bb]y)\s*:\s*.*([Cc]laude|[Aa]nthropic|AI[- ]?[Aa]ssisted)'
$script:AttributionEmojiRegex   = '🤖\s*\S*\s*([Cc]laude|[Aa]nthropic)'
$script:AttributionProseRegex   = '([Gg]enerated|[Cc]reated|[Aa]uthored|[Ww]ritten)\s+(with|by|using)\s+(Claude|Anthropic|AI[- ]?[Aa]ssistant)'

# Test-AttributionReason
# Returns a user-facing rejection reason string when $Text contains an
# attribution marker matching one of the three patterns, or $null when the
# text is clean (including casual technical mentions of Claude/Anthropic).
function Test-AttributionReason {
    param([string]$Text)
    if (-not $Text) { return $null }
    if ($Text -match $script:AttributionTrailerRegex) {
        return 'Text contains AI/Claude attribution trailer (Co-Authored-By: / Generated-by: / Authored-by: Claude or Anthropic). Remove the trailer before submitting.'
    }
    if ($Text -match $script:AttributionEmojiRegex) {
        return 'Text contains AI bot emoji adjacent to Claude/Anthropic attribution. Remove the marker before submitting.'
    }
    if ($Text -match $script:AttributionProseRegex) {
        return "Text contains AI/Claude attribution prose (e.g. 'Generated with Claude'). Remove the attribution before submitting."
    }
    return $null
}

Export-ModuleMember -Function @('Test-AttributionReason')
