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
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do echo "  $err"; done
    exit 1
fi
exit 0
