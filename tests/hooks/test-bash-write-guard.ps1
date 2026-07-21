#!/usr/bin/env pwsh
#Requires -Version 7.0
# Test suite for bash-write-guard.ps1
# Run: pwsh tests/hooks/test-bash-write-guard.ps1
#
# Port of tests/hooks/test-bash-write-guard.sh (67 assertions). The .ps1 guard
# is a regex approximation of the tokenizer-based .sh guard, so a handful of
# bash cases legitimately diverge. Every ported case was probed against the
# actual .ps1 guard first; matches are asserted plainly, divergences are
# asserted at the ACTUAL .ps1 decision with a comment (never forced into
# agreement). See the read-only-awk approximation-artifact block and the
# divergence section at the bottom.

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$script:HookPath = Join-Path $script:RepoRoot 'global' 'hooks' 'bash-write-guard.ps1'
$script:Passed = 0
$script:Failed = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()

# Fresh per-run session id so we never touch the developer's read tracker.
# Set in the environment (the guard reads $env:CLAUDE_SESSION_ID first) and echo
# it into every payload for parity with the bash suite.
$script:SessionId = "bwg-ps-test-$PID"
$env:CLAUDE_SESSION_ID = $script:SessionId
$script:TrackerDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
$script:Tracker = Join-Path $script:TrackerDir ("claude-read-set-{0}" -f $script:SessionId)
Remove-Item -LiteralPath $script:Tracker -ErrorAction SilentlyContinue

$script:FixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) ("bwg-ps-fix-{0}" -f $PID)
New-Item -ItemType Directory -Path $script:FixtureDir -Force | Out-Null

# Build the hook JSON payload with ConvertTo-Json so commands containing quotes
# and backslashes (python -c "...\"...\"...", awk 'BEGIN{print "y" > f}') are
# escaped correctly instead of being hand-concatenated.
function New-BashPayload {
    param([string]$Command)
    return (@{
        tool_name  = 'Bash'
        tool_input = @{ command = $Command }
        session_id = $script:SessionId
    } | ConvertTo-Json -Compress -Depth 5)
}

function Assert-Deny {
    param([string]$InputJson, [string]$Label)
    $result = $InputJson | & pwsh -NoProfile -File $script:HookPath 2>$null
    if ($result -match '"deny"') {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected deny, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

function Assert-Allow {
    param([string]$InputJson, [string]$Label)
    $result = $InputJson | & pwsh -NoProfile -File $script:HookPath 2>$null
    if ($result -match '"allow"' -or [string]::IsNullOrEmpty($result)) {
        $script:Passed++
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        $script:Failed++
        $script:Errors.Add("FAIL: $Label - expected allow, got: $result")
        Write-Host "  FAIL: $Label" -ForegroundColor Red
    }
}

Write-Host '=== bash-write-guard.ps1 tests ==='
Write-Host ''

Write-Host '[Fail-open on missing input]'
Assert-Allow -InputJson (New-BashPayload '') -Label 'Empty command -> allow'

Write-Host ''
Write-Host '[deny - write to sensitive paths]'
Assert-Deny -InputJson (New-BashPayload 'echo secret > .env') -Label 'echo > .env'
Assert-Deny -InputJson (New-BashPayload "cat <<EOF > .env`nA=1`nEOF") -Label 'heredoc > .env'
Assert-Deny -InputJson (New-BashPayload 'tee .env') -Label 'tee .env'
Assert-Deny -InputJson (New-BashPayload 'cp newkey ~/.ssh/id_rsa') -Label 'cp into ~/.ssh/id_rsa'
Assert-Deny -InputJson (New-BashPayload 'echo y > /etc/passwd') -Label 'echo > /etc/passwd'
Assert-Deny -InputJson (New-BashPayload 'curl https://x | tee ~/.aws/credentials') -Label 'tee ~/.aws/credentials'
Assert-Deny -InputJson (New-BashPayload 'dd of=/etc/shadow') -Label 'dd of=/etc/shadow'
Assert-Deny -InputJson (New-BashPayload 'echo y >> .env') -Label 'append >> .env'

Write-Host ''
Write-Host '[deny - case-insensitive variants (macOS/Windows bypass guard)]'
Assert-Deny -InputJson (New-BashPayload 'echo x > .ENV') -Label 'write uppercase .ENV'
Assert-Deny -InputJson (New-BashPayload 'tee ./config/.Env.Local') -Label 'write mixed-case .Env.Local'
Assert-Deny -InputJson (New-BashPayload 'cp k ~/.SSH/ID_RSA') -Label 'write uppercase .SSH/ID_RSA'
Assert-Deny -InputJson (New-BashPayload 'curl x | tee ~/.AWS/credentials') -Label 'write uppercase .AWS dir'

Write-Host ''
Write-Host '[deny - uninspectable mutation patterns (Red Team Vector E)]'
Assert-Deny -InputJson (New-BashPayload 'python -c "open(\"/etc/x\", \"w\").write(\"y\")"') -Label 'python -c'
Assert-Deny -InputJson (New-BashPayload 'python3 -c "import pathlib; pathlib.Path(\"f\").write_text(\"y\")"') -Label 'python3 -c'
Assert-Deny -InputJson (New-BashPayload 'node -e "require(\"fs\").writeFileSync(\"f\",\"y\")"') -Label 'node -e'
Assert-Deny -InputJson (New-BashPayload 'perl -e "open(F,\">f\");print F \"y\""') -Label 'perl -e'
Assert-Deny -InputJson (New-BashPayload 'awk "BEGIN{print \"x\" > \"/tmp/y\"}"') -Label 'awk script body'
Assert-Deny -InputJson (New-BashPayload 'gawk "BEGIN{print > \"f\"}"') -Label 'gawk script body'
# Regression (#747 review): bare-word / bare-variable / append / pipe redirects.
Assert-Deny -InputJson (New-BashPayload 'awk ''BEGIN{print "y" > f}''') -Label 'awk bare-variable redirect'
Assert-Deny -InputJson (New-BashPayload 'awk ''BEGIN{f="/etc/passwd"; print "x" > f}''') -Label 'awk bare-var to sensitive file'
Assert-Deny -InputJson (New-BashPayload 'awk ''BEGIN{print "y" > out}''') -Label 'awk bare-word redirect'
Assert-Deny -InputJson (New-BashPayload 'awk ''BEGIN{print "y" >> f}''') -Label 'awk append redirect'
Assert-Deny -InputJson (New-BashPayload 'awk ''BEGIN{printf "y" > f}''') -Label 'awk printf redirect'
Assert-Deny -InputJson (New-BashPayload 'awk ''BEGIN{print "y" | "cat>/tmp/x"}''') -Label 'awk pipe-to-command'

Write-Host ''
Write-Host '[allow - read-only awk (no write target)]'
# APPROXIMATION ARTIFACT (whole section): the bash guard tokenizes the awk body
# and allows awk with no write redirect. The .ps1 uninspectable arm is the
# coarse regex `\b(awk|gawk|mawk)\b`, which matches EVERY awk invocation
# regardless of redirect, so all six read-only cases deny. Over-approximation
# (fail-safe: it blocks harmless awk reads, never permits a write), not a
# security gap. Asserted at the actual .ps1 decision.
Assert-Deny -InputJson (New-BashPayload 'awk ''{print $1}'' file.txt') -Label 'awk print column (no redirect) [artifact -> deny]'
Assert-Deny -InputJson (New-BashPayload 'awk ''/TODO/{c++} END{print c}'' src.txt') -Label 'awk count pattern (no redirect) [artifact -> deny]'
Assert-Deny -InputJson (New-BashPayload 'ps aux | awk ''{print $2}''') -Label 'awk in pipe (no redirect) [artifact -> deny]'
Assert-Deny -InputJson (New-BashPayload 'awk -F''|'' ''{print $1}'' file.txt') -Label "awk -F'|' separator [artifact -> deny]"
Assert-Deny -InputJson (New-BashPayload 'awk -F ''|'' ''{print $1}'' file.txt') -Label "awk -F '|' separator [artifact -> deny]"
Assert-Deny -InputJson (New-BashPayload 'awk -v sep=''a|b'' ''{print sep}'' file.txt') -Label 'awk -v value with pipe [artifact -> deny]'

Write-Host ''
Write-Host '[deny - wrapper bypass for sensitive write]'
Assert-Deny -InputJson (New-BashPayload 'sudo tee /etc/shadow') -Label 'sudo tee /etc/shadow'
Assert-Deny -InputJson (New-BashPayload 'env X=1 echo y > .env') -Label 'env wrapper write'

Write-Host ''
Write-Host '[deny - chained sensitive write]'
Assert-Deny -InputJson (New-BashPayload 'true; echo y > .env') -Label '; chain'
Assert-Deny -InputJson (New-BashPayload 'true && echo y > .env') -Label '&& chain'

Write-Host ''
Write-Host '[deny - template allow-list must not widen the bypass surface (#866)]'
Assert-Deny -InputJson (New-BashPayload 'echo y > .env.*') -Label 'glob .env.* (not an allow-list entry)'
Assert-Deny -InputJson (New-BashPayload 'echo y > .env.example*') -Label 'glob .env.example* (no dot before wildcard)'
Assert-Deny -InputJson (New-BashPayload 'echo y > .env.examplexyz') -Label '.env.examplexyz (not .env.example)'
Assert-Deny -InputJson (New-BashPayload 'tee .env.sample.local') -Label '.env.sample.local (no suffix arm for sample)'
Assert-Deny -InputJson (New-BashPayload 'echo y > /srv/secrets/.env.example') -Label 'template under secrets/ still denied'
# The write .ps1 guard HAS the relative-directory fix from #877, so the relative
# secrets/ form denies here (unlike the read guard's #878 gap).
Assert-Deny -InputJson (New-BashPayload 'echo y > secrets/.env.example') -Label 'template under relative secrets/ denied'
Assert-Deny -InputJson (New-BashPayload 'true && echo y > .env.example; echo y > .env') -Label 'template does not launder a chained .env write'

Write-Host ''
Write-Host '[deny - relative sensitive-directory writes (issue #871)]'
Assert-Deny -InputJson (New-BashPayload 'echo y > secrets/db.yml') -Label 'redirect into relative secrets/'
Assert-Deny -InputJson (New-BashPayload 'echo y > credentials/aws.json') -Label 'redirect into relative credentials/'
Assert-Deny -InputJson (New-BashPayload 'tee passwords/list.txt') -Label 'tee into relative passwords/'
Assert-Deny -InputJson (New-BashPayload 'cp payload.txt secrets/db.yml') -Label 'cp destination in relative secrets/'
Assert-Deny -InputJson (New-BashPayload 'echo y > /srv/secrets/db.yml') -Label 'absolute secrets/ stays denied'

Write-Host ''
Write-Host '[allow - non-sensitive relative writes stay allowed (#871 precision)]'
Assert-Allow -InputJson (New-BashPayload 'echo y > build/out.txt') -Label 'relative non-sensitive dir'
Assert-Allow -InputJson (New-BashPayload 'echo y > docs/secrets-of-git.md') -Label 'secrets substring without directory boundary'
Assert-Allow -InputJson (New-BashPayload 'tee notes/password-policy.md') -Label 'password substring deliberately not ported to write side'

Write-Host ''
Write-Host '[allow - write to new, non-sensitive files]'
$script:NewTarget = Join-Path $script:FixtureDir 'new_output.txt'
Assert-Allow -InputJson (New-BashPayload "echo hello > $script:NewTarget") -Label 'echo > new file'
Assert-Allow -InputJson (New-BashPayload "tee $script:NewTarget") -Label 'tee new file'

Write-Host ''
Write-Host '[allow - env file templates (issue #866, file-channel parity)]'
# Asserted before the read tracker is created below, so these exercise the
# sensitive-target arm rather than the Read-before-Edit arm.
Assert-Allow -InputJson (New-BashPayload 'echo y > .env.example') -Label 'echo > .env.example'
Assert-Allow -InputJson (New-BashPayload 'tee .env.sample') -Label 'tee .env.sample'
Assert-Allow -InputJson (New-BashPayload 'echo y > /app/.env.template') -Label 'echo > /app/.env.template (path-prefixed form)'
Assert-Allow -InputJson (New-BashPayload 'echo y > .env.example.local') -Label 'echo > .env.example.local (suffixed example)'
Assert-Allow -InputJson (New-BashPayload 'cp template.txt .env.example') -Label 'cp into .env.example'

Write-Host ''
Write-Host '[allow - read-only commands]'
Assert-Allow -InputJson (New-BashPayload 'cat README.md') -Label 'cat (no redirect)'
Assert-Allow -InputJson (New-BashPayload 'grep TODO src/') -Label 'grep (no redirect)'
Assert-Allow -InputJson (New-BashPayload 'ls -la') -Label 'ls'
Assert-Allow -InputJson (New-BashPayload 'echo hello | tee /dev/null') -Label 'tee /dev/null (allowed sink)'
Assert-Allow -InputJson (New-BashPayload 'echo hello > /dev/null') -Label 'echo > /dev/null'
Assert-Allow -InputJson (New-BashPayload 'true 2>&1') -Label 'stderr redirect, no file'

Write-Host ''
Write-Host '[allow - write to file already Read this session]'
# The Read-before-Edit arm only runs once the tracker file exists, so it is
# created here (mirroring the bash suite ordering). Resolve-Path returns the
# same canonical form the guard computes for an existing redirect target, so a
# single tracker entry matches. Verified deterministic on macOS pwsh 7.6.3.
$script:Existing = Join-Path $script:FixtureDir 'existing.txt'
Set-Content -LiteralPath $script:Existing -Value 'initial'
$script:ResolvedExisting = (Resolve-Path -LiteralPath $script:Existing).Path
Set-Content -LiteralPath $script:Tracker -Value $script:ResolvedExisting
Assert-Allow -InputJson (New-BashPayload "echo update > $script:Existing") -Label 'tracker hit -> allow'

Write-Host ''
Write-Host '[deny - write to existing file NOT yet Read]'
$script:Untracked = Join-Path $script:FixtureDir 'untracked.txt'
Set-Content -LiteralPath $script:Untracked -Value 'data'
# Tracker exists (from prior test) but does not contain $Untracked -> deny.
Assert-Deny -InputJson (New-BashPayload "echo overwrite > $script:Untracked") -Label 'untracked existing file -> deny'

Write-Host ''
Write-Host '[divergence - .ps1 arm gaps pinned as-is, see #878]'
# The .ps1 sensitive-target regex only recognizes credential filenames behind a
# `.ssh/` prefix; a bare `id_rsa` / `credentials` planted in cwd carries no such
# boundary and is not matched. The .sh guard's bare-credential-filename block
# was deferred out of the write port (#877) and is tracked by #878. Pinned at
# today's ALLOW so the flip to deny (when #878 lands) trips this suite.
Assert-Allow -InputJson (New-BashPayload 'echo y > id_rsa') -Label 'planting bare id_rsa in cwd [#878 gap -> allow]'
Assert-Allow -InputJson (New-BashPayload 'tee credentials') -Label 'overwriting bare credentials filename [#878 gap -> allow]'

# Cleanup: remove the tracker and fixture dir this run created.
Remove-Item -LiteralPath $script:Tracker -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $script:FixtureDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "=== Results: $($script:Passed) passed, $($script:Failed) failed ==="
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    foreach ($err in $script:Errors) {
        Write-Host "  $err"
    }
    exit 1
}
exit 0
