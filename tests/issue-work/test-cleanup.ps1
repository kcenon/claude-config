#Requires -Version 7.0
# Test suite for global/skills/_internal/issue-work/scripts/cleanup-workspace.ps1
# Run: pwsh -NoProfile -File tests/issue-work/test-cleanup.ps1
#
# PowerShell parity suite for tests/issue-work/test-cleanup.sh. Drives the same
# resume-reconciliation + safe-cleanup stage
# (PUSHED -> ... -> MERGED -> CLEANUP_PENDING -> CLEANED) against a real local
# bare git repository plus the fake gh double (fake-gh.ps1) for the PR-state
# reads reconciliation performs. Dot-sourcing cleanup-workspace.ps1 also loads
# workspace.ps1, so the #838 manifest primitive (workspace_manifest_*) is
# available for assertions.
#
# AC -> test mapping (identical to the bash suite; see
# reference/workspace-lifecycle.md, #840 sections):
#   AC1  cleanup safety predicate  -> traversal / symlink / basename / marker /
#                                     base / root / home are each REFUSED
#   AC2  git-state gate            -> tracked change / untracked / conflict REFUSED
#   AC3  remotely-recoverable      -> unpushed REFUSED; pushed OK; squash-merge OK
#   AC4  agents-terminated gate    -> a surviving .iw-writer.lease REFUSED
#   AC5  resume reconciliation     -> a MERGED PR repairs state to MERGED even
#                                     when the manifest stored PR_OPEN
#   AC6  3-fail preservation       -> failing remover retries exactly 3x, run
#                                     root survives, manifest not CLEANED, a
#                                     manual-procedure message names the path
#   AC7  happy path                -> MERGED + clean + recoverable + no agents +
#                                     valid path emits CLEANED, run root removed
#   AC8  credential redaction      -> a git error carrying a fake token never
#                                     appears in output or the manifest
#
# PowerShell-only regression cases (issue #847, commit 38df2ec):
#   S1   $PSNativeCommandUseErrorActionPreference is pinned $false at script
#        scope, so a host that enabled it still gets structured refusals from the
#        paths that read a non-zero git/gh exit as data (no upstream /
#        not-an-ancestor / no such PR) instead of a NativeCommandExitException.
#   S2   Split-CleanupCliResult puts the outcome JSON on stdout for
#        `pwsh -File cleanup-workspace.ps1 ...`; before the fix the CLI printed
#        nothing at all because `exit @(<json>, <int>)` threw on the array cast.
#
# Injection seams exercised: GIT_BIN, GH_BIN, CLEANUP_RM, CLEANUP_RETRY_SLEEP,
# CLEANUP_LEASE_DIRNAME. Seams whose value is captured at load time are driven
# through a child pwsh so the env var is read exactly as a real caller reads it.

$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Cleanup = Join-Path $RootDir 'global/skills/_internal/issue-work/scripts/cleanup-workspace.ps1'
$FakeGh = Join-Path $RootDir 'tests/issue-work/fake-gh.ps1'

$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("iw-cleanup-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null
# Resolve the provider path once so every derived path is spelled the same way
# the script's own _cleanup_realpath will spell it. The path-prefix / marker /
# TOCTOU checks compare canonicalized paths, so the base and the candidates must
# agree; they do because both sides go through the same resolver.
$Work = (Resolve-Path -LiteralPath $Work).Path

$Pass = 0
$Fail = 0
$Skip = 0
$Errors = @()

# Saved so the suite restores the caller's environment on the way out.
$SavedEnv = @{}
foreach ($name in @('GH_BIN', 'GIT_BIN', 'FAKE_GH_DIR', 'CLEANUP_RM', 'CLEANUP_RETRY_SLEEP', 'CLEANUP_LEASE_DIRNAME')) {
    $SavedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
}

# ── Assertion helpers ─────────────────────────────────────────────────

function Write-Pass {
    param([string]$Label)
    $script:Pass++
    Write-Host "  PASS: $Label"
}

function Write-Fail {
    param([string]$Label, [string]$Detail = '')
    $script:Fail++
    $script:Errors += "FAIL: $Label$(if ($Detail) { " -- $Detail" })"
    Write-Host "  FAIL: $Label$(if ($Detail) { " ($Detail)" })"
}

function Write-Skip {
    param([string]$Label, [string]$Reason)
    $script:Skip++
    Write-Host "  SKIP: $Label ($Reason)"
}

function Assert-Equal {
    param([AllowEmptyString()][string]$Expected, [AllowEmptyString()][string]$Actual, [string]$Label)
    if ($Expected -eq $Actual) { Write-Pass $Label } else { Write-Fail $Label "expected '$Expected', got '$Actual'" }
}

function Assert-True {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if ($Condition) { Write-Pass $Label } else { Write-Fail $Label $Detail }
}

function Assert-False {
    param([bool]$Condition, [string]$Label, [string]$Detail = '')
    if (-not $Condition) { Write-Pass $Label } else { Write-Fail $Label $Detail }
}

function Assert-Contains {
    param([string]$Needle, [AllowEmptyString()][string]$Haystack, [string]$Label)
    if ($Haystack -and $Haystack.Contains($Needle)) { Write-Pass $Label } else { Write-Fail $Label "'$Needle' not in output: $Haystack" }
}

function Assert-NotContains {
    param([string]$Needle, [AllowEmptyString()][string]$Haystack, [string]$Label)
    if ($Haystack -and $Haystack.Contains($Needle)) { Write-Fail $Label "'$Needle' unexpectedly present" } else { Write-Pass $Label }
}

function Assert-PathExists {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) { Write-Pass $Label } else { Write-Fail $Label "$Path does not exist" }
}

function Assert-PathMissing {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) { Write-Fail $Label "$Path still exists" } else { Write-Pass $Label }
}

# ── git / process helpers ─────────────────────────────────────────────

# Setup git that fails loudly: a broken fixture must not masquerade as a failed
# assertion. Args are passed as an explicit array so a leading "-C" is never
# mistaken for a parameter name.
function Invoke-GitOrDie {
    param([Parameter(Mandatory)][string[]]$GitArgs)
    & git @GitArgs 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed (exit $LASTEXITCODE)" }
}

function Get-GitLine {
    param([Parameter(Mandatory)][string[]]$GitArgs)
    return ((& git @GitArgs 2>$null | Out-String).Trim())
}

# A dot-sourced driver returns @(<emitted json...>, <exit code>) on one stream:
# PowerShell puts both the Write-Output payload and the `return` value on the
# success stream. These two helpers split them the way Split-CleanupCliResult
# does for the CLI, so assertions can address each half.
function Get-EmittedText {
    param([AllowEmptyCollection()][object[]]$Result)
    $items = @($Result)
    if ($items.Count -gt 0 -and $items[-1] -is [int]) {
        if ($items.Count -gt 1) { $items = $items[0..($items.Count - 2)] } else { $items = @() }
    }
    return (($items | ForEach-Object { [string]$_ }) -join "`n")
}

function Get-ResultCode {
    param([AllowEmptyCollection()][object[]]$Result)
    $items = @($Result)
    if ($items.Count -gt 0 -and $items[-1] -is [int]) { return [int]$items[-1] }
    return 0
}

# Run a child pwsh script with a scoped environment overlay, capturing stdout,
# stderr and the exit code separately. Used for the seams cleanup-workspace.ps1
# captures at load time (GIT_BIN, CLEANUP_LEASE_DIRNAME) and for the S1 case,
# which needs $PSNativeCommandUseErrorActionPreference set before the script
# loads -- exactly how a host with the setting enabled would reach it.
function Invoke-ChildPwsh {
    param([string]$ScriptPath, [hashtable]$EnvOverlay = @{})
    $saved = @{}
    foreach ($key in $EnvOverlay.Keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key, $EnvOverlay[$key])
    }
    $errFile = Join-Path $Work ("child-err-" + [guid]::NewGuid().ToString('N') + ".txt")
    try {
        $stdout = & pwsh -NoProfile -File $ScriptPath 2>$errFile
        $code = $LASTEXITCODE
    } finally {
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
    }
    $stderr = ''
    if (Test-Path -LiteralPath $errFile) { $stderr = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue) }
    if ($null -eq $stderr) { $stderr = '' }
    return [pscustomobject]@{
        StdOut = (($stdout | Out-String).Trim())
        StdErr = $stderr
        Code   = $code
    }
}

# ── Fixture builders (mirror the bash make_remote / clone_repo / make_run_root) ──

# Builds a bare "remote" under $Work/remote seeded with one commit on develop,
# plus a working "seed" clone used to advance the remote. Returns the bare path.
function New-Remote {
    param([string]$Name)
    $remote = Join-Path $Work "remote/$Name.git"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $remote) | Out-Null
    Invoke-GitOrDie @('init', '--bare', '-q', $remote)
    $seed = Join-Path $Work "seed-$Name"
    Invoke-GitOrDie @('init', '-q', '-b', 'develop', $seed)
    Invoke-GitOrDie @('-C', $seed, 'config', 'user.email', 'test@example.com')
    Invoke-GitOrDie @('-C', $seed, 'config', 'user.name', 'test')
    [System.IO.File]::WriteAllText((Join-Path $seed 'file.txt'), "content`n")
    Invoke-GitOrDie @('-C', $seed, 'add', 'file.txt')
    Invoke-GitOrDie @('-C', $seed, 'commit', '-q', '-m', 'seed commit')
    Invoke-GitOrDie @('-C', $seed, 'remote', 'add', 'origin', $remote)
    Invoke-GitOrDie @('-C', $seed, 'push', '-q', 'origin', 'develop')
    return $remote
}

function New-CloneRepo {
    param([string]$Remote, [string]$Dest)
    Invoke-GitOrDie @('clone', '-q', '--branch', 'develop', '--single-branch', $Remote, $Dest)
    Invoke-GitOrDie @('-C', $Dest, 'config', 'user.email', 'test@example.com')
    Invoke-GitOrDie @('-C', $Dest, 'config', 'user.name', 'test')
    return $Dest
}

# Materializes a valid run root under <Base>: the run root, a valid run marker,
# a clone at <run_root>/repo, and a manifest. Returns the run root path.
function New-RunRoot {
    param([string]$Base, [string]$Issue, [string]$Suffix, [string]$Remote)
    $runRoot = Join-Path $Base "iw-$Issue-$Suffix"
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $runRoot $script:WorkspaceMarkerFile), "issue=$Issue`ncreated=2026-07-18T00:00:00Z`n")
    New-CloneRepo $Remote (Join-Path $runRoot 'repo') | Out-Null
    $manifest = Join-Path $runRoot 'manifest'
    workspace_manifest_write -Path $manifest -Key 'issue' -Value $Issue | Out-Null
    workspace_manifest_write -Path $manifest -Key 'run_root' -Value $runRoot | Out-Null
    return $runRoot
}

# ── Fake credential material (secret-scanner-safe) ────────────────────
# A low-entropy, clearly-fake secret with NO real token prefix. The credential
# URL is assembled at runtime and handed to the git shim through an environment
# variable, so no complete "scheme://user:secret@host" literal is ever written to
# a committed file (GitGuardian scans history).
$FakeSecret = 'placeholder-not-a-real-secret'
$FakeCredUrl = 'https://' + "x-access-token:$FakeSecret" + '@github.com/acme/x.git'

# ── Load the script under test ────────────────────────────────────────
# Seams that cleanup-workspace.ps1 captures at load time must be exported first.
# CLEANUP_RETRY_SLEEP=0 gives a fast, deterministic retry loop; GH_BIN aims the
# gh seam at the committed PowerShell double. Child pwsh runs inherit both.
$env:CLEANUP_RETRY_SLEEP = '0'
$env:GH_BIN = $FakeGh
$env:GIT_BIN = $null
$env:CLEANUP_RM = $null
$env:CLEANUP_LEASE_DIRNAME = $null
$env:FAKE_GH_DIR = Join-Path $Work 'fakegh'
New-Item -ItemType Directory -Force -Path $env:FAKE_GH_DIR | Out-Null

Write-Host "=== cleanup-workspace.ps1 unit + scenario tests ==="
. $Cleanup

try {
    Write-Host ""
    Write-Host "=== Load-time injection seams ==="
    Assert-Equal '0' ([string]$script:CleanupRetrySleep) 'CLEANUP_RETRY_SLEEP seam honored at load time'
    Assert-Equal $FakeGh $script:GhBin 'GH_BIN seam honored at load time'
    Assert-Equal 'git' $script:GitBin 'GIT_BIN defaults to git when unset'
    Assert-Equal '.iw-writer.lease' $script:CleanupLeaseDirname 'CLEANUP_LEASE_DIRNAME defaults to .iw-writer.lease'

    $Base = Join-Path $Work 'base'
    New-Item -ItemType Directory -Force -Path $Base | Out-Null
    $Remote = New-Remote 'acme'

    Write-Host ""
    Write-Host "=== AC1: cleanup safety predicate -- each unsafe candidate is REFUSED ==="
    # A genuinely valid run root, used as the positive control.
    $validRoot = New-RunRoot $Base '840' 'valid' $Remote

    # Shape guard: the predicate must return exactly one boolean. A stray
    # Write-Output anywhere inside it would make every `if (cleanup_validate_path
    # ...)` below test an array instead of the verdict, which PowerShell coerces
    # to $true and would silently disarm the whole safety gate.
    $shape = @(cleanup_validate_path -Candidate $validRoot -RunBase $Base -Issue '840')
    Assert-Equal '1' ([string]$shape.Count) 'AC1 the predicate emits exactly one value (no stray output)'
    Assert-True ($shape[0] -is [bool]) 'AC1 the predicate returns a boolean'

    Assert-True (cleanup_validate_path -Candidate $validRoot -RunBase $Base -Issue '840') 'AC1 a valid run root passes the safety predicate' $script:CleanupLastError
    Assert-False (cleanup_validate_path -Candidate '' -RunBase $Base -Issue '840') 'AC1 empty candidate refused'
    Assert-False (cleanup_validate_path -Candidate '/' -RunBase $Base -Issue '840') 'AC1 filesystem root refused'
    Assert-False (cleanup_validate_path -Candidate $HOME -RunBase $Base -Issue '840') 'AC1 home directory refused'

    # The base itself: give the base an iw-840-* name + marker so it clears the
    # basename/marker gates, proving the strictly-under-base guard is what refuses it.
    $baseNamed = Join-Path $Work 'iw-840-baseonly'
    New-Item -ItemType Directory -Force -Path $baseNamed | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $baseNamed $script:WorkspaceMarkerFile), "issue=840`n")
    Assert-False (cleanup_validate_path -Candidate $baseNamed -RunBase $baseNamed -Issue '840') 'AC1 the base itself refused (never strictly under itself)'

    # Traversal in the raw candidate.
    Assert-False (cleanup_validate_path -Candidate (Join-Path $Base '../iw-840-x') -RunBase $Base -Issue '840') "AC1 '..' traversal refused"

    # Basename does not match iw-840-*.
    $wrongName = Join-Path $Base 'notarun-840'
    New-Item -ItemType Directory -Force -Path $wrongName | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $wrongName $script:WorkspaceMarkerFile), "issue=840`n")
    Assert-False (cleanup_validate_path -Candidate $wrongName -RunBase $Base -Issue '840') 'AC1 basename not matching iw-840-* refused'

    # Missing marker.
    $noMarker = Join-Path $Base 'iw-840-nomarker'
    New-Item -ItemType Directory -Force -Path $noMarker | Out-Null
    Assert-False (cleanup_validate_path -Candidate $noMarker -RunBase $Base -Issue '840') 'AC1 missing marker refused'

    # Marker names the wrong issue.
    $wrongIssue = Join-Path $Base 'iw-840-wrongissue'
    New-Item -ItemType Directory -Force -Path $wrongIssue | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $wrongIssue $script:WorkspaceMarkerFile), "issue=999`n")
    Assert-False (cleanup_validate_path -Candidate $wrongIssue -RunBase $Base -Issue '840') 'AC1 marker naming the wrong issue refused'

    # Symlinked run root (swap attack): the final component is itself a symlink.
    # Creating one can require elevation on Windows; the case is skipped rather
    # than silently passed if the platform refuses.
    $symRoot = Join-Path $Base 'iw-840-symlink'
    $symMade = $false
    try {
        New-Item -ItemType SymbolicLink -Path $symRoot -Target $validRoot -ErrorAction Stop | Out-Null
        $symMade = $true
    } catch {
        Write-Skip 'AC1 symlinked run root refused' 'symlink creation not permitted on this platform'
    }
    if ($symMade) {
        Assert-False (cleanup_validate_path -Candidate $symRoot -RunBase $Base -Issue '840') 'AC1 symlinked run root refused (swap attack)'
    }

    Write-Host ""
    Write-Host "=== AC2: git-state gate -- dirty tree or unresolved conflict is REFUSED ==="
    $gsRoot = New-RunRoot $Base '840' 'gitstate' $Remote
    $gsRepo = Join-Path $gsRoot 'repo'
    $gsFile = Join-Path $gsRepo 'file.txt'
    Assert-True (cleanup_git_state_clean -RepoDir $gsRepo) 'AC2 a fresh clone is clean' $script:CleanupLastError

    # Tracked modification. Restored by rewriting the original bytes rather than
    # by a git checkout, so the fixture never depends on a working-tree reset.
    [System.IO.File]::WriteAllText($gsFile, "content`nchanged`n")
    Assert-False (cleanup_git_state_clean -RepoDir $gsRepo) 'AC2 tracked modification refused'
    [System.IO.File]::WriteAllText($gsFile, "content`n")

    # Untracked file.
    [System.IO.File]::WriteAllText((Join-Path $gsRepo 'untracked.txt'), "new`n")
    Assert-False (cleanup_git_state_clean -RepoDir $gsRepo) 'AC2 untracked file refused'
    Remove-Item -LiteralPath (Join-Path $gsRepo 'untracked.txt') -Force
    Assert-True (cleanup_git_state_clean -RepoDir $gsRepo) 'AC2 tree is clean again after reverting' $script:CleanupLastError

    # Unresolved conflict: a real merge left mid-conflict.
    $cfRepo = Join-Path $Work 'conflict-repo'
    Invoke-GitOrDie @('init', '-q', '-b', 'develop', $cfRepo)
    Invoke-GitOrDie @('-C', $cfRepo, 'config', 'user.email', 'test@example.com')
    Invoke-GitOrDie @('-C', $cfRepo, 'config', 'user.name', 'test')
    [System.IO.File]::WriteAllText((Join-Path $cfRepo 'c.txt'), "base`n")
    Invoke-GitOrDie @('-C', $cfRepo, 'add', 'c.txt')
    Invoke-GitOrDie @('-C', $cfRepo, 'commit', '-q', '-m', 'base')
    Invoke-GitOrDie @('-C', $cfRepo, 'checkout', '-q', '-b', 'other')
    [System.IO.File]::WriteAllText((Join-Path $cfRepo 'c.txt'), "theirs`n")
    Invoke-GitOrDie @('-C', $cfRepo, 'add', 'c.txt')
    Invoke-GitOrDie @('-C', $cfRepo, 'commit', '-q', '-m', 'theirs')
    Invoke-GitOrDie @('-C', $cfRepo, 'checkout', '-q', 'develop')
    [System.IO.File]::WriteAllText((Join-Path $cfRepo 'c.txt'), "ours`n")
    Invoke-GitOrDie @('-C', $cfRepo, 'add', 'c.txt')
    Invoke-GitOrDie @('-C', $cfRepo, 'commit', '-q', '-m', 'ours')
    & git -C $cfRepo merge other 2>$null | Out-Null   # expected to conflict
    Assert-False (cleanup_git_state_clean -RepoDir $cfRepo) 'AC2 unresolved conflict refused'

    Write-Host ""
    Write-Host "=== AC3: remotely-recoverable -- unpushed REFUSED; pushed OK; squash-merge OK ==="
    $rcRoot = New-RunRoot $Base '840' 'recover' $Remote
    $rcRepo = Join-Path $rcRoot 'repo'
    Assert-True (cleanup_remotely_recoverable -RepoDir $rcRepo) 'AC3 pushed HEAD is recoverable' $script:CleanupLastError

    # Unpushed commit on top of develop.
    [System.IO.File]::WriteAllText((Join-Path $rcRepo 'file.txt'), "content`nlocal work`n")
    Invoke-GitOrDie @('-C', $rcRepo, 'add', 'file.txt')
    Invoke-GitOrDie @('-C', $rcRepo, 'commit', '-q', '-m', 'unpushed local work')
    Assert-False (cleanup_remotely_recoverable -RepoDir $rcRepo) 'AC3 unpushed commit refused'

    # Squash-merge: the local feature commit is NOT an ancestor of the merge
    # commit, but the merge commit landed on origin/develop, so (c) deems it
    # recoverable.
    $sqRemote = New-Remote 'squash'
    $sqRepo = Join-Path $Work 'squash-repo'
    New-CloneRepo $sqRemote $sqRepo | Out-Null
    Invoke-GitOrDie @('-C', $sqRepo, 'checkout', '-q', '-b', 'feat/issue-840-x')
    [System.IO.File]::WriteAllText((Join-Path $sqRepo 'file.txt'), "content`nfeature`n")
    Invoke-GitOrDie @('-C', $sqRepo, 'add', 'file.txt')
    Invoke-GitOrDie @('-C', $sqRepo, 'commit', '-q', '-m', 'feature work (never pushed as-is)')
    $sqSeed = Join-Path $Work 'seed-squash'
    Invoke-GitOrDie @('-C', $sqSeed, 'checkout', '-q', 'develop')
    [System.IO.File]::WriteAllText((Join-Path $sqSeed 'file.txt'), "content`nmerged squashed change`n")
    Invoke-GitOrDie @('-C', $sqSeed, 'add', 'file.txt')
    Invoke-GitOrDie @('-C', $sqSeed, 'commit', '-q', '-m', 'squash merge of #840')
    Invoke-GitOrDie @('-C', $sqSeed, 'push', '-q', 'origin', 'develop')
    $mergeCommit = Get-GitLine @('-C', $sqSeed, 'rev-parse', 'HEAD')
    Invoke-GitOrDie @('-C', $sqRepo, 'fetch', '-q', 'origin')
    Assert-False (cleanup_remotely_recoverable -RepoDir $sqRepo) 'AC3 feature branch alone is not recoverable (precondition)'
    Assert-True (cleanup_remotely_recoverable -RepoDir $sqRepo -MergeCommit $mergeCommit) 'AC3 squash-merge is recoverable via the merge commit on origin/develop' $script:CleanupLastError

    Write-Host ""
    Write-Host "=== AC4: agents-terminated -- a surviving lease is REFUSED ==="
    $agRoot = New-RunRoot $Base '840' 'agents' $Remote
    Assert-True (cleanup_agents_terminated -RunRoot $agRoot) 'AC4 no lease -> agents terminated' $script:CleanupLastError
    $leaseDir = Join-Path $agRoot "repo/$script:CleanupLeaseDirname"
    New-Item -ItemType Directory -Force -Path $leaseDir | Out-Null
    Assert-False (cleanup_agents_terminated -RunRoot $agRoot) 'AC4 surviving lease refused'
    Remove-Item -LiteralPath $leaseDir -Force

    # CLEANUP_LEASE_DIRNAME seam: captured at load time, so it is driven in a
    # child pwsh where the env var is read exactly as a real caller sets it.
    $seamRoot = New-RunRoot $Base '840' 'leaseseam' $Remote
    New-Item -ItemType Directory -Force -Path (Join-Path $seamRoot 'repo/.custom-writer.lease') | Out-Null
    $seamDefaultRoot = New-RunRoot $Base '840' 'leasedefault' $Remote
    New-Item -ItemType Directory -Force -Path (Join-Path $seamDefaultRoot 'repo/.iw-writer.lease') | Out-Null
    $leaseChild = Join-Path $Work 'child-lease-seam.ps1'
    Set-Content -LiteralPath $leaseChild -Value @'
$ErrorActionPreference = 'Stop'
. $env:IW_CLEANUP_SCRIPT
[Console]::Out.WriteLine("SEAM=$script:CleanupLeaseDirname")
[Console]::Out.WriteLine("CUSTOM=" + (cleanup_agents_terminated -RunRoot $env:IW_SEAM_ROOT))
[Console]::Out.WriteLine("DEFAULTIGNORED=" + (cleanup_agents_terminated -RunRoot $env:IW_SEAM_DEFAULT_ROOT))
exit 0
'@
    $leaseRun = Invoke-ChildPwsh $leaseChild @{
        IW_CLEANUP_SCRIPT       = $Cleanup
        IW_SEAM_ROOT            = $seamRoot
        IW_SEAM_DEFAULT_ROOT    = $seamDefaultRoot
        CLEANUP_LEASE_DIRNAME   = '.custom-writer.lease'
    }
    Assert-Contains 'SEAM=.custom-writer.lease' $leaseRun.StdOut 'AC4 CLEANUP_LEASE_DIRNAME seam is read from the environment at load time'
    Assert-Contains 'CUSTOM=False' $leaseRun.StdOut 'AC4 a lease under the seam name is refused'
    Assert-Contains 'DEFAULTIGNORED=True' $leaseRun.StdOut 'AC4 the default lease name is ignored once the seam is overridden'

    Write-Host ""
    Write-Host "=== AC5: resume reconciliation -- a MERGED PR wins over a stored PR_OPEN ==="
    $recRoot = New-RunRoot $Base '840' 'reconcile' $Remote
    $recRepo = Join-Path $recRoot 'repo'
    $recManifest = Join-Path $recRoot 'manifest'
    # Stored state deliberately stale: PR_OPEN even though the PR has since merged.
    workspace_manifest_write -Path $recManifest -Key 'state' -Value 'PR_OPEN' | Out-Null
    $recHead = Get-GitLine @('-C', $recRepo, 'rev-parse', 'HEAD')
    [System.IO.File]::WriteAllText(
        (Join-Path $env:FAKE_GH_DIR 'pr-view-77.json'),
        ('{"state":"MERGED","mergedAt":"2026-07-18T01:00:00Z","mergeCommit":{"oid":"' + $recHead + '"},"headRefName":"feat/issue-840-x"}'))
    $recResult = cleanup_reconcile -RepoDir $recRepo -Manifest $recManifest -PrNumber '77'
    $recOut = Get-EmittedText $recResult
    Assert-Contains '"state":"MERGED"' $recOut 'AC5 reconcile emits MERGED (reality wins over stored PR_OPEN)'
    Assert-Equal '0' ([string](Get-ResultCode $recResult)) 'AC5 reconcile returns 0'
    Assert-Equal 'MERGED' (workspace_manifest_state -Path $recManifest) 'AC5 manifest repaired to MERGED'
    Assert-Equal $recHead (workspace_manifest_read -Path $recManifest -Key 'merge_commit') 'AC5 reconcile records the merge commit'
    Assert-Equal $recHead (workspace_manifest_read -Path $recManifest -Key 'head') 'AC5 reconcile records the live HEAD'

    Write-Host ""
    Write-Host "=== AC6: 3-fail preservation -- failing remover retries 3x, then preserves ==="
    $failRoot = New-RunRoot $Base '840' 'threefail' $Remote
    $failRepo = Join-Path $failRoot 'repo'
    $failManifest = Join-Path $failRoot 'manifest'
    workspace_manifest_write -Path $failManifest -Key 'state' -Value 'MERGED' | Out-Null

    # A remover that always fails and counts its invocations. Invoked through the
    # CleanupRm seam as `& $script:CleanupRm $Target`; `exit 1` inside a .ps1 run
    # in-process returns to the caller and sets $LASTEXITCODE, which is what
    # _cleanup_remove reads.
    $rmCount = Join-Path $Work 'rm-count'
    [System.IO.File]::WriteAllText($rmCount, '')
    $failRm = Join-Path $Work 'failing-rm.ps1'
    Set-Content -LiteralPath $failRm -Value @'
[System.IO.File]::AppendAllText($env:IW_RM_COUNT, "x`n")
exit 1
'@
    $env:IW_RM_COUNT = $rmCount
    # Per-call seam override. $script:CleanupRm is the load-time capture of
    # $env:CLEANUP_RM and is what _cleanup_remove reads, so assigning it here is
    # the direct analog of the bash suite's `CLEANUP_RM="$fail_rm" cleanup_workspace`
    # env prefix, and it keeps the seam off for the AC7 happy path below.
    $savedRm = $script:CleanupRm
    $failMergeCommit = Get-GitLine @('-C', $failRepo, 'rev-parse', 'HEAD')

    # _cleanup_print_manual_procedure writes straight to the process stderr
    # handle via [Console]::Error, which PowerShell's redirection of a function
    # call cannot intercept; swap in a StringWriter to capture it.
    $capturedErr = New-Object System.IO.StringWriter
    $originalErr = [Console]::Error
    try {
        $script:CleanupRm = $failRm
        [Console]::SetError($capturedErr)
        $failResult = cleanup_workspace -RunRoot $failRoot -RepoDir $failRepo -Manifest $failManifest -RunBase $Base -Issue '840' -MergeCommit $failMergeCommit
    } finally {
        [Console]::SetError($originalErr)
        $script:CleanupRm = $savedRm
    }
    $failOut = Get-EmittedText $failResult
    $failErr = $capturedErr.ToString()
    $attempts = @(Get-Content -LiteralPath $rmCount -ErrorAction SilentlyContinue).Count
    Assert-Equal '3' ([string]$attempts) 'AC6 the failing remover is retried exactly 3 times (retry cap honored)'
    Assert-PathExists $failRoot 'AC6 the run root survives a failed cleanup'
    Assert-Contains 'PRESERVED' $failOut 'AC6 outcome is PRESERVED'
    Assert-Equal '1' ([string](Get-ResultCode $failResult)) 'AC6 a preserved cleanup returns 1'
    Assert-Contains 'MANUAL CLEANUP REQUIRED' $failErr 'AC6 a manual-procedure message is printed'
    Assert-Contains $failRoot $failErr 'AC6 the manual procedure names the exact validated path'
    Assert-True ((workspace_manifest_state -Path $failManifest) -ne 'CLEANED') 'AC6 manifest is not CLEANED after a failed cleanup'

    Write-Host ""
    Write-Host "=== AC7: happy path -- MERGED + clean + recoverable + no agents removes root ==="
    $happyRoot = New-RunRoot $Base '840' 'happy' $Remote
    $happyRepo = Join-Path $happyRoot 'repo'
    # Manifest override OUTSIDE the run root so the terminal state survives the
    # removal and can be asserted (the in-root manifest would be gone).
    $happyManifest = Join-Path $Work 'happy-ext-manifest'
    workspace_manifest_write -Path $happyManifest -Key 'state' -Value 'MERGED' | Out-Null
    $happyMergeCommit = Get-GitLine @('-C', $happyRepo, 'rev-parse', 'HEAD')
    $happyResult = cleanup_workspace -RunRoot $happyRoot -RepoDir $happyRepo -Manifest $happyManifest -RunBase $Base -Issue '840' -MergeCommit $happyMergeCommit
    $happyOut = Get-EmittedText $happyResult
    Assert-Contains '"state":"CLEANED"' $happyOut 'AC7 happy path emits CLEANED'
    Assert-Equal '0' ([string](Get-ResultCode $happyResult)) 'AC7 happy path returns 0'
    Assert-PathMissing $happyRoot 'AC7 run root removed on the happy path'
    Assert-Equal 'CLEANED' (workspace_manifest_state -Path $happyManifest) 'AC7 external manifest persists CLEANED'

    # Guard: cleanup before MERGED is refused (incomplete PR preservation case).
    $earlyRoot = New-RunRoot $Base '840' 'early' $Remote
    workspace_manifest_write -Path (Join-Path $earlyRoot 'manifest') -Key 'state' -Value 'PR_OPEN' | Out-Null
    $earlyResult = cleanup_workspace -RunRoot $earlyRoot -RepoDir (Join-Path $earlyRoot 'repo') -Manifest (Join-Path $earlyRoot 'manifest') -RunBase $Base -Issue '840'
    Assert-Contains 'PRESERVED' (Get-EmittedText $earlyResult) 'AC7 cleanup before MERGED is refused'
    Assert-PathExists $earlyRoot 'AC7 the run root survives a pre-MERGED cleanup attempt'

    Write-Host ""
    Write-Host "=== AC8: credential redaction -- a git error carrying a fake token is scrubbed ==="
    # A git shim whose branch lookup emits a credential-bearing URL, mimicking a
    # credential leaking through git output. reconcile writes/emits branch + head;
    # both must be redacted before they reach stdout or the manifest. Driven in a
    # child pwsh because GIT_BIN is captured at load time.
    $tokGit = Join-Path $Work 'fake-git-token.ps1'
    Set-Content -LiteralPath $tokGit -Value @'
$joined = @($args) -join ' '
if ($joined -like '*rev-parse --abbrev-ref HEAD*') { Write-Output $env:IW_FAKE_CRED_URL; exit 0 }
if ($joined -like '*rev-parse HEAD*') { Write-Output 'deadbeefcafe'; exit 0 }
exit 0
'@
    $tokManifest = Join-Path $Work 'token-manifest'
    workspace_manifest_write -Path $tokManifest -Key 'state' -Value 'PUSHED' | Out-Null
    $tokChild = Join-Path $Work 'child-redaction.ps1'
    Set-Content -LiteralPath $tokChild -Value @'
$ErrorActionPreference = 'Stop'
. $env:IW_CLEANUP_SCRIPT
$result = cleanup_reconcile -RepoDir $env:IW_REPO_DIR -Manifest $env:IW_MANIFEST
foreach ($item in @($result)) {
    if ($item -isnot [int]) { [Console]::Out.WriteLine([string]$item) }
}
exit 0
'@
    $tokRun = Invoke-ChildPwsh $tokChild @{
        IW_CLEANUP_SCRIPT = $Cleanup
        IW_REPO_DIR       = $Work
        IW_MANIFEST       = $tokManifest
        IW_FAKE_CRED_URL  = $FakeCredUrl
        GIT_BIN           = $tokGit
    }
    Assert-Equal '0' ([string]$tokRun.Code) 'AC8 reconcile completes under the credential-emitting git shim'
    Assert-Contains '"phase":"reconcile"' $tokRun.StdOut 'AC8 reconcile still emits its outcome JSON'
    Assert-NotContains $FakeSecret $tokRun.StdOut 'AC8 reconcile stdout never contains the fake token'
    Assert-NotContains $FakeSecret (Get-Content -LiteralPath $tokManifest -Raw) 'AC8 the manifest never contains the fake token'

    Write-Host ""
    Write-Host "=== S2 (#847): the CLI puts its outcome JSON on stdout ==="
    # Before commit 38df2ec the driver's @(<json>, <int>) result was passed
    # straight to `exit`, which threw on the array cast and took the JSON with
    # it: `pwsh -File cleanup-workspace.ps1 ...` printed nothing at all.
    $cliRoot = New-RunRoot $Base '840' 'cli' $Remote
    $cliRepo = Join-Path $cliRoot 'repo'
    $cliManifest = Join-Path $cliRoot 'manifest'
    workspace_manifest_write -Path $cliManifest -Key 'state' -Value 'PR_OPEN' | Out-Null
    $cliHead = Get-GitLine @('-C', $cliRepo, 'rev-parse', 'HEAD')
    [System.IO.File]::WriteAllText(
        (Join-Path $env:FAKE_GH_DIR 'pr-view-88.json'),
        ('{"state":"MERGED","mergedAt":"2026-07-18T01:00:00Z","mergeCommit":{"oid":"' + $cliHead + '"},"headRefName":"feat/issue-840-x"}'))

    $reconcileOut = (& pwsh -NoProfile -File $Cleanup --phase reconcile --repo-dir $cliRepo --manifest $cliManifest --pr 88 2>$null | Out-String).Trim()
    $reconcileCode = $LASTEXITCODE
    Assert-Contains '"phase":"reconcile"' $reconcileOut 'S2 reconcile CLI writes its JSON to stdout'
    Assert-Contains '"state":"MERGED"' $reconcileOut 'S2 reconcile CLI reports the reconciled state'
    Assert-Equal '0' ([string]$reconcileCode) 'S2 reconcile CLI exits 0'
    # The trailing exit code must not be re-emitted as a second stdout line --
    # the single-element slice bug Split-CleanupCliResult guards against.
    Assert-Equal '1' ([string](@($reconcileOut -split "`n")).Count) 'S2 reconcile CLI stdout is exactly one line (exit code not re-emitted)'

    $cleanupOut = (& pwsh -NoProfile -File $Cleanup --phase cleanup --run-root $cliRoot --repo-dir $cliRepo --manifest $cliManifest --base $Base --issue 840 --merge-commit $cliHead 2>$null | Out-String).Trim()
    $cleanupCode = $LASTEXITCODE
    Assert-Contains '"state":"CLEANED"' $cleanupOut 'S2 cleanup CLI writes its CLEANED JSON to stdout'
    Assert-Equal '0' ([string]$cleanupCode) 'S2 cleanup CLI exits 0 on the happy path'
    Assert-PathMissing $cliRoot 'S2 cleanup CLI removed the run root'

    # A preserved run must also reach stdout, and must carry a non-zero status.
    $cliEarly = New-RunRoot $Base '840' 'clipreserve' $Remote
    workspace_manifest_write -Path (Join-Path $cliEarly 'manifest') -Key 'state' -Value 'PR_OPEN' | Out-Null
    $preserveOut = (& pwsh -NoProfile -File $Cleanup --phase cleanup --run-root $cliEarly --repo-dir (Join-Path $cliEarly 'repo') --manifest (Join-Path $cliEarly 'manifest') --base $Base --issue 840 2>$null | Out-String).Trim()
    $preserveCode = $LASTEXITCODE
    Assert-Contains '"state":"PRESERVED"' $preserveOut 'S2 a preserved cleanup CLI still writes JSON to stdout'
    Assert-Equal '1' ([string]$preserveCode) 'S2 a preserved cleanup CLI exits 1'

    Write-Host ""
    Write-Host "=== S1 (#847): non-zero git/gh exits stay data under a host that enabled the native EAP ==="
    # $PSNativeCommandUseErrorActionPreference is set BEFORE the script loads,
    # which is how a host with the setting enabled reaches it. The script pins it
    # $false at script scope; without that pin the direct `& $script:GitBin ...`
    # call sites below raise NativeCommandExitException under the 'Stop'
    # preference and a safety refusal becomes a crash.
    $s1Repo = Join-Path $Work 's1-no-remote'
    Invoke-GitOrDie @('init', '-q', '-b', 'develop', $s1Repo)
    Invoke-GitOrDie @('-C', $s1Repo, 'config', 'user.email', 'test@example.com')
    Invoke-GitOrDie @('-C', $s1Repo, 'config', 'user.name', 'test')
    [System.IO.File]::WriteAllText((Join-Path $s1Repo 'a.txt'), "a`n")
    Invoke-GitOrDie @('-C', $s1Repo, 'add', 'a.txt')
    Invoke-GitOrDie @('-C', $s1Repo, 'commit', '-q', '-m', 'a')
    $s1Sha = Get-GitLine @('-C', $s1Repo, 'rev-parse', 'HEAD')
    $s1Manifest = Join-Path $Work 's1-manifest'
    workspace_manifest_write -Path $s1Manifest -Key 'state' -Value 'PUSHED' | Out-Null

    $s1Child = Join-Path $Work 'child-native-eap.ps1'
    Set-Content -LiteralPath $s1Child -Value @'
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. $env:IW_CLEANUP_SCRIPT
[Console]::Out.WriteLine("PIN=$PSNativeCommandUseErrorActionPreference")
# `rev-parse @{u}` exits non-zero on a branch with no upstream.
[Console]::Out.WriteLine("NOUPSTREAM=" + (cleanup_remotely_recoverable -RepoDir $env:IW_S1_REPO))
# `merge-base --is-ancestor` exits non-zero when the sha is not an ancestor.
[Console]::Out.WriteLine("NOTANCESTOR=" + (cleanup_remotely_recoverable -RepoDir $env:IW_S1_REPO -MergeCommit $env:IW_S1_SHA))
# `gh pr view` on a missing PR exits non-zero, and `ls-remote origin` exits
# non-zero on a repo with no origin -- both are read as data by reconcile.
$result = cleanup_reconcile -RepoDir $env:IW_S1_REPO -Manifest $env:IW_MANIFEST -PrNumber 4242
foreach ($item in @($result)) {
    if ($item -isnot [int]) { [Console]::Out.WriteLine("JSON=" + [string]$item) }
}
[Console]::Out.WriteLine('DONE')
exit 0
'@
    # GH_BIN is pointed at git so `gh pr view ...` becomes `git pr view ...`: a
    # genuine NATIVE process exiting non-zero, which is what the pin has to
    # tolerate. The .ps1 double cannot serve here -- it runs in-process and so
    # never triggers native-command error promotion at all.
    $s1Run = Invoke-ChildPwsh $s1Child @{
        IW_CLEANUP_SCRIPT = $Cleanup
        IW_S1_REPO        = $s1Repo
        IW_S1_SHA         = $s1Sha
        IW_MANIFEST       = $s1Manifest
        GH_BIN            = 'git'
    }
    Assert-Equal '0' ([string]$s1Run.Code) 'S1 the run completes instead of dying on a non-zero git/gh exit'
    Assert-Contains 'PIN=False' $s1Run.StdOut 'S1 the script pins $PSNativeCommandUseErrorActionPreference back to $false'
    Assert-Contains 'NOUPSTREAM=False' $s1Run.StdOut 'S1 a missing upstream is a structured refusal, not an exception'
    Assert-Contains 'NOTANCESTOR=False' $s1Run.StdOut 'S1 a not-an-ancestor merge commit is a structured refusal'
    Assert-Contains 'JSON={"phase":"reconcile"' $s1Run.StdOut 'S1 reconcile still emits its outcome JSON when gh exits non-zero'
    Assert-Contains 'DONE' $s1Run.StdOut 'S1 every path ran to completion'
    Assert-NotContains 'NativeCommandExitException' $s1Run.StdErr 'S1 no NativeCommandExitException reaches stderr'
}
finally {
    foreach ($name in $SavedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $SavedEnv[$name]) }
    $env:IW_RM_COUNT = $null
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "  $Pass passed, $Fail failed$(if ($Skip -gt 0) { ", $Skip skipped" })"
if ($Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Failures:"
    foreach ($err in $Errors) { Write-Host "  $err" }
    exit 1
}
exit 0
