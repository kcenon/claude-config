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
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do echo "  $err"; done
    exit 1
fi
exit 0
