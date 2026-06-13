#Requires -Version 7.0
# check_agents.ps1 — PowerShell twin of check_agents.sh.
# Drift guard for the 8 agent definitions duplicated across plugin/agents/
# and project/.claude/agents/. See check_agents.sh for the full rationale:
# frontmatter differs per layer and one repo-path sentence is genericized in
# the plugin copy; the bodies must otherwise stay identical. In addition the
# behavioral frontmatter fields `tools` and `permissionMode` must match across
# layers (intended per-layer fields like `color` are exempt).
# Exit: 0 = in sync, 2 = drift.

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir

$Agents = @(
    'code-reviewer'
    'codebase-analyzer'
    'dependency-auditor'
    'documentation-writer'
    'qa-reviewer'
    'refactor-assistant'
    'structure-explorer'
    'test-strategist'
)

function Get-NormalizedBody {
    param([string]$Path)
    $dashes = 0
    $body = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding utf8)) {
        if ($dashes -lt 2 -and $line -eq '---') { $dashes++; continue }
        if ($dashes -ge 2) {
            if ($line -match '^If .*language-specific rules.*read them before starting\.$') {
                $body.Add('<RULES_PATH_NOTE>')
            } else {
                $body.Add($line)
            }
        }
    }
    return ($body -join "`n")
}

# Extract the value of a frontmatter key from the first '---' block. Returns
# the empty string when the key is absent, so a key declared on only one layer
# surfaces as a drift.
function Get-FrontmatterField {
    param([string]$Path, [string]$Key)
    $dashes = 0
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding utf8)) {
        if ($line -eq '---') {
            $dashes++
            if ($dashes -ge 2) { break }
            continue
        }
        if ($dashes -eq 1 -and $line -match ('^' + [regex]::Escape($Key) + ':')) {
            return ($line -replace ('^' + [regex]::Escape($Key) + ':\s*'), '').TrimEnd()
        }
    }
    return ''
}

$drift = 0
foreach ($a in $Agents) {
    $p = Join-Path $RootDir "plugin/agents/$a.md"
    $c = Join-Path $RootDir "project/.claude/agents/$a.md"
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "FAIL: missing plugin/agents/$a.md"; $drift = 1; continue }
    if (-not (Test-Path -LiteralPath $c)) { Write-Host "FAIL: missing project/.claude/agents/$a.md"; $drift = 1; continue }
    if ((Get-NormalizedBody $p) -ne (Get-NormalizedBody $c)) {
        Write-Host "FAIL: agent body drift: plugin/agents/$a.md vs project/.claude/agents/$a.md"
        $drift = 1
    }

    # Behavioral frontmatter parity: layers may differ in declarative fields
    # (color, model, ...) but must agree on what the agent can do.
    foreach ($field in @('tools', 'permissionMode')) {
        $pv = Get-FrontmatterField $p $field
        $cv = Get-FrontmatterField $c $field
        if ($pv -ne $cv) {
            Write-Host "FAIL: frontmatter '$field' drift for $($a): plugin='$pv' project='$cv'"
            $drift = 1
        }
    }
}

if ($drift -eq 0) {
    Write-Host "check_agents: OK ($($Agents.Count) agent pairs: bodies + behavioral frontmatter in sync)"
    exit 0
}

Write-Host ""
Write-Host "check_agents: drift detected between plugin/agents and project/.claude/agents."
exit 2
