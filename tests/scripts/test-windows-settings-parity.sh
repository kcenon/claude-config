#!/bin/bash
# Settings parity contract for global/settings.json and
# global/settings.windows.json (#821). Hook wiring has its own tuple-level
# test in test-windows-hooks-parity.sh; this gate covers the surrounding
# settings surface that can otherwise drift silently.
#
# Run: bash tests/scripts/test-windows-settings-parity.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

UNIX_JSON="global/settings.json"
WIN_JSON="global/settings.windows.json"

if [ ! -f "$UNIX_JSON" ] || [ ! -f "$WIN_JSON" ]; then
    echo "FAIL: settings files missing" >&2
    exit 1
fi

PYTHON=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "SKIP: python3/python not in PATH"
    exit 0
fi

"$PYTHON" - <<'PY' "$UNIX_JSON" "$WIN_JSON"
import json
import sys
from pathlib import Path

unix_path = Path(sys.argv[1])
win_path = Path(sys.argv[2])
unix_settings = json.loads(unix_path.read_text(encoding="utf-8"))
win_settings = json.loads(win_path.read_text(encoding="utf-8"))

errors = []


def report_set_drift(label, only_unix, only_win):
    if only_unix:
        errors.append(f"{label} only in {unix_path.name}: {', '.join(sorted(only_unix))}")
    if only_win:
        errors.append(f"{label} only in {win_path.name}: {', '.join(sorted(only_win))}")


def require_no_duplicates(label, values):
    seen = set()
    duplicates = sorted({value for value in values if value in seen or seen.add(value)})
    if duplicates:
        errors.append(f"{label} contains duplicate entries: {', '.join(duplicates)}")


# Top-level fields must remain shape-compatible. Platform-specific behavior
# belongs in values, not in missing keys.
report_set_drift(
    "top-level key",
    set(unix_settings) - set(win_settings),
    set(win_settings) - set(unix_settings),
)


# Windows intentionally omits POSIX CA-bundle environment variables; gh and
# PowerShell use the Windows certificate store directly.
env_unix_only_allow = {"SSL_CERT_FILE", "SSL_CERT_DIR"}
env_win_only_allow = set()
unix_env = unix_settings.get("env") or {}
win_env = win_settings.get("env") or {}
report_set_drift(
    "env key",
    (set(unix_env) - set(win_env)) - env_unix_only_allow,
    (set(win_env) - set(unix_env)) - env_win_only_allow,
)
for key in sorted(set(unix_env) & set(win_env)):
    if unix_env[key] != win_env[key]:
        errors.append(
            f"env value drift for {key}: {unix_path.name}={unix_env[key]!r}, "
            f"{win_path.name}={win_env[key]!r}"
        )


unix_perms = unix_settings.get("permissions") or {}
win_perms = win_settings.get("permissions") or {}
for key in ("defaultMode", "disableBypassPermissionsMode", "disableAutoMode"):
    if unix_perms.get(key) != win_perms.get(key):
        errors.append(
            f"permissions.{key} drift: {unix_path.name}={unix_perms.get(key)!r}, "
            f"{win_path.name}={win_perms.get(key)!r}"
        )

unix_deny = unix_perms.get("deny") or []
win_deny = win_perms.get("deny") or []
require_no_duplicates(f"{unix_path.name} permissions.deny", unix_deny)
require_no_duplicates(f"{win_path.name} permissions.deny", win_deny)
report_set_drift(
    "permissions.deny entry",
    set(unix_deny) - set(win_deny),
    set(win_deny) - set(unix_deny),
)


unix_allow = unix_perms.get("allow") or []
win_allow = win_perms.get("allow") or []
require_no_duplicates(f"{unix_path.name} permissions.allow", unix_allow)
require_no_duplicates(f"{win_path.name} permissions.allow", win_allow)

unix_bash_allow = {entry for entry in unix_allow if entry.startswith("Bash(")}
win_bash_allow = {entry for entry in win_allow if entry.startswith("Bash(")}
report_set_drift(
    "Bash permissions.allow entry",
    unix_bash_allow - win_bash_allow,
    win_bash_allow - unix_bash_allow,
)

win_powershell_allow = {entry for entry in win_allow if entry.startswith("PowerShell(")}
expected_win_powershell_allow = {
    "PowerShell(Get-ChildItem:*)",
    "PowerShell(Test-Path:*)",
    "PowerShell(Select-Object:*)",
    "PowerShell(Select-String:*)",
    "PowerShell(Write-Output:*)",
    "PowerShell(git status:*)",
    "PowerShell(git log:*)",
    "PowerShell(git diff:*)",
    "PowerShell(git show:*)",
    "PowerShell(git branch:*)",
    "PowerShell(git tag:*)",
    "PowerShell(git remote:*)",
    "PowerShell(git ls-files:*)",
    "PowerShell(git rev-parse:*)",
    "PowerShell(git describe:*)",
    "PowerShell(git for-each-ref:*)",
    "PowerShell(git worktree list:*)",
    "PowerShell(gh pr view:*)",
    "PowerShell(gh pr list:*)",
    "PowerShell(gh pr diff:*)",
    "PowerShell(gh pr checks:*)",
    "PowerShell(gh pr status:*)",
    "PowerShell(gh issue view:*)",
    "PowerShell(gh issue list:*)",
    "PowerShell(gh issue status:*)",
    "PowerShell(gh run view:*)",
    "PowerShell(gh run list:*)",
    "PowerShell(gh workflow list:*)",
    "PowerShell(gh workflow view:*)",
    "PowerShell(gh repo view:*)",
    "PowerShell(gh release view:*)",
    "PowerShell(gh release list:*)",
    "PowerShell(gh auth status:*)",
    "PowerShell(gh api -X GET:*)",
    "PowerShell(gh api -H *:*)",
    "PowerShell(gh api repos/*:*)",
    "PowerShell(gh api orgs/*:*)",
    "PowerShell(gh api users/*:*)",
    "PowerShell(gh api user:*)",
    "PowerShell(gh api rate_limit:*)",
    "PowerShell(gh api graphql:*)",
}
report_set_drift(
    "Windows PowerShell permissions.allow exception",
    expected_win_powershell_allow - win_powershell_allow,
    win_powershell_allow - expected_win_powershell_allow,
)

unexpected_unix_non_bash = sorted(entry for entry in unix_allow if not entry.startswith("Bash("))
if unexpected_unix_non_bash:
    errors.append(
        f"{unix_path.name} permissions.allow has non-Bash entries without an allow-list: "
        + ", ".join(unexpected_unix_non_bash)
    )

unexpected_win_non_shell = sorted(
    entry
    for entry in win_allow
    if not entry.startswith("Bash(") and not entry.startswith("PowerShell(")
)
if unexpected_win_non_shell:
    errors.append(
        f"{win_path.name} permissions.allow has unknown shell entries: "
        + ", ".join(unexpected_win_non_shell)
    )

if errors:
    print("FAIL: settings parity drift between settings.json and settings.windows.json")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print("PASS: settings parity contract between settings.json and settings.windows.json")
PY
