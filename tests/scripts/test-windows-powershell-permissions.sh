#!/bin/bash
# Regression test for Windows PowerShell permissions policy (issue #722).
# The Windows profile should allow routine read-only discovery commands while
# preserving sensitive-file denies and avoiding broad or state-changing
# PowerShell grants.

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

PYTHON=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "SKIP: python3/python not in PATH"
    exit 0
fi

"$PYTHON" - <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path("global/settings.windows.json")
settings = json.loads(settings_path.read_text(encoding="utf-8"))
perms = settings.get("permissions") or {}
allow = set(perms.get("allow") or [])
deny = set(perms.get("deny") or [])

required = {
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

forbidden = {
    "PowerShell(*)",
    "PowerShell(Get-Content:*)",
    "PowerShell(Set-Content:*)",
    "PowerShell(New-Item:*)",
    "PowerShell(Remove-Item:*)",
    "PowerShell(Invoke-Expression:*)",
    "PowerShell(Invoke-RestMethod:*)",
    "PowerShell(iex:*)",
    "PowerShell(gh pr create:*)",
    "PowerShell(gh pr edit:*)",
    "PowerShell(gh pr merge:*)",
    "PowerShell(gh pr close:*)",
    "PowerShell(gh pr review:*)",
    "PowerShell(gh issue create:*)",
    "PowerShell(gh issue edit:*)",
    "PowerShell(gh issue close:*)",
    "PowerShell(gh issue comment:*)",
    "PowerShell(gh workflow run:*)",
    "PowerShell(gh workflow enable:*)",
    "PowerShell(gh workflow disable:*)",
    "PowerShell(gh release create:*)",
    "PowerShell(gh release edit:*)",
    "PowerShell(gh release delete:*)",
    "PowerShell(gh release upload:*)",
}

required_deny = {
    "Read(.env)",
    "Read(**/.env)",
    "Read(**/secrets/**)",
    "Read(**/credentials/**)",
    "Read(**/*.pem)",
    "Read(**/*.key)",
    "Write(.env)",
    "Edit(.env)",
}

errors = []
missing = sorted(required - allow)
if missing:
    errors.append("missing required PowerShell allow entries: " + ", ".join(missing))

present_forbidden = sorted(forbidden & allow)
if present_forbidden:
    errors.append("forbidden broad/state-changing PowerShell allow entries present: " + ", ".join(present_forbidden))

missing_deny = sorted(required_deny - deny)
if missing_deny:
    errors.append("sensitive-file deny entries missing: " + ", ".join(missing_deny))

if perms.get("defaultMode") != "default":
    errors.append("permissions.defaultMode must remain default")
if perms.get("disableBypassPermissionsMode") != "disable":
    errors.append("disableBypassPermissionsMode must remain disable")
if perms.get("disableAutoMode") != "disable":
    errors.append("disableAutoMode must remain disable")
if settings.get("skipDangerousModePermissionPrompt") is not True:
    errors.append("skipDangerousModePermissionPrompt must remain true")

if errors:
    print("FAIL: Windows PowerShell permissions policy drift")
    for err in errors:
        print(f"  - {err}")
    sys.exit(1)

print("PASS: Windows PowerShell permissions allowlist is narrow and guardrails remain configured")
PY
