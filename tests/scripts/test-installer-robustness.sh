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
echo "[backup copy-then-swap staging (no wipe-before-copy)]"
check "backup.sh uses .new.\$\$ staging" "$(has scripts/backup.sh '.new.$$')"
check "backup.ps1 uses .new staging"     "$(has scripts/backup.ps1 '.new')"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do echo "  $err"; done
    exit 1
fi
exit 0
