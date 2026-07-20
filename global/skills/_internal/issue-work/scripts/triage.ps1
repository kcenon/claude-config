#Requires -Version 7.0
# triage.ps1
# issue-work: triage state machine
# ================================
# PowerShell parity port of scripts/triage.sh. Same public functions, same
# deterministic and idempotent behavior, same outcome JSON schema, same comment
# fingerprint rule, same candidate eligibility predicate, same sort key, and the
# same injection seams. See reference/triage-state-machine.md for the contract
# both scripts satisfy.
#
# NOTE (authoring-time caveat): pwsh was not available in the environment this
# port was written in, so it was produced by mirroring the bash-verified logic
# in triage.sh line-for-line rather than by running it. It has NOT been executed.
# Cross-platform runtime regression coverage (a PowerShell test suite plus CI
# wiring) is tracked in issue #847 under epic #832, consistent with the existing
# PowerShell-parity notes for the workspace/agents/cleanup stages.
#
# The script is both a sourceable library (dot-source it to get the functions
# below) and a CLI:
#   pwsh -File triage.ps1 --repo <owner/name> [--issue <n>] [--plan-file <path>]
#        [--max-depth <n>] [--dry-run]
# CLI flags intentionally mirror triage.sh's flags exactly (rather than native
# PowerShell parameter binding) so the two entry points are interchangeable from
# a caller's point of view.
#
# The embedded python3 JSON parsing in triage.sh is replaced here with native
# ConvertFrom-Json, so this port carries no python3 dependency (matching the
# other issue-work PowerShell ports).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A non-zero exit from gh is data here, not an error: triage.sh reads
# `issue view` on a missing or closed issue as empty output and lets the retry
# and eligibility logic decide. A host that has enabled
# $PSNativeCommandUseErrorActionPreference would promote those exits to
# terminating errors under the 'Stop' preference above, so the setting is pinned
# off for this script. _triage_gh also lowers $ErrorActionPreference locally,
# which keeps the wrapper correct even if this line is ever removed.
$PSNativeCommandUseErrorActionPreference = $false

# Injection seams (overridable by tests and callers via environment variables,
# mirroring the bash GH_BIN / MAX_CHILD_DEPTH seams). TRIAGE_CURRENT_USER,
# TRIAGE_DRY_RUN, and TRIAGE_MAX_FAILURES are read directly from $env at their
# use sites, mirroring triage.sh's ${VAR:-default} at-use reads.
$script:GhBin = if ($env:GH_BIN) { $env:GH_BIN } else { 'gh' }
$script:MaxChildDepth = if ($env:MAX_CHILD_DEPTH) { [int]$env:MAX_CHILD_DEPTH } else { 5 }

# Tracked issue identities consumed by _triage_emit. Initialized here so a
# stray emit before run_triage can never trip StrictMode's uninitialized-var
# rule; run_triage resets all three at the start of every run.
$script:Requested = ''
$script:Root = ''
$script:Visited = ''

# ── Low-level gh wrapper ─────────────────────────────────────────────
# All GitHub access funnels through here so a fake gh can shadow it via
# $env:GH_BIN, mirroring _triage_gh in triage.sh.
#
# Native-command failure is surfaced via $LASTEXITCODE / empty stdout, never a
# thrown exception: $ErrorActionPreference is locally lowered to 'Continue' so a
# benign non-zero gh exit (e.g. `issue view` on a missing issue, which the retry
# and eligibility logic treats as empty output) does NOT become a terminating
# error under the script-scope 'Stop' preference on pwsh 7.4+
# ($PSNativeCommandUseErrorActionPreference). triage.sh relies on this tolerance
# throughout (the `if gh ...; then` / `$?` idioms); without it the negative paths
# (the three-failure fetch stop, closed/blocked reads) would throw instead of
# returning empty. This mirrors the guard already used by _prepr_git in
# pre-pr-gate.ps1.
function _triage_gh {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GhArgs)
    $ErrorActionPreference = 'Continue'
    & $script:GhBin @GhArgs
}

# ── Pure helpers (unit-testable without gh) ──────────────────────────

# Stable lowercase-hex SHA256 digest of the input. Matches `sha256sum` output
# (lowercase hex, no separators). Accepts input via the pipeline or the first
# positional parameter; the digest is computed over the UTF-8 bytes of the input
# with no added trailing newline (mirroring `printf '%s' ... | sha256sum`).
function triage_hash {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$InputString = ''
    )
    begin { $builder = [System.Text.StringBuilder]::new() }
    process { if ($null -ne $InputString) { [void]$builder.Append($InputString) } }
    end {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $digest = $sha.ComputeHash($bytes)
        } finally {
            $sha.Dispose()
        }
        return (([System.BitConverter]::ToString($digest)) -replace '-', '').ToLowerInvariant()
    }
}

# Extract blocker issue numbers from a body. Matches "Blocked by #N" and
# "Depends on #N" (case-insensitive). Returns the numbers as integers, sorted
# ascending and de-duplicated (the numeric-unique equivalent of `sort -un`).
function triage_extract_blockers {
    param([AllowEmptyString()][string]$Body = '')
    if ([string]::IsNullOrEmpty($Body)) { return @() }
    $seen = @{}
    $nums = New-Object System.Collections.Generic.List[int]
    foreach ($m in [regex]::Matches($Body, '(?i)(blocked by|depends on)\s+#([0-9]+)')) {
        $n = [int]$m.Groups[2].Value
        if (-not $seen.ContainsKey($n)) {
            $seen[$n] = $true
            [void]$nums.Add($n)
        }
    }
    return ($nums | Sort-Object)
}

# Map a comma-separated label list to a numeric priority rank (lower = higher
# priority). Unlabeled issues rank last.
function triage_priority_rank {
    param([AllowEmptyString()][string]$Labels = '')
    $set = ",$Labels,"
    if ($set -like '*,priority/critical,*') { return 0 }
    if ($set -like '*,priority/high,*')     { return 1 }
    if ($set -like '*,priority/medium,*')   { return 2 }
    if ($set -like '*,priority/low,*')      { return 3 }
    return 4
}

# Return $true if the raw comments blob already carries a marker of the given
# kind whose hash equals the supplied fingerprint (state unchanged -> skip
# posting). Return $false otherwise (no marker, or a different hash -> post).
# When a kind appears more than once, the last marker wins (mirrors `tail -n1`).
function triage_comment_marker_matches {
    param([AllowEmptyString()][string]$Raw = '', [string]$Kind, [string]$Fingerprint)
    $pattern = 'triage-fingerprint: ' + [regex]::Escape($Kind) + ':([0-9a-f]+)'
    $hits = [regex]::Matches($Raw, $pattern)
    if ($hits.Count -eq 0) { return $false }
    $existing = $hits[$hits.Count - 1].Groups[1].Value
    return ((-not [string]::IsNullOrEmpty($existing)) -and ($existing -eq $Fingerprint))
}

# Return $true if the raw comments blob carries any marker of the given kind.
function triage_comment_marker_present {
    param([AllowEmptyString()][string]$Raw = '', [string]$Kind)
    $pattern = 'triage-fingerprint: ' + [regex]::Escape($Kind) + ':[0-9a-f]+'
    return [regex]::IsMatch($Raw, $pattern)
}

# Eligibility predicate. Arguments are already-resolved scalar facts so the
# predicate itself is pure and testable. Returns $true when eligible.
#   State OPEN/CLOSED  Blocked true/false  OtherOnly true/false
#   ActivePr true/false  Visited true/false
function triage_is_eligible {
    param([string]$State, [string]$Blocked, [string]$OtherOnly, [string]$ActivePr, [string]$Visited)
    if ($State -ne 'OPEN')       { return $false }
    if ($Blocked -ne 'false')    { return $false }
    if ($OtherOnly -ne 'false')  { return $false }
    if ($ActivePr -ne 'false')   { return $false }
    if ($Visited -ne 'false')    { return $false }
    return $true
}

# ── JSON field extraction (native, no python3) ───────────────────────

# Safe property read: returns the property value coerced to a string, or '' when
# the object or property is absent/null. This is the ConvertFrom-Json equivalent
# of the python `x.get(<name>, "")` used by triage.sh, and it stays StrictMode
# safe by inspecting PSObject.Properties rather than dereferencing directly.
function _triage_prop {
    param($Item, [string]$Name)
    if ($null -eq $Item) { return '' }
    $p = $Item.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return '' }
    return [string]$p.Value
}

# Minimal field extraction from an issue JSON object. Replaces triage.sh's
# embedded python3 with native ConvertFrom-Json. Prints the requested scalar as
# a string; arrays are comma-joined with the same key rules as the bash version:
#   labels    -> comma-joined `.name` values
#   assignees -> comma-joined `.login` values
#   other list-> comma-joined string values
#   missing / null -> '' ; scalar -> value as-is
function _triage_field {
    param([AllowEmptyString()][string]$Json = '', [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Json)) { return '' }
    $obj = $null
    try {
        $obj = $Json | ConvertFrom-Json
    } catch {
        return ''
    }
    if ($null -eq $obj) { return '' }
    $prop = $obj.PSObject.Properties[$Field]
    if ($null -eq $prop) { return '' }
    $val = $prop.Value
    if ($null -eq $val) { return '' }
    if ($val -is [System.Array]) {
        if ($Field -eq 'labels') {
            return (@($val | ForEach-Object { _triage_prop $_ 'name' }) -join ',')
        } elseif ($Field -eq 'assignees') {
            return (@($val | ForEach-Object { _triage_prop $_ 'login' }) -join ',')
        } else {
            return (@($val | ForEach-Object { [string]$_ }) -join ',')
        }
    }
    return [string]$val
}

# ── gh-backed accessors ──────────────────────────────────────────────

function _triage_current_user {
    if (-not [string]::IsNullOrEmpty($env:TRIAGE_CURRENT_USER)) {
        return $env:TRIAGE_CURRENT_USER
    }
    return ((_triage_gh api user --jq '.login' 2>$null) | Out-String).Trim()
}

# Fetch a single issue as JSON. Returns the raw JSON object text ('' on failure).
function _triage_issue_json {
    param([string]$Repo, [string]$Num)
    return ((_triage_gh issue view $Num --repo $Repo --json 'number,title,state,body,labels,assignees,createdAt' 2>$null) | Out-String).Trim()
}

# Fetch with up to TRIAGE_MAX_FAILURES identical attempts. Returns the JSON text
# on success; returns $null only after the same fetch has failed that many times
# in a row, implementing the "stop after three identical failures" rule
# (#829 Risks) for the primary external dependency.
function _triage_issue_json_retry {
    param([string]$Repo, [string]$Num)
    $max = if ($env:TRIAGE_MAX_FAILURES) { [int]$env:TRIAGE_MAX_FAILURES } else { 3 }
    $attempt = 1
    while ($attempt -le $max) {
        $json = _triage_issue_json $Repo $Num
        if (-not [string]::IsNullOrEmpty($json)) { return $json }
        $attempt++
    }
    return $null
}

# Raw comments blob for marker scanning (matched as text, no JSON parse needed).
function _triage_comments_raw {
    param([string]$Repo, [string]$Num)
    return ((_triage_gh issue view $Num --repo $Repo --json comments 2>$null) | Out-String).Trim()
}

# True when an open PR references the issue (proxy for "active work in
# progress"). The "#<num> in:body" search narrows matches to PRs that mention
# the issue in their body, reducing false positives from a bare numeric match.
function _triage_has_active_pr {
    param([string]$Repo, [string]$Num)
    $out = ((_triage_gh pr list --repo $Repo --state open --search "#$Num in:body" --json number 2>$null) | Out-String).Trim()
    if ([string]::IsNullOrEmpty($out) -or $out -eq '[]') { return $false }
    return $true
}

# Resolve whether an issue is currently blocked. Returns a PSCustomObject with
# OpenFound ('true'/'false') and Action (the normalized "#N:STATE" list, all
# blockers, numerically sorted, trailing-space trimmed). Action is the
# fingerprint input, so it MUST enumerate every blocker (not collapse to the
# first): a later blocker's state change must still move the digest (AC4/AC4b).
function _triage_block_state {
    param([string]$Repo, [string]$Json)
    $body = _triage_field $Json 'body'
    $blockers = triage_extract_blockers $body
    $openFound = 'false'
    $pairs = ''
    foreach ($b in $blockers) {
        $bstate = ((_triage_gh issue view $b --repo $Repo --json state --jq '.state' 2>$null) | Out-String).Trim()
        if ([string]::IsNullOrEmpty($bstate)) { $bstate = 'UNKNOWN' }
        $pairs = "$pairs#${b}:$bstate "
        if ($bstate -eq 'OPEN') { $openFound = 'true' }
    }
    return [PSCustomObject]@{ OpenFound = $openFound; Action = $pairs.TrimEnd() }
}

# ── Mutations ────────────────────────────────────────────────────────

# Post a comment body unless the same-kind fingerprint marker already matches.
# Returns $true if posted (or would post under a real run), $false if skipped as
# unchanged. Honors the TRIAGE_DRY_RUN seam.
function _triage_post_idempotent_comment {
    param([string]$Repo, [string]$Num, [string]$Kind, [string]$Fingerprint, [string]$Body)
    $raw = _triage_comments_raw $Repo $Num
    if (triage_comment_marker_matches $raw $Kind $Fingerprint) {
        return $false
    }
    if ($env:TRIAGE_DRY_RUN -eq 'true') {
        return $true
    }
    $tmp = New-TemporaryFile
    try {
        $content = "$Body`n`n<!-- triage-fingerprint: ${Kind}:${Fingerprint} -->`n"
        Set-Content -LiteralPath $tmp.FullName -Value $content -NoNewline
        _triage_gh issue comment $Num --repo $Repo --body-file $tmp.FullName 2>$null | Out-Null
    } finally {
        Remove-Item -LiteralPath $tmp.FullName -ErrorAction SilentlyContinue
    }
    return $true
}

# ── Emit outcome JSON ─────────────────────────────────────────────────
# Writes exactly one JSON object as the final stdout line. Field order is
# identical to triage.sh: outcome, requested, root, active, visited, reason,
# fingerprint. `visited` is a JSON array of issue-number strings and is inserted
# raw (placeholder {4} is unquoted). Callers set the exit code themselves
# (`failed` -> nonzero, everything else -> zero), mirroring triage.sh's
# `_triage_emit ...; return $?` chaining.
function _triage_emit {
    param(
        [string]$Outcome,
        [string]$Reason,
        [AllowEmptyString()][string]$Active = '',
        [AllowEmptyString()][string]$Fingerprint = ''
    )
    $visitedJson = '[]'
    if (-not [string]::IsNullOrWhiteSpace($script:Visited)) {
        $nums = @($script:Visited -split '\s+' | Where-Object { $_ -ne '' })
        if ($nums.Count -gt 0) {
            $visitedJson = '[' + (($nums | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']'
        }
    }
    Write-Output ('{{"outcome":"{0}","requested":"{1}","root":"{2}","active":"{3}","visited":{4},"reason":"{5}","fingerprint":"{6}"}}' `
        -f $Outcome, $script:Requested, $script:Root, $Active, $visitedJson, $Reason, $Fingerprint)
}

# ── State machine driver ─────────────────────────────────────────────
# run_triage -Repo <owner/name> [-Issue <n>] [-PlanFile <path>]
# Returns 0 for every terminal outcome except `failed`, which returns 1
# (mirroring triage.sh's return-status chaining). The outcome JSON is emitted by
# _triage_emit; the integer return is the process exit code.
function run_triage {
    param([string]$Repo, [AllowEmptyString()][string]$Issue = '', [AllowEmptyString()][string]$PlanFile = '')
    $script:Requested = $Issue
    $script:Root = ''
    $script:Visited = ''
    $depth = 0

    # RESOLVE_REQUESTED: pick the root issue.
    if ([string]::IsNullOrEmpty($Issue)) {
        $Issue = ((_triage_gh issue list --repo $Repo --state open --limit 1 --json number --jq '.[0].number' 2>$null) | Out-String).Trim()
        if ([string]::IsNullOrEmpty($Issue)) {
            _triage_emit skipped 'no open issue to select'
            return 0
        }
    }
    $script:Root = $Issue
    $active = $Issue
    $user = _triage_current_user

    while ($true) {
        if ($depth -gt $script:MaxChildDepth) {
            _triage_emit failed "child traversal exceeded MAX_CHILD_DEPTH=$($script:MaxChildDepth)"
            return 1
        }

        # REFRESH: re-fetch the active issue, retrying up to TRIAGE_MAX_FAILURES
        # times. Three identical failures in a row stop the run with a blocked
        # outcome rather than a blind retry (#829 Risks).
        $json = _triage_issue_json_retry $Repo $active
        if ($null -eq $json) {
            $max = if ($env:TRIAGE_MAX_FAILURES) { [int]$env:TRIAGE_MAX_FAILURES } else { 3 }
            _triage_emit blocked "stopped after $max identical failures fetching #$active" '' ''
            return 0
        }
        $state = _triage_field $json 'state'
        if ($state -ne 'OPEN') {
            $script:Visited = "$script:Visited $active"
            _triage_emit skipped "issue #$active is $state"
            return 0
        }

        # EVALUATE_BLOCKERS: recompute + idempotent blocked comment.
        $blockOut = _triage_block_state $Repo $json
        $openBlocker = $blockOut.OpenFound
        $action = $blockOut.Action
        if ($openBlocker -eq 'true') {
            $fp = $action | triage_hash
            _triage_post_idempotent_comment $Repo $active blocked $fp `
                "Blocked: #$active has an unresolved dependency. Blocker states: $action" | Out-Null
            $script:Visited = "$script:Visited $active"
            _triage_emit blocked "unresolved blocker on #$active" '' $fp
            return 0
        }

        # DECOMPOSE (explicit): a plan file means the caller is asking to
        # decompose this invocation. Reconcile existing-vs-planned children,
        # create only the missing ones, post one summary. This takes priority
        # over child selection so a partial decomposition can be completed on a
        # rerun (AC6) rather than immediately diving into an existing child.
        if (-not [string]::IsNullOrEmpty($PlanFile) -and (Test-Path -LiteralPath $PlanFile -PathType Leaf)) {
            if (_triage_create_children $Repo $active $PlanFile) {
                $script:Visited = "$script:Visited $active"
                _triage_emit decomposed "reconciled children for #$active" ''
                return 0
            }
            _triage_emit failed "plan file supplied but contained no child titles for #$active"
            return 1
        }

        # EVALUATE_SIZE (no plan): work directly, select a child, or audit.
        if (-not (_triage_needs_decompose $json)) {
            # CLAIM
            if (_triage_claim $Repo $active $user) {
                $script:Visited = "$script:Visited $active"
                _triage_emit proceed "eligible issue #$active claimed" $active
                return 0
            }
            # Claim lost: fall through to sibling selection below.
            $script:Visited = "$script:Visited $active"
        } else {
            # Oversized with no plan: prefer an existing eligible open child.
            $child = _triage_select_child $Repo $active $user
            if (-not [string]::IsNullOrEmpty($child)) {
                $script:Visited = "$script:Visited $active"
                $active = $child
                $depth++
                continue
            }
            # No eligible open child. Distinguish "all children closed"
            # (completion audit, AC8) from other terminal cases.
            $stats = _triage_children_stats $Repo $active
            $parts = @($stats -split '\s+' | Where-Object { $_ -ne '' })
            $total = if ($parts.Count -ge 1) { [int]$parts[0] } else { 0 }
            $openCount = if ($parts.Count -ge 2) { [int]$parts[1] } else { 0 }
            if ($total -gt 0 -and $openCount -eq 0) {
                $script:Visited = "$script:Visited $active"
                _triage_emit skipped "all children of #$active are closed; run completion audit"
                return 0
            }
            if ($total -gt 0) {
                $script:Visited = "$script:Visited $active"
                _triage_emit skipped "children of #$active exist but none are eligible"
                return 0
            }
            # Oversized, no children, and no plan to create them with. Reason is
            # prefixed "needs_plan" so callers/batch can distinguish this
            # re-invoke signal from a genuine build/CI failure.
            $script:Visited = "$script:Visited $active"
            _triage_emit failed "needs_plan: issue #$active needs decomposition; re-invoke with --plan-file"
            return 1
        }

        # Claim was lost: try the next eligible sibling of ROOT.
        $next = _triage_select_child $Repo $script:Root $user
        if (-not [string]::IsNullOrEmpty($next)) {
            $active = $next
            $depth++
            continue
        }
        _triage_emit skipped 'claim race lost and no remaining eligible child'
        return 0
    }
}

# Decide whether an issue must be decomposed. Large by label, or large by body
# with 4+ acceptance-criteria checkboxes.
function _triage_needs_decompose {
    param([string]$Json)
    $labels = _triage_field $Json 'labels'
    $set = ",$labels,"
    if ($set -like '*,size/L,*' -or $set -like '*,size/XL,*') { return $true }
    $body = _triage_field $Json 'body'
    $acCount = 0
    foreach ($line in ($body -split "`n")) {
        if ($line -match '^\s*- \[[ xX]\]') { $acCount++ }
    }
    if ($body.Length -gt 1500 -and $acCount -ge 4) { return $true }
    return $false
}

# Return "<total> <open>" counts of a parent's children (any state). Replaces
# triage.sh's embedded python3 with native ConvertFrom-Json.
function _triage_children_stats {
    param([string]$Repo, [string]$Parent)
    $list = ((_triage_gh issue list --repo $Repo --state all --search "Part of #$Parent in:body" --json 'number,state' 2>$null) | Out-String).Trim()
    if ([string]::IsNullOrEmpty($list)) { return '0 0' }
    $items = $null
    try {
        $items = $list | ConvertFrom-Json
    } catch {
        return '0 0'
    }
    if ($null -eq $items) { return '0 0' }
    $arr = @($items)
    $total = $arr.Count
    $opened = @($arr | Where-Object { (_triage_prop $_ 'state') -eq 'OPEN' }).Count
    return "$total $opened"
}

# List children of a parent (issues whose body references "Part of #<parent>"),
# filter to eligible ones, sort by the deterministic key, and return the first.
# Replaces triage.sh's embedded python3 with native ConvertFrom-Json and a
# Sort-Object that replicates the python sort tuple EXACTLY:
#   (mine=0-if-user-in-assignees-else-1, idx=original-list-index,
#    prio=min(label ranks, else 4), createdAt string, int(number), number-string)
function _triage_select_child {
    param([string]$Repo, [string]$Parent, [string]$User)
    $list = ((_triage_gh issue list --repo $Repo --state all --search "Part of #$Parent in:body" --json 'number,title,state,labels,assignees,createdAt' 2>$null) | Out-String).Trim()
    if ([string]::IsNullOrEmpty($list)) { return '' }
    $items = $null
    try {
        $items = $list | ConvertFrom-Json
    } catch {
        return ''
    }
    if ($null -eq $items) { return '' }
    $items = @($items)

    $visitedSet = @{}
    foreach ($v in ($script:Visited -split '\s+')) {
        if ($v -ne '') { $visitedSet[$v] = $true }
    }

    $rank = @{ 'priority/critical' = 0; 'priority/high' = 1; 'priority/medium' = 2; 'priority/low' = 3 }
    $cands = @()
    for ($idx = 0; $idx -lt $items.Count; $idx++) {
        $it = $items[$idx]
        $num = [string](_triage_prop $it 'number')
        if ((_triage_prop $it 'state') -ne 'OPEN') { continue }
        if ($visitedSet.ContainsKey($num)) { continue }

        $assignees = @()
        $aProp = $it.PSObject.Properties['assignees']
        if ($aProp -and $null -ne $aProp.Value) {
            foreach ($a in @($aProp.Value)) { $assignees += (_triage_prop $a 'login') }
        }
        # Assigned only to others (current user not among assignees) -> skip. The
        # membership test is case-sensitive to match python's `user in assignees`.
        if ($assignees.Count -gt 0 -and ($assignees -cnotcontains $User)) { continue }

        $prio = 4
        $lProp = $it.PSObject.Properties['labels']
        if ($lProp -and $null -ne $lProp.Value) {
            foreach ($l in @($lProp.Value)) {
                $lname = _triage_prop $l 'name'
                if ($rank.ContainsKey($lname) -and $rank[$lname] -lt $prio) { $prio = $rank[$lname] }
            }
        }
        $mine = if ($assignees -ccontains $User) { 0 } else { 1 }
        $numInt = 0
        [void][int]::TryParse($num, [ref]$numInt)
        $cands += [PSCustomObject]@{
            Mine      = $mine
            Idx       = $idx
            Prio      = $prio
            CreatedAt = [string](_triage_prop $it 'createdAt')
            NumInt    = $numInt
            NumStr    = $num
        }
    }
    if ($cands.Count -eq 0) { return '' }
    $sorted = @($cands | Sort-Object -Property Mine, Idx, Prio, CreatedAt, NumInt, NumStr)
    return $sorted[0].NumStr
}

# Re-read the issue after a claim mutation and decide whether the claim holds.
# Returns $false if we lost (closed, reassigned away, or a linked PR appeared).
function _triage_claim_verify {
    param([string]$Repo, [string]$Num, [string]$User)
    $json = _triage_issue_json $Repo $Num
    if ([string]::IsNullOrEmpty($json)) { return $false }
    $state = _triage_field $json 'state'
    if ($state -ne 'OPEN') { return $false }
    $assignees = _triage_field $json 'assignees'
    if (-not [string]::IsNullOrEmpty($assignees)) {
        # We are (among) the assignees -> won; assigned only to others -> lost.
        # Case-sensitive to match triage.sh's literal `case ",$assignees,"` test.
        if (",$assignees," -cnotlike "*,$User,*") { return $false }
    }
    if (_triage_has_active_pr $Repo $Num) { return $false }
    return $true
}

# Assign the issue to the current user, then re-verify no one else won the race.
# On a lost race, roll back our speculative @me assignment so the abandoned issue
# is not left showing us as an assignee.
function _triage_claim {
    param([string]$Repo, [string]$Num, [string]$User)
    if ($env:TRIAGE_DRY_RUN -ne 'true') {
        _triage_gh issue edit $Num --repo $Repo --add-assignee '@me' 2>$null | Out-Null
    }
    if (_triage_claim_verify $Repo $Num $User) {
        return $true
    }
    if ($env:TRIAGE_DRY_RUN -ne 'true') {
        _triage_gh issue edit $Num --repo $Repo --remove-assignee '@me' 2>$null | Out-Null
    }
    return $false
}

# Reconcile and create children from a plan file (one child title per line).
# Idempotent: creates only titles that do not already exist; posts one parent
# summary guarded by a decompose fingerprint. Returns $false if no usable plan.
function _triage_create_children {
    param([string]$Repo, [string]$Parent, [string]$PlanFile)
    if ([string]::IsNullOrEmpty($PlanFile) -or -not (Test-Path -LiteralPath $PlanFile -PathType Leaf)) { return $false }

    $existingRaw = (_triage_gh issue list --repo $Repo --state all --search "Part of #$Parent in:body" --json title --jq '.[].title' 2>$null) | Out-String
    $existing = @($existingRaw -split "`r?`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -ne '' })

    $planned = 0
    $created = 0
    foreach ($title in (Get-Content -LiteralPath $PlanFile)) {
        if ([string]::IsNullOrEmpty($title)) { continue }
        $planned++
        # Full-line, case-sensitive existence test (mirrors `grep -Fxq`).
        if ($existing -ccontains $title) { continue }
        if ($env:TRIAGE_DRY_RUN -ne 'true') {
            $tmp = New-TemporaryFile
            try {
                Set-Content -LiteralPath $tmp.FullName -Value "Part of #$Parent"
                _triage_gh issue create --repo $Repo --title $title --body-file $tmp.FullName 2>$null | Out-Null
            } finally {
                Remove-Item -LiteralPath $tmp.FullName -ErrorAction SilentlyContinue
            }
        }
        $created++
    }

    if ($planned -le 0) { return $false }

    # Post the parent summary once (idempotent via decompose fingerprint).
    $fp = "decompose:${Parent}:${planned}" | triage_hash
    _triage_post_idempotent_comment $Repo $Parent decompose $fp `
        "Decomposed into $planned child issue(s); $created created this run." | Out-Null
    return $true
}

# ── CLI entry ────────────────────────────────────────────────────────

# Split a driver result into "emit on stdout" and "use as the exit code".
#
# run_triage writes its JSON to the success stream and then `return`s an int
# exit code -- but in PowerShell a `return` value also lands on the success
# stream, so the caller receives @(<json>, <int>) as one array. Passing that
# array straight to `exit` casts the whole array to int, which throws and takes
# the JSON down with it, so `pwsh -File triage.ps1 ...` printed nothing at all
# while triage.sh printed the triage JSON (issue #847 S2).
#
# This helper writes every non-int item straight to the console and returns the
# trailing int as the exit code, restoring parity with the bash CLI.
# Dot-sourced callers are unaffected -- they consume the driver's return value
# directly.
#
# The payload goes out via [Console]::Out rather than Write-Output on purpose:
# Write-Output would put it back on the success stream alongside the returned
# exit code, reproducing the very merge this helper exists to undo.
function Split-TriageCliResult {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Result)
    $items = @($Result)
    $code = 0
    if ($items.Count -gt 0 -and $items[-1] -is [int]) {
        $code = [int]$items[-1]
        # Note the explicit Count check: $items[0..($items.Count - 2)] would be
        # $items[0..-1] for a single-element array, and PowerShell reads -1 as
        # "last element", silently re-emitting the exit code as output.
        if ($items.Count -gt 1) {
            $items = $items[0..($items.Count - 2)]
        } else {
            $items = @()
        }
    }
    foreach ($item in $items) { [Console]::Out.WriteLine([string]$item) }
    return $code
}

function Invoke-TriageMain {
    param([string[]]$Arguments = @())
    $repo = ''; $issue = ''; $planFile = ''
    $i = 0
    while ($i -lt $Arguments.Count) {
        switch ($Arguments[$i]) {
            '--repo' { $repo = $Arguments[$i + 1]; $i += 2 }
            '--issue' { $issue = $Arguments[$i + 1]; $i += 2 }
            '--plan-file' { $planFile = $Arguments[$i + 1]; $i += 2 }
            '--max-depth' { $script:MaxChildDepth = [int]$Arguments[$i + 1]; $i += 2 }
            '--dry-run' { $env:TRIAGE_DRY_RUN = 'true'; $i += 1 }
            default {
                Write-Error "unknown argument: $($Arguments[$i])"
                return 2
            }
        }
    }
    if (-not $repo) {
        Write-Error 'error: --repo <owner/name> is required'
        return 2
    }
    return run_triage -Repo $repo -Issue $issue -PlanFile $planFile
}

# Run as CLI only when executed directly; stay quiet when dot-sourced by tests
# (mirrors triage.sh's BASH_SOURCE guard).
if ($MyInvocation.InvocationName -ne '.') {
    exit (Split-TriageCliResult (Invoke-TriageMain -Arguments $args))
}
