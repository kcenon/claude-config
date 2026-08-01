# Test suite for global/skills/_internal/issue-work/scripts/triage.ps1
# Run: pwsh -NoProfile -File tests/issue-work/test-triage.ps1
#
# PowerShell parity suite for tests/issue-work/test-triage.sh: the same unit
# tests over the pure functions (dot-sourced) and the same end-to-end scenarios
# driven through the CLI, against the fake gh (fake-gh.ps1). Every issue #829
# acceptance criterion and the verification matrix are covered.
#
# AC -> test mapping (see reference/triage-state-machine.md):
#   AC1  oversized + no children + plan          -> creates children + 1 summary, decomposed
#   AC2  oversized parent + eligible open child  -> selects child, no decompose comment, proceed
#   AC3  documented unchanged blocker            -> no additional comment on rerun
#   AC4  changed blocker                         -> exactly one updated comment
#   AC4b later blocker flips, first unchanged    -> exactly one updated comment (M1 regression)
#   AC5  new human info before blocked decision  -> re-evaluated, flips blocked->proceed
#   AC6  partial child creation                  -> rerun creates only the missing child
#   AC7  claim race                              -> advances to the next eligible child
#   AC8  only-closed children                    -> completion audit (skipped), not a closed pick
#   AC9  blocked/decomposed do no repo work      -> no assign/create on blocked, terminal outcomes
#   VER  cyclic relationships                    -> visited guard terminates the traversal
#   VER  max depth                               -> depth guard yields failed, not an infinite loop
#   VER  three identical fetch failures          -> retry helper stops with a blocked outcome
#   VER  batch reporting                         -> decomposition is not a merge success (doc guard)
#
# Two further cases cover defects that exist only in the PowerShell port and so
# have no counterpart in the bash suite (issue #847):
#   S1   a native gh exiting non-zero must not throw when the host has enabled
#        $PSNativeCommandUseErrorActionPreference
#   S2   `pwsh -File triage.ps1` must print the outcome JSON on stdout
#
# Note on S1: fake-gh.ps1 cannot exercise that path. pwsh runs a .ps1 GH_BIN
# in-process, and $PSNativeCommandUseErrorActionPreference only governs *native*
# child processes, so the fake never trips it however the preference is set. The
# case therefore builds a small native shim (New-NativeGhShim) that wraps the
# fake in a real child process and exits non-zero on an empty read, the way real
# gh exits non-zero for `issue view` on a missing issue. Without that shim the
# assertion would pass even with the fix reverted.
#
# What S1 does and does not pin down, measured against mutated copies of
# triage.ps1: the native-exit tolerance rests on two deliberately redundant
# guards -- the script-scope `$PSNativeCommandUseErrorActionPreference = $false`
# and the `$ErrorActionPreference = 'Continue'` that _triage_gh sets locally.
# Removing either one alone still yields the blocked outcome, so S1 does not
# detect a single-guard regression; removing both makes the run throw
# NativeCommandExitException and S1 fails. S1 therefore asserts the observable
# contract (a non-zero native gh is data, not an error) rather than the presence
# of one particular line -- which is exactly what triage.ps1's own comment says
# the redundancy is there to provide.

$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Triage = Join-Path $RootDir 'global/skills/_internal/issue-work/scripts/triage.ps1'
$FakeGh = Join-Path $RootDir 'tests/issue-work/fake-gh.ps1'
$BatchModeDoc = Join-Path $RootDir 'global/skills/_internal/issue-work/reference/batch-mode.md'
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("triage-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null

$Pass = 0
$Fail = 0
$Errors = @()

# Raw stdout / exit code of the most recent CLI invocation, for the cases that
# assert on the transport itself rather than on a parsed field.
$script:LastCliRaw = @()
$script:LastCliExit = 0

# ── Assertions ───────────────────────────────────────────────────────

function Add-Pass {
    param([string]$Label)
    $script:Pass++
    Write-Host "  PASS: $Label"
}

function Add-Fail {
    param([string]$Label)
    $script:Fail++
    $script:Errors += "FAIL: $Label"
    Write-Host "  FAIL: $Label"
}

function Assert-Eq {
    param([string]$Expected, [string]$Actual, [string]$Label)
    if ($Expected -eq $Actual) { Add-Pass $Label }
    else { Add-Fail "$Label -- expected '$Expected', got '$Actual'" }
}

function Assert-Contains {
    param([string]$Needle, [string]$Haystack, [string]$Label)
    if ($Haystack.Contains($Needle)) { Add-Pass $Label }
    else { Add-Fail "$Label -- '$Needle' not in output" }
}

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if ($Condition) { Add-Pass $Label } else { Add-Fail $Label }
}

function Assert-False {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) { Add-Pass $Label } else { Add-Fail $Label }
}

# ── Fixture helpers ──────────────────────────────────────────────────

function Set-FixtureFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# Fresh fixture directory for one scenario.
function New-Fixture {
    $d = Join-Path $script:Work ('fix-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $d | Out-Null
    Set-FixtureFile (Join-Path $d 'user') 'me'
    Set-FixtureFile (Join-Path $d 'mutations.log') ''
    return $d
}

# issue JSON with the same field order and placeholder createdAt as the bash
# suite's issue_json helper.
function New-IssueJson {
    param([string]$Number, [string]$State, [string]$Labels, [string]$Assignees, [string]$Body)
    return ('{{"number":{0},"title":"issue {0}","state":"{1}","body":"{2}","labels":{3},"assignees":{4},"createdAt":"2026-01-01T00:00:00Z"}}' `
        -f $Number, $State, $Body, $Labels, $Assignees)
}

function Set-IssueFixture {
    param([string]$Fixture, [string]$Number, [string]$State, [string]$Labels, [string]$Assignees, [string]$Body)
    Set-FixtureFile (Join-Path $Fixture "issue-$Number.json") (New-IssueJson $Number $State $Labels $Assignees $Body)
}

# StrictMode-safe field read off the outcome JSON (the bash suite's jfield).
function Get-JsonField {
    param([AllowEmptyString()][string]$Json, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Json)) { return '' }
    $obj = $null
    try { $obj = $Json | ConvertFrom-Json } catch { return '' }
    if ($null -eq $obj) { return '' }
    $p = $obj.PSObject.Properties[$Field]
    if ($null -eq $p -or $null -eq $p.Value) { return '' }
    return [string]$p.Value
}

# Count mutation-log lines for one verb (the bash suite's count_log).
function Get-LogCount {
    param([string]$Fixture, [string]$Verb)
    $log = Join-Path $Fixture 'mutations.log'
    if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { return 0 }
    $lines = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue |
        Where-Object { $_ -clike "$Verb *" })
    return $lines.Count
}

function Get-LogText {
    param([string]$Fixture)
    $log = Join-Path $Fixture 'mutations.log'
    if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { return '' }
    $raw = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
    if ($null -eq $raw) { return '' }
    return $raw
}

# Run the triage CLI against a fixture; return the final JSON line. Mirrors the
# bash suite's run(): the CLI is the entry point under test, and only the last
# line that starts with '{' is the outcome.
function Invoke-TriageCli {
    param([string]$Fixture, [string[]]$ExtraArgs = @(), [string]$GhBin = '')
    $env:GH_BIN = if ([string]::IsNullOrEmpty($GhBin)) { $script:FakeGh } else { $GhBin }
    $env:FAKE_GH_DIR = $Fixture
    $env:TRIAGE_CURRENT_USER = 'me'
    $pwshArgs = @('-NoProfile', '-File', $script:Triage, '--repo', 'test/repo') + $ExtraArgs
    $raw = & pwsh @pwshArgs 2>$null
    $script:LastCliExit = $LASTEXITCODE
    $script:LastCliRaw = @(@($raw) | ForEach-Object { [string]$_ })
    $json = @($script:LastCliRaw | Where-Object { $_ -match '^\{' })
    if ($json.Count -eq 0) { return '' }
    return $json[-1]
}

# S1 seam: run the CLI in a host that has enabled
# $PSNativeCommandUseErrorActionPreference, which is a preference variable and
# so cannot be injected through the environment like the other seams.
function Invoke-TriageCliWithNativePref {
    param([string]$Fixture, [string]$IssueNumber, [string]$GhBin)
    $env:GH_BIN = $GhBin
    $env:FAKE_GH_DIR = $Fixture
    $env:TRIAGE_CURRENT_USER = 'me'
    $command = '$PSNativeCommandUseErrorActionPreference = $true; ' +
               '$ErrorActionPreference = ''Stop''; ' +
               "& '$script:Triage' --repo test/repo --issue $IssueNumber"
    $raw = & pwsh -NoProfile -Command $command 2>$null
    $script:LastCliExit = $LASTEXITCODE
    $script:LastCliRaw = @(@($raw) | ForEach-Object { [string]$_ })
    $json = @($script:LastCliRaw | Where-Object { $_ -match '^\{' })
    if ($json.Count -eq 0) { return '' }
    return $json[-1]
}

# Build a *native* gh double for the S1 case. See the S1 note in the header for
# why fake-gh.ps1 cannot stand in here: it wraps the fake in a real child
# process and exits non-zero on an empty read, mirroring real gh on a missing
# issue. The behavior lives in one .ps1 that both platform stubs delegate to.
function New-NativeGhShim {
    $impl = Join-Path $script:Work 'gh-native-impl.ps1'
    $body = @'
$out = & '__FAKE_GH__' @args
if ($null -ne $out) { @($out) | ForEach-Object { [Console]::Out.WriteLine([string]$_) } }
if (-not $out) { exit 1 }
exit 0
'@
    Set-FixtureFile $impl ($body.Replace('__FAKE_GH__', $script:FakeGh))

    if ($IsWindows) {
        $shim = Join-Path $script:Work 'gh-native.cmd'
        Set-FixtureFile $shim "@pwsh -NoProfile -File `"$impl`" %*`r`n"
    } else {
        $shim = Join-Path $script:Work 'gh-native'
        Set-FixtureFile $shim "#!/usr/bin/env bash`nexec pwsh -NoProfile -File '$impl' `"`$@`"`n"
        & chmod +x $shim
    }
    return $shim
}

try {
    Write-Host '=== triage.ps1 unit tests (pure functions) ==='
    # Dot-sourcing exposes the pure functions without running the CLI (the
    # InvocationName guard at the bottom of triage.ps1 stays quiet). It also
    # imports Set-StrictMode -Version Latest into this scope, so everything
    # below is written strict-clean.
    . $Triage

    # triage_hash: deterministic and input-sensitive.
    $h1 = 'abc' | triage_hash
    $h2 = 'abc' | triage_hash
    $h3 = 'abd' | triage_hash
    Assert-Eq $h1 $h2 'triage_hash is deterministic'
    Assert-True ($h1 -ne $h3) 'triage_hash differs on different input'

    # triage_extract_blockers.
    $blk = @(triage_extract_blockers 'text Blocked by #12 and Depends on #7 more')
    Assert-Eq '7,12' ($blk -join ',') 'triage_extract_blockers finds both refs, sorted'
    Assert-Eq '' ((@(triage_extract_blockers 'no refs here')) -join ',') 'triage_extract_blockers empty when none'

    # triage_priority_rank.
    Assert-Eq '0' ([string](triage_priority_rank 'priority/critical,type/bug')) 'rank critical=0'
    Assert-Eq '2' ([string](triage_priority_rank 'priority/medium')) 'rank medium=2'
    Assert-Eq '4' ([string](triage_priority_rank 'type/bug')) 'rank unlabeled=4'

    # triage_is_eligible truth table.
    Assert-True  (triage_is_eligible 'OPEN' 'false' 'false' 'false' 'false') 'eligible when all clear'
    Assert-False (triage_is_eligible 'CLOSED' 'false' 'false' 'false' 'false') 'closed is ineligible'
    Assert-False (triage_is_eligible 'OPEN' 'true' 'false' 'false' 'false') 'blocked is ineligible'
    Assert-False (triage_is_eligible 'OPEN' 'false' 'true' 'false' 'false') 'assigned-other is ineligible'
    Assert-False (triage_is_eligible 'OPEN' 'false' 'false' 'true' 'false') 'active-PR is ineligible'
    Assert-False (triage_is_eligible 'OPEN' 'false' 'false' 'false' 'true') 'visited is ineligible'

    # triage_comment_marker matchers.
    $raw = 'body text <!-- triage-fingerprint: blocked:abc123 --> tail'
    Assert-True  (triage_comment_marker_matches $raw 'blocked' 'abc123') 'marker matches equal fingerprint'
    Assert-False (triage_comment_marker_matches $raw 'blocked' 'zzz999') 'marker rejects differing fingerprint'
    Assert-True  (triage_comment_marker_present $raw 'blocked') 'marker presence detected'
    Assert-False (triage_comment_marker_present $raw 'decompose') 'absent marker kind reported absent'

    Write-Host ''
    Write-Host '=== AC1: oversized + no children + plan -> decomposed (create + 1 summary) ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 1 OPEN '[{"name":"size/XL"}]' '[]' 'Big epic'
    Set-FixtureFile (Join-Path $fix 'children-1.json') '[]'
    Set-FixtureFile (Join-Path $fix 'plan.txt') "child alpha`nchild beta`n"
    $out = Invoke-TriageCli $fix @('--issue', '1', '--plan-file', (Join-Path $fix 'plan.txt'))
    Assert-Eq 'decomposed' (Get-JsonField $out 'outcome') 'AC1 outcome=decomposed'
    Assert-Eq '2' ([string](Get-LogCount $fix 'CREATE')) 'AC1 created 2 children'
    Assert-Eq '1' ([string](Get-LogCount $fix 'COMMENT')) 'AC1 posted exactly one parent summary'
    Assert-Eq '0' ([string](Get-LogCount $fix 'ASSIGN')) 'AC1 made no assignment (no code work)'

    Write-Host ''
    Write-Host '=== AC2: oversized parent + eligible open child -> proceed on child ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 10 OPEN '[{"name":"size/XL"}]' '[]' 'Parent epic'
    Set-IssueFixture $fix 11 OPEN '[{"name":"size/S"}]' '[]' 'Child work'
    Set-FixtureFile (Join-Path $fix 'children-10.json') '[{"number":11,"title":"Child work","state":"OPEN","labels":[{"name":"size/S"}],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"}]'
    $out = Invoke-TriageCli $fix @('--issue', '10')
    Assert-Eq 'proceed' (Get-JsonField $out 'outcome') 'AC2 outcome=proceed'
    Assert-Eq '11' (Get-JsonField $out 'active') 'AC2 active=child #11'
    Assert-Eq '0' ([string](Get-LogCount $fix 'CREATE')) 'AC2 created no children'
    Assert-Eq '0' ([string](Get-LogCount $fix 'COMMENT')) 'AC2 posted no decomposition comment'

    Write-Host ''
    Write-Host '=== AC3: documented unchanged blocker -> no extra comment on rerun ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 20 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #21'
    Set-IssueFixture $fix 21 OPEN '[]' '[]' 'dependency'
    $out = Invoke-TriageCli $fix @('--issue', '20')
    Assert-Eq 'blocked' (Get-JsonField $out 'outcome') 'AC3 first run outcome=blocked'
    Assert-Eq '1' ([string](Get-LogCount $fix 'COMMENT')) 'AC3 first run posts one blocked comment'
    $out2 = Invoke-TriageCli $fix @('--issue', '20')   # rerun, blocker unchanged, marker present
    Assert-Eq 'blocked' (Get-JsonField $out2 'outcome') 'AC3 rerun still blocked'
    Assert-Eq '1' ([string](Get-LogCount $fix 'COMMENT')) 'AC3 rerun posts no additional comment'

    Write-Host ''
    Write-Host '=== AC4: changed blocker -> exactly one updated comment ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 30 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #21'
    Set-IssueFixture $fix 21 OPEN '[]' '[]' 'dep one'
    Invoke-TriageCli $fix @('--issue', '30') | Out-Null           # run1: posts comment fp1
    Assert-Eq '1' ([string](Get-LogCount $fix 'COMMENT')) 'AC4 first run posts one comment'
    Set-IssueFixture $fix 30 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #21 Depends on #22'
    Set-IssueFixture $fix 22 OPEN '[]' '[]' 'dep two'
    $out = Invoke-TriageCli $fix @('--issue', '30')               # run2: blocker set changed -> fp2
    Assert-Eq 'blocked' (Get-JsonField $out 'outcome') 'AC4 rerun outcome=blocked'
    Assert-Eq '2' ([string](Get-LogCount $fix 'COMMENT')) 'AC4 changed blocker adds exactly one comment'

    Write-Host ''
    Write-Host '=== AC4b (M1 regression): later blocker flips while first stays -> one update ==='
    # Guards the fingerprint against the block-state leak bug: with the first
    # blocker unchanged, a *later* blocker's state change must still alter the
    # fingerprint and post exactly one updated comment.
    $fix = New-Fixture
    Set-IssueFixture $fix 35 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #36 Depends on #37'
    Set-IssueFixture $fix 36 OPEN '[]' '[]' 'first dep'
    Set-IssueFixture $fix 37 OPEN '[]' '[]' 'second dep'
    Invoke-TriageCli $fix @('--issue', '35') | Out-Null            # run1: #36 OPEN, #37 OPEN
    Assert-Eq '1' ([string](Get-LogCount $fix 'COMMENT')) 'AC4b first run posts one comment'
    Set-IssueFixture $fix 37 CLOSED '[]' '[]' 'second dep resolved'   # later blocker flips
    $out = Invoke-TriageCli $fix @('--issue', '35')                # run2: #36 OPEN, #37 CLOSED
    Assert-Eq 'blocked' (Get-JsonField $out 'outcome') 'AC4b still blocked by the first dependency'
    Assert-Eq '2' ([string](Get-LogCount $fix 'COMMENT')) 'AC4b later-blocker flip posts exactly one update'

    Write-Host ''
    Write-Host '=== AC5: new human info evaluated before keeping blocked -> flips to proceed ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 40 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #41'
    Set-IssueFixture $fix 41 OPEN '[]' '[]' 'dependency'
    $out = Invoke-TriageCli $fix @('--issue', '40')
    Assert-Eq 'blocked' (Get-JsonField $out 'outcome') 'AC5 initially blocked'
    Set-IssueFixture $fix 41 CLOSED '[]' '[]' 'dependency resolved'   # human resolves blocker
    $out2 = Invoke-TriageCli $fix @('--issue', '40')
    Assert-Eq 'proceed' (Get-JsonField $out2 'outcome') 'AC5 fresh blocker state flips to proceed'
    Assert-Eq '40' (Get-JsonField $out2 'active') 'AC5 proceeds on the unblocked issue'

    Write-Host ''
    Write-Host '=== AC6: partial child creation -> rerun creates only the missing child ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 50 OPEN '[{"name":"size/XL"}]' '[]' 'Epic'
    Set-FixtureFile (Join-Path $fix 'children-50.json') '[{"number":51,"title":"child alpha","state":"OPEN","labels":[],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"}]'
    Set-FixtureFile (Join-Path $fix 'plan.txt') "child alpha`nchild beta`n"
    $out = Invoke-TriageCli $fix @('--issue', '50', '--plan-file', (Join-Path $fix 'plan.txt'))
    Assert-Eq 'decomposed' (Get-JsonField $out 'outcome') 'AC6 outcome=decomposed'
    Assert-Eq '1' ([string](Get-LogCount $fix 'CREATE')) 'AC6 creates only the missing child'
    Assert-Contains 'child beta' (Get-LogText $fix) 'AC6 creates the beta child specifically'

    Write-Host ''
    Write-Host '=== AC7: claim race -> advance to the next eligible child ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 60 OPEN '[{"name":"size/XL"}]' '[]' 'Parent'
    Set-IssueFixture $fix 61 OPEN '[{"name":"size/S"}]' '[]' 'first child'
    # Post-claim swap: #61 turns out assigned to someone else (race lost).
    Set-FixtureFile (Join-Path $fix 'issue-61.postclaim.json') (New-IssueJson 61 OPEN '[{"name":"size/S"}]' '[{"login":"other"}]' 'first child')
    Set-IssueFixture $fix 62 OPEN '[{"name":"size/S"}]' '[]' 'second child'
    Set-FixtureFile (Join-Path $fix 'children-60.json') '[{"number":61,"title":"first child","state":"OPEN","labels":[{"name":"size/S"}],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"},{"number":62,"title":"second child","state":"OPEN","labels":[{"name":"size/S"}],"assignees":[],"createdAt":"2026-01-03T00:00:00Z"}]'
    $out = Invoke-TriageCli $fix @('--issue', '60')
    Assert-Eq 'proceed' (Get-JsonField $out 'outcome') 'AC7 recovers to proceed'
    Assert-Eq '62' (Get-JsonField $out 'active') 'AC7 advances to the second child after losing the race'
    # m4: the abandoned claim rolls back its speculative @me assignment.
    Assert-Contains 'UNASSIGN 61' (Get-LogText $fix) 'AC7 rolls back @me on the lost claim (m4)'

    Write-Host ''
    Write-Host '=== AC8: only-closed children -> completion audit (skipped), not a closed pick ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 70 OPEN '[{"name":"size/XL"}]' '[]' 'Parent all done'
    Set-FixtureFile (Join-Path $fix 'children-70.json') '[{"number":71,"title":"done a","state":"CLOSED","labels":[],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"},{"number":72,"title":"done b","state":"CLOSED","labels":[],"assignees":[],"createdAt":"2026-01-03T00:00:00Z"}]'
    $out = Invoke-TriageCli $fix @('--issue', '70')
    Assert-Eq 'skipped' (Get-JsonField $out 'outcome') 'AC8 outcome=skipped'
    Assert-Contains 'completion audit' (Get-JsonField $out 'reason') 'AC8 reason names the completion audit'
    Assert-Eq '0' ([string](Get-LogCount $fix 'ASSIGN')) 'AC8 never claims a closed child'

    Write-Host ''
    Write-Host '=== AC9: blocked/decomposed perform no repository work ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 80 OPEN '[{"name":"size/S"}]' '[]' 'Blocked by #81'
    Set-IssueFixture $fix 81 OPEN '[]' '[]' 'dep'
    $out = Invoke-TriageCli $fix @('--issue', '80')
    Assert-Eq 'blocked' (Get-JsonField $out 'outcome') 'AC9 blocked terminal'
    Assert-Eq '0' ([string](Get-LogCount $fix 'ASSIGN')) 'AC9 blocked makes no assignment'
    Assert-Eq '0' ([string](Get-LogCount $fix 'CREATE')) 'AC9 blocked creates no branch/child'

    Write-Host ''
    Write-Host '=== VER: cyclic relationship terminates via visited guard ==='
    $fix = New-Fixture
    Set-IssueFixture $fix 90 OPEN '[{"name":"size/XL"}]' '[]' 'A'
    Set-IssueFixture $fix 91 OPEN '[{"name":"size/XL"}]' '[]' 'B'
    # 90 -> 91 -> 90 cycle.
    Set-FixtureFile (Join-Path $fix 'children-90.json') '[{"number":91,"title":"B","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"}]'
    Set-FixtureFile (Join-Path $fix 'children-91.json') '[{"number":90,"title":"A","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-01T00:00:00Z"}]'
    $out = Invoke-TriageCli $fix @('--issue', '90')
    $cycOutcome = Get-JsonField $out 'outcome'
    Assert-True (($cycOutcome -eq 'skipped') -or ($cycOutcome -eq 'failed')) `
        "VER cycle terminates with a terminal outcome ($cycOutcome)"

    Write-Host ''
    Write-Host '=== VER: max-depth guard yields failed, not an infinite descent ==='
    $fix = New-Fixture
    # Chain 100 -> 101 -> 102 -> 103, each oversized with one deeper child.
    foreach ($n in 100, 101, 102, 103) {
        Set-IssueFixture $fix $n OPEN '[{"name":"size/XL"}]' '[]' "node $n"
    }
    Set-FixtureFile (Join-Path $fix 'children-100.json') '[{"number":101,"title":"n101","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-02T00:00:00Z"}]'
    Set-FixtureFile (Join-Path $fix 'children-101.json') '[{"number":102,"title":"n102","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-03T00:00:00Z"}]'
    Set-FixtureFile (Join-Path $fix 'children-102.json') '[{"number":103,"title":"n103","state":"OPEN","labels":[{"name":"size/XL"}],"assignees":[],"createdAt":"2026-01-04T00:00:00Z"}]'
    Set-FixtureFile (Join-Path $fix 'children-103.json') '[]'
    $out = Invoke-TriageCli $fix @('--issue', '100', '--max-depth', '2')
    Assert-Eq 'failed' (Get-JsonField $out 'outcome') 'VER max-depth guard yields failed'
    Assert-Contains 'MAX_CHILD_DEPTH' (Get-JsonField $out 'reason') 'VER failure names the depth guard'

    Write-Host ''
    Write-Host '=== VER (m1): three identical fetch failures stop with a blocked outcome ==='
    # No issue-200.json fixture -> every fetch returns empty. The retry helper
    # stops after TRIAGE_MAX_FAILURES identical failures with a blocked outcome.
    $fix = New-Fixture
    $out = Invoke-TriageCli $fix @('--issue', '200')
    Assert-Eq 'blocked' (Get-JsonField $out 'outcome') 'VER 3-fail yields blocked'
    Assert-Contains 'identical failures' (Get-JsonField $out 'reason') 'VER 3-fail names the failure rule'

    Write-Host ''
    Write-Host '=== VER: batch reporting does not treat decomposition as a merge success ==='
    $doc = Get-Content -LiteralPath $BatchModeDoc -Raw
    Assert-Contains 'only `Merged` items count as successes' $doc `
        'VER batch-mode doc asserts only merged items are successes'

    Write-Host ''
    Write-Host '=== S2 (#847): the CLI prints the outcome JSON on stdout ==='
    # Split-TriageCliResult regression. run_triage writes the JSON to the success
    # stream and returns the exit code, so a dot-sourced caller receives
    # @(<json>, <int>). Passing that array straight to `exit` cast the whole
    # array to int, which threw and took the JSON with it -- `pwsh -File
    # triage.ps1` printed nothing while triage.sh printed the outcome.
    $fix = New-Fixture
    Set-IssueFixture $fix 300 OPEN '[{"name":"size/S"}]' '[]' 'simple work'
    $out = Invoke-TriageCli $fix @('--issue', '300')
    $jsonLines = @($script:LastCliRaw | Where-Object { $_ -match '^\{' })
    Assert-True ($jsonLines.Count -eq 1) 'S2 CLI prints exactly one JSON line on stdout'
    Assert-Eq 'proceed' (Get-JsonField $out 'outcome') 'S2 the printed JSON carries the outcome'
    Assert-Eq '300' (Get-JsonField $out 'active') 'S2 the printed JSON carries the active issue'
    Assert-Eq '0' ([string]$script:LastCliExit) 'S2 non-failed outcome exits 0'
    # The exit code must survive the same split: `failed` still returns 1.
    $fix = New-Fixture
    Set-IssueFixture $fix 310 OPEN '[{"name":"size/XL"}]' '[]' 'needs a plan'
    Set-FixtureFile (Join-Path $fix 'children-310.json') '[]'
    $out = Invoke-TriageCli $fix @('--issue', '310')
    Assert-Eq 'failed' (Get-JsonField $out 'outcome') 'S2 needs_plan yields failed'
    Assert-Eq '1' ([string]$script:LastCliExit) 'S2 failed outcome exits 1 alongside its JSON'

    Write-Host ''
    Write-Host '=== S1 (#847): native gh exiting non-zero must not throw ==='
    # $PSNativeCommandUseErrorActionPreference = $false is pinned at triage.ps1
    # script scope. Without it, a host that enabled the preference would promote
    # gh's non-zero exit into a terminating error under 'Stop', and the retry /
    # eligibility logic would never see the empty read it is written against.
    $shim = New-NativeGhShim
    $fix = New-Fixture
    $out = Invoke-TriageCliWithNativePref $fix '200' $shim
    Assert-Eq 'blocked' (Get-JsonField $out 'outcome') `
        'S1 native non-zero gh still yields the blocked outcome, not a throw'
    Assert-Contains 'identical failures' (Get-JsonField $out 'reason') `
        'S1 the retry rule still names the failure stop'
    Assert-False ((($script:LastCliRaw -join "`n")).Contains('NativeCommandExitException')) `
        'S1 no NativeCommandExitException surfaced'
    # Sanity: the shim really is a native command that exits non-zero, otherwise
    # the assertions above would hold even with the fix reverted.
    $env:FAKE_GH_DIR = $fix
    & $shim issue view 200 --repo test/repo --json state 2>$null | Out-Null
    Assert-Eq '1' ([string]$LASTEXITCODE) 'S1 shim exits non-zero on an empty read (case is not vacuous)'
}
finally {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '=== Summary ==='
Write-Host "  $Pass passed, $Fail failed"
if ($Errors.Count -gt 0) {
    Write-Host ''
    Write-Host 'Failures:'
    foreach ($err in $Errors) {
        Write-Host "  $err"
    }
    exit 1
}
exit 0
