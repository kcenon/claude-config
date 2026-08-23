#!/bin/bash
# test-installer-robustness.sh
# Guards the P1-C fixes (deep-audit-2026-05-29):
#   1. Per-platform settings-source parity: the PowerShell installers
#      (install.ps1, bootstrap.ps1) must ship global/settings.windows.json;
#      the bash installers (install.sh, bootstrap.sh) must ship
#      global/settings.json. A mismatch ships .sh hook commands to Windows
#      (or vice versa), which the target host cannot execute.
#   2. install.sh error() must be terminal (silent-data-loss fix): a failed
#      `cp ... || error` on the enterprise policy path must abort, not fall
#      through to a green success line.
#   3. backup.sh REPLACE blocks must use copy-then-swap staging so a failed
#      copy never leaves a wiped backup directory.
# Run: bash tests/scripts/test-installer-robustness.sh

PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1

check() {
    local label="$1" cond="$2"
    if [ "$cond" = "y" ]; then
        ((PASS++)); echo "  PASS: $label"
    else
        ((FAIL++)); ERRORS+=("FAIL: $label"); echo "  FAIL: $label"
    fi
}

has() { grep -qF -- "$2" "$1" && echo y || echo n; }
hasnot() { grep -qF -- "$2" "$1" && echo n || echo y; }

# has_in_ps_func <file> <powershell-function-name> <literal>
# PowerShell declares functions as `function Name {`, so has_in_func's
# `name() {` opener never matches one. Same reason for scoping: the assertions
# below would otherwise pass on text that lives elsewhere in install.ps1.
has_in_ps_func() {
    awk -v opener="function $2 {" '
        index($0, opener) == 1 { inside = 1 }
        inside { print }
        inside && $0 == "}" { exit }
    ' "$1" | grep -qF -- "$3" && echo y || echo n
}

# has_in_func <file> <shell-function-name> <literal>
# Whole-file `has` is not discriminating for idioms this repo already uses
# elsewhere: the project layer, for example, guards its helper load and
# restores MANIFEST_PATH with exactly the same lines. Scoping the search to one
# function body is what makes those assertions mean anything.
has_in_func() {
    awk -v opener="$2() {" '
        index($0, opener) == 1 { inside = 1 }
        inside { print }
        inside && $0 == "}" { exit }
    ' "$1" | grep -qF -- "$3" && echo y || echo n
}

echo "=== installer robustness tests ==="
echo ""
echo "[settings-source parity: PowerShell installers -> settings.windows.json]"
check "install.ps1 ships settings.windows.json"   "$(has scripts/install.ps1 'settings.windows.json')"
check "bootstrap.ps1 ships settings.windows.json" "$(has bootstrap.ps1 'settings.windows.json')"

echo ""
echo "[settings-source parity: bash installers -> settings.json (not windows)]"
check "install.sh ships global/settings.json"     "$(has scripts/install.sh 'global/settings.json')"
check "install.sh does NOT ship windows settings" "$(hasnot scripts/install.sh 'settings.windows.json')"
check "bootstrap.sh ships global/settings.json"   "$(has bootstrap.sh 'global/settings.json')"
check "bootstrap.sh does NOT ship windows settings" "$(hasnot bootstrap.sh 'settings.windows.json')"

echo ""
echo "[install.sh error() is terminal (silent-data-loss fix)]"
# The error() body must contain an exit so `cp || error` aborts.
if awk '/^error\(\)/{f=1} f&&/exit 1/{print;found=1} f&&/^}/{f=0} END{exit !found}' scripts/install.sh >/dev/null; then
    check "install.sh error() contains exit 1" y
else
    check "install.sh error() contains exit 1" n
fi

echo ""
echo "[backup.sh error() is terminal (residual silent-success fix)]"
# The initial backup-copy paths still call `cp || error`; error() itself must
# terminate so they cannot fall through to the following success message.
if awk '/^error\(\)/{f=1} f&&/exit 1/{print;found=1} f&&/^}/{f=0} END{exit !found}' scripts/backup.sh >/dev/null; then
    check "backup.sh error() contains exit 1" y
else
    check "backup.sh error() contains exit 1" n
fi

echo ""
echo "[backup copy-then-swap staging (no wipe-before-copy)]"
check "backup.sh uses .new.\$\$ staging" "$(has scripts/backup.sh '.new.$$')"
check "backup.ps1 uses .new staging"     "$(has scripts/backup.ps1 '.new')"

echo ""
echo "[enterprise layer is manifest-tracked on Windows (#903)]"
# The enterprise tree is the highest-precedence layer and was deployed with
# bare Copy-Item, so nothing could tell a stale deployment from a tampered one.
check "install.ps1 tracks enterprise CLAUDE.md"       "$(has scripts/install.ps1 "Invoke-ManifestTrackedCopy -Src \$enterpriseMd")"
check "install.ps1 tracks enterprise rules tree"      "$(has scripts/install.ps1 "Copy-ManifestTree -SourceDir \$sourceRules")"
check "install.ps1 no bare Copy-Item for enterprise"  "$(hasnot scripts/install.ps1 "Copy-Item -Path \$enterpriseMd")"
# A shared manifest would collide on the key `CLAUDE.md`, which the global root
# already tracks, so the enterprise root must get its own manifest file.
check "enterprise root gets its own manifest"         "$(has scripts/install.ps1 'MANIFEST_PATH = Join-Path $enterpriseDir')"
# A leaked MANIFEST_PATH would redirect the global manifest into the enterprise
# root, so the repoint has to be unwound even when the copy throws.
check "MANIFEST_PATH repoint is unwound in finally"   "$(awk '/MANIFEST_PATH = Join-Path \$enterpriseDir/{f=1} f&&/finally \{/{found=1} f&&/^\}/{f=0} END{exit !found}' scripts/install.ps1 >/dev/null && echo y || echo n)"
# Every exit path must record an outcome, or the summary reports paths that
# were never written.
check "summary reads the recorded install state"      "$(has scripts/install.ps1 'switch ($script:EnterpriseInstallState)')"
check "admin-gate exit records why it skipped"        "$(has scripts/install.ps1 "EnterpriseInstallState = 'skipped-not-admin'")"

echo ""
echo "[the enterprise block reports from measurement, not return values (#910)]"
# Previously only the rules copy was guarded, so a throw from the CLAUDE.md
# copy or the manifest write unwound past the function under
# ErrorActionPreference=Stop: state stayed 'skipped' and no summary printed.
check "enterprise copies have a catch, not just a finally" "$(has_in_ps_func scripts/install.ps1 Install-Enterprise 'Enterprise deployment failed')"
# Invoke-ManifestTrackedCopy returns true for a real copy, a no-op, AND a
# missing source, so the old success lines could not have been accurate.
check "CLAUDE.md copy result is not used for reporting"    "$(has_in_ps_func scripts/install.ps1 Install-Enterprise '$null = Invoke-ManifestTrackedCopy -Src $enterpriseMd')"
check "per-file report compares hashes"                    "$(has_in_ps_func scripts/install.ps1 Install-Enterprise 'Get-FileSha256 -Path $p.Dest')"
check "report distinguishes updated from already current"  "$(has_in_ps_func scripts/install.ps1 Install-Enterprise 'already current')"
check "a kept file is not reported as installed"           "$(has_in_ps_func scripts/install.ps1 Install-Enterprise "EnterpriseInstallState = 'installed-with-kept'")"
check "summary renders the kept-file state"                "$(has scripts/install.ps1 "'installed-with-kept' {")"
check "summary names each kept file"                       "$(has scripts/install.ps1 'foreach ($kept in $script:EnterpriseKeptFiles)')"

echo ""
echo "[user-facing entry points declare the PowerShell floor they need (#911)]"
# These scripts use the three-argument Join-Path (-AdditionalChildPath), which
# is PowerShell 6+ only. A `#Requires -Version 5.1` line admits an interpreter
# that cannot run them, turning a clear refusal into a mid-run parameter error
# after the user has already answered prompts.
for entry in bootstrap.ps1 scripts/install.ps1 scripts/backup.ps1 scripts/sync.ps1 scripts/verify.ps1; do
    check "$entry declares PowerShell 7" "$(has "$entry" '#Requires -Version 7.0')"
done
check "no entry point still declares 5.1" "$(grep -rl '#Requires -Version 5\.' --include='*.ps1' --include='*.psm1' . >/dev/null 2>&1 && echo n || echo y)"

echo ""
echo "[enterprise layer is manifest-tracked on POSIX (#906)]"
check "install.sh tracks enterprise CLAUDE.md"        "$(has scripts/install.sh 'manifest_copy_file "$BACKUP_DIR/enterprise/CLAUDE.md"')"
check "install.sh tracks enterprise rules tree"       "$(has scripts/install.sh 'manifest_copy_tree "$BACKUP_DIR/enterprise/rules"')"
check "install.sh no bare cp for enterprise CLAUDE.md" "$(hasnot scripts/install.sh 'cp "$BACKUP_DIR/enterprise/CLAUDE.md"')"
check "install.sh no bare cp -r for enterprise rules"  "$(hasnot scripts/install.sh 'cp -r "$BACKUP_DIR/enterprise/rules"')"
check "enterprise root gets its own manifest"          "$(has scripts/install.sh 'MANIFEST_PATH="$enterprise_dir/.install-manifest.json"')"
# install_enterprise runs before the global block sources the helper, and
# INSTALL_TYPE=4 never enters that block, so the guarded load is not optional.
check "install_enterprise sources the helper itself"   "$(has_in_func scripts/install.sh install_enterprise 'if ! type manifest_copy_file')"
# A leaked MANIFEST_PATH would redirect the whole ~/.claude manifest into the
# enterprise root, because install_enterprise runs first.
check "MANIFEST_PATH is restored afterwards"           "$(has_in_func scripts/install.sh install_enterprise 'MANIFEST_PATH="$previous_manifest_path"')"
check "elevation is opt-in via MANIFEST_ELEVATE"       "$(has scripts/install-manifest.sh '_manifest_run()')"
check "elevation defaults to a plain exec"             "$(has scripts/install-manifest.sh 'MANIFEST_ELEVATE:-')"
# The audit that motivated this must be able to hash the manifest unprivileged.
check "elevated manifest is left world-readable"       "$(has scripts/install.sh 'sudo chmod 644 "$MANIFEST_PATH"')"

echo ""
echo "[global payload parity against the claude-docker contract (#914)]"
# docs/CLAUDE_DOCKER_CONTRACT.md declares the ~/.claude/ subtree guaranteed
# after a full install from ANY of the four entry points, which is the promise
# #914 found broken for .claudeignore.
#
# What this is NOT: a payload-set comparison derived from the installers. That
# was the first attempt, and it does not survive a mutation check. Searching
# each script for a guaranteed name passes on `project/.claudeignore` too, and
# tightening it to a `global/`-qualified form then misses CLAUDE.md and
# commit-settings.md, which both installers deploy through a loop variable
# (`global/$gf`). Two languages, four copy idioms, and loop indirection put a
# reliable static payload diff out of reach; a green check that proves nothing
# is worse than an honest narrower one (the #910 lesson, inverted).
#
# So: a tripwire on the contract itself. If the guaranteed subtree gains or
# loses a top-level file, this fails and forces whoever changed the contract to
# extend the per-entry-point assertions below.
# No \xNN escapes in the awk pattern: mawk (the Ubuntu runner's awk) and gawk
# disagree about them, and in a UTF-8 locale gawk matches characters rather
# than bytes -- /^[\xe2][\x94][\x9c\x94]/ passed on Git Bash and failed on both
# CI runners. Structural rule instead, with the box-drawing literals passed in
# as plain strings for index(): a top-level entry carries the connector, has no
# vertical bar (that marks a nested line), and does not start with a space
# (that marks the last directory's children).
contract_top_level_files() {
    local conn vbar
    conn=$(printf '\342\224\200\342\224\200 ')
    vbar=$(printf '\342\224\202')
    awk -v conn="$conn" -v vbar="$vbar" '
        /^~\/\.claude\/$/ { inside = 1; next }
        inside && /^```/  { exit }
        inside && index($0, conn) > 0 && index($0, vbar) == 0 && substr($0, 1, 1) != " " { print }
    ' docs/CLAUDE_DOCKER_CONTRACT.md |
        grep -v '(' |
        sed -e 's/^[^ ]* //' -e 's/ *$//' |
        grep -v '/$' |
        LC_ALL=C sort -u
}

# `.full-suite-active` is absent by design: its line carries the "(optional
# probe)" parenthetical, and invariant #4 names install.{sh,ps1} as its only
# writers, so bootstrap not writing it is correct.
contract_names="$(contract_top_level_files | tr '\n' ' ' | sed -e 's/ *$//')"
check "contract subtree still lists exactly the files this test covers" \
    "$([ "$contract_names" = ".claudeignore CLAUDE.md commit-settings.md settings.json" ] && echo y || echo n)"

# The specific regression, pinned per entry point.
check "install.ps1 deploys global/.claudeignore"  "$(has scripts/install.ps1 'Join-Path $BackupDir "global/.claudeignore"')"
check "install.ps1 tracks it under key .claudeignore" "$(has scripts/install.ps1 '-Dest (Join-Path $claudeDir ".claudeignore") -Key ".claudeignore"')"
check "bootstrap.ps1 deploys global/.claudeignore" "$(has bootstrap.ps1 "Join-Path \$InstallDir 'global' '.claudeignore'")"
check "bootstrap.sh deploys global/.claudeignore"  "$(has bootstrap.sh '"$INSTALL_DIR/global/.claudeignore" "$CLAUDE_DIR/.claudeignore" ".claudeignore"')"
# tmux reads ~/.tmux.conf, which bootstrap installs; the ~/.claude/tmux.conf
# copy was read by nothing and had no Windows peer.
check "install.sh no longer copies tmux.conf to ~/.claude" "$(hasnot scripts/install.sh 'cp "$BACKUP_DIR/global/tmux.conf" "$HOME/.claude/"')"

echo ""
echo "[verifiers compare the settings profile the platform publishes (#914)]"
check "verify.ps1 selects settings.windows.json on Windows" "$(has scripts/verify.ps1 "if (\$IsWindows) { 'settings.windows.json' } else { 'settings.json' }")"
check "verify.sh selects the windows profile under MSYS"    "$(has scripts/verify.sh 'Windows_NT* | *MINGW* | *MSYS* | *CYGWIN*)')"
# A line comparison can never pass: the installer republishes settings.json
# through ConvertTo-Json / jq, so the deployed file is machine-serialized while
# the profile is hand-formatted.
check "verify.ps1 drops settings.json from the byte-wise loop" "$(hasnot scripts/verify.ps1 "@('CLAUDE.md', 'commit-settings.md', 'settings.json', '.claudeignore')")"
check "verify.sh drops settings.json from the byte-wise loop"  "$(hasnot scripts/verify.sh 'for f in CLAUDE.md commit-settings.md settings.json .claudeignore')"
check "verify.ps1 compares settings semantically"              "$(has scripts/verify.ps1 'function Test-SyncSettings')"
check "verify.sh compares settings semantically"               "$(has scripts/verify.sh 'check_sync_settings()')"
check "verify.ps1 canonicalises before comparing"              "$(has_in_ps_func scripts/verify.ps1 Test-SyncSettings 'ConvertTo-CanonicalJson')"
check "verify.sh canonicalises before comparing"               "$(has_in_func scripts/verify.sh check_sync_settings 'sort_keys=True')"
check "both verifiers compare permissions and hooks"           "$([ "$(has scripts/verify.ps1 "@('permissions', 'hooks')")" = y ] && [ "$(has scripts/verify.sh '("permissions", "hooks")')" = y ] && echo y || echo n)"

echo ""
echo "[settings.json publish preserves machine-local keys (#915)]"
# line_of <file> <literal> -- first matching line number, or 0.
line_of() {
    local n
    n=$(grep -nF -- "$2" "$1" | head -1 | cut -d: -f1)
    echo "${n:-0}"
}

# All four full-install entry points stage the repo profile and move it over
# the destination, so all four dropped the same keys. #914 is the standing
# lesson about fixing one entry point and calling it done.
check "install.ps1 merges local keys"    "$(has scripts/install.ps1 'Merge-LocalSettingsKeys -StagedPath $settingsTmp -LivePath $destSettings')"
check "bootstrap.ps1 merges local keys"  "$(has bootstrap.ps1 'Merge-LocalSettingsKeys -StagedPath $settingsTmp -LivePath $settingsDst')"
check "install.sh merges local keys"     "$(has scripts/install.sh 'merge_local_settings_keys "$settings_tmp" "$settings_dst"')"
check "bootstrap.sh merges local keys"   "$(has bootstrap.sh 'merge_local_settings_keys "$settings_tmp" "$settings_dst"')"

# before <file> <earlier-literal> <later-literal>
# Both must be present. Without the -gt 0 guard a missing "earlier" compares as
# line 0 and the assertion passes vacuously -- these four did exactly that on
# their first mutation check.
before() {
    local a b
    a=$(line_of "$1" "$2")
    b=$(line_of "$1" "$3")
    if [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -lt "$b" ]; then echo y; else echo n; fi
}

# Ordering is the whole contract: merge first, then inject policy, so the
# policy still wins on the keys it owns. Reversed, a stale local `language`
# would survive a policy change -- the property install.ps1:184-187 protects.
check "install.ps1 merges before the policy injection" \
    "$(before scripts/install.ps1 'Merge-LocalSettingsKeys' 'Update-ClaudeSettingsJson -SettingsPath $settingsTmp')"
check "bootstrap.ps1 merges before the policy injection" \
    "$(before bootstrap.ps1 'Merge-LocalSettingsKeys' 'Update-ClaudeSettingsJson -SettingsPath $settingsTmp')"
check "install.sh merges before the policy injection" \
    "$(before scripts/install.sh 'merge_local_settings_keys' 'update_claude_settings_json "$settings_tmp"')"
check "bootstrap.sh merges before the policy injection" \
    "$(before bootstrap.sh 'merge_local_settings_keys' 'update_claude_settings_json "$settings_tmp"')"

# The two implementations must agree on which keys the repo owns and which are
# runtime state, or a machine would keep different values depending on which
# installer last ran.
check "policy keys agree across implementations" \
    "$([ "$(has scripts/install-manifest.ps1 "@('language', 'permissions', 'hooks')")" = y ] && [ "$(has scripts/install-manifest.sh '["language","permissions","hooks"]')" = y ] && echo y || echo n)"
check "runtime keys agree across implementations" \
    "$([ "$(has scripts/install-manifest.ps1 "@('effortLevel')")" = y ] && [ "$(has scripts/install-manifest.sh '["effortLevel"]')" = y ] && echo y || echo n)"
# env is merged one level so a machine-local variable survives, but the repo
# still wins per key.
check "ps1 merges env one level"          "$(has_in_ps_func scripts/install-manifest.ps1 Merge-LocalSettingsKeys 'foreach ($e in $liveEnv.Value.PSObject.Properties)')"
check "sh merges env with repo winning"   "$(has_in_func scripts/install-manifest.sh merge_local_settings_keys '.env = (($lv.env // {}) * ($st.env // {}))')"
# jq on Git Bash emits CRLF, which would put a stray CR inside a reported key
# name; the JSON itself is unaffected.
check "sh strips CR from reported keys"   "$(has_in_func scripts/install-manifest.sh merge_local_settings_keys "tr -d '\\r'")"
# Silence was the original defect: four values vanished and the run printed a
# green success line.
check "install.ps1 reports what it preserved" "$(has scripts/install.ps1 'machine-local settings keys preserved')"
check "install.sh reports what it preserved"  "$(has scripts/install.sh 'machine-local settings keys preserved')"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do echo "  $err"; done
    exit 1
fi
exit 0
