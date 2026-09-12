#!/bin/bash
# Verify the Anthropic installer sha256 pins against upstream (#936).
#
# Three checks. Each one runs even when an earlier one fails, so one run
# reports every problem:
#   parity       bootstrap.sh and scripts/install.sh carry the same bash pin
#                (the ANTHROPIC_INSTALLER_SHA256 default). No network.
#   install.sh   the bootstrap.sh pin matches https://claude.ai/install.sh.
#   install.ps1  the bootstrap.ps1 pin ($AnthropicInstallerSha256 default)
#                matches https://claude.ai/install.ps1.
#
# Usage: bash scripts/check-installer-pins.sh [--offline] [--root DIR]
#            [--sh-url URL] [--ps1-url URL]
#   --offline  read the pins and check parity only; download nothing
#   --root     repository to read (default: the one holding this script)
#   --sh-url, --ps1-url
#              upstream URLs (the tests pass file:// fixtures)
#
# Exit codes, first match wins:
#   1   drift: an upstream installer no longer matches its pin, or the two
#       bash pins differ. Review the upstream change and rotate the pin
#       ("Rotating the pin" in docs/SUPPLY_CHAIN.md).
#   2   a pin line could not be read. Fix the pin line or this script.
#   3   an upstream installer could not be downloaded. Re-run.
#   64  usage error.
#
# When GITHUB_STEP_SUMMARY is set, a Markdown table of the results is
# appended to it. Callers: .github/workflows/check-anthropic-installer.yml
# and tests/scripts/test-check-installer-pins.sh.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH_URL="https://claude.ai/install.sh"
PS1_URL="https://claude.ai/install.ps1"
OFFLINE=0

usage() {
    echo "usage: $0 [--offline] [--root DIR] [--sh-url URL] [--ps1-url URL]" >&2
    exit 64
}

while [ $# -gt 0 ]; do
    case "$1" in
        --offline) OFFLINE=1; shift ;;
        --root) [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --sh-url) [ $# -ge 2 ] || usage; SH_URL="$2"; shift 2 ;;
        --ps1-url) [ $# -ge 2 ] || usage; PS1_URL="$2"; shift 2 ;;
        *) usage ;;
    esac
done

# One capture group each: the 64-hex default on the pin line. Bracket
# expressions keep '$', '{' and '}' literal in every ERE implementation.
SQ="'"
BOOTSTRAP_SH_RE='^ANTHROPIC_INSTALLER_SHA256="[$][{]ANTHROPIC_INSTALLER_SHA256:-([0-9a-f]{64})[}]"'
INSTALL_SH_RE='^[[:space:]]*local installer_sha="[$][{]ANTHROPIC_INSTALLER_SHA256:-([0-9a-f]{64})[}]"'
BOOTSTRAP_PS1_RE="^[\$]AnthropicInstallerSha256[[:space:]]*=.*else[[:space:]]*[{][[:space:]]*${SQ}([0-9a-f]{64})${SQ}[[:space:]]*[}]"

DRIFT=0
UNREADABLE=0
FETCH_FAILED=0
ROWS=""

# Print the pin that RE captures in FILE. Fails unless exactly one line
# matches, so a duplicated or reshaped pin line is reported, not guessed.
extract_pin() {
    local file="$1" re="$2" line found="" count=0
    [ -f "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ $re ]]; then
            found="${BASH_REMATCH[1]}"
            count=$((count + 1))
        fi
    done < "$file"
    [ "$count" -eq 1 ] || return 1
    printf '%s\n' "$found"
}

sha256_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

# Print the sha256 of the bytes at URL. pipefail makes a failed download fail
# the pipeline, so the hash of an empty body is never reported as drift.
upstream_sha256() {
    curl -fsSL --retry 3 --retry-delay 5 --max-time 60 "$1" | sha256_stdin
}

# record CHECK PINNED COMPARED RESULT
record() {
    ROWS="${ROWS}| $1 | \`$2\` | \`$3\` | $4 |"$'\n'
}

annotate() {
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        echo "::error::$1"
    fi
}

report_unreadable() {
    UNREADABLE=1
    echo "$1: could not read exactly one pin line of the shape: $2" >&2
    annotate "$1: pin line unreadable"
}

BASH_PIN="$(extract_pin "$ROOT/bootstrap.sh" "$BOOTSTRAP_SH_RE")" || BASH_PIN=""
COPY_PIN="$(extract_pin "$ROOT/scripts/install.sh" "$INSTALL_SH_RE")" || COPY_PIN=""
PS1_PIN="$(extract_pin "$ROOT/bootstrap.ps1" "$BOOTSTRAP_PS1_RE")" || PS1_PIN=""

# shellcheck disable=SC2016  # the shapes are printed literally
{
    [ -n "$BASH_PIN" ] || report_unreadable "bootstrap.sh" 'ANTHROPIC_INSTALLER_SHA256="${ANTHROPIC_INSTALLER_SHA256:-<sha256>}"'
    [ -n "$COPY_PIN" ] || report_unreadable "scripts/install.sh" 'local installer_sha="${ANTHROPIC_INSTALLER_SHA256:-<sha256>}"'
    [ -n "$PS1_PIN" ] || report_unreadable "bootstrap.ps1" '$AnthropicInstallerSha256 = if (...) { ... } else { '"'<sha256>'"' }'
}

echo "== parity =="
PARITY_CHECK="bash pin parity: bootstrap.sh = scripts/install.sh"
if [ -z "$BASH_PIN" ] || [ -z "$COPY_PIN" ]; then
    echo "parity: skipped (pin unreadable)."
    record "$PARITY_CHECK" "${BASH_PIN:--}" "${COPY_PIN:--}" "not run: pin unreadable"
elif [ "$BASH_PIN" = "$COPY_PIN" ]; then
    echo "parity: bootstrap.sh and scripts/install.sh carry the same pin."
    record "$PARITY_CHECK" "$BASH_PIN" "$COPY_PIN" "pass"
else
    DRIFT=1
    {
        echo "parity: bootstrap.sh and scripts/install.sh carry different bash pins."
        echo "  bootstrap.sh:       $BASH_PIN"
        echo "  scripts/install.sh: $COPY_PIN"
        echo "Rotate both files in the same PR. See docs/SUPPLY_CHAIN.md."
    } >&2
    annotate "parity: bootstrap.sh and scripts/install.sh carry different bash pins"
    record "$PARITY_CHECK" "$BASH_PIN" "$COPY_PIN" "FAIL: pins differ"
fi

# check_upstream NAME CHECK PIN URL HINT
check_upstream() {
    local name="$1" check="$2" pin="$3" url="$4" hint="$5" actual
    echo "== $name =="
    if [ -z "$pin" ]; then
        echo "$name: skipped (pin unreadable)."
        record "$check" "-" "-" "not run: pin unreadable"
        return
    fi
    if [ "$OFFLINE" -eq 1 ]; then
        echo "$name: skipped (--offline)."
        record "$check" "$pin" "-" "not run: --offline"
        return
    fi
    if ! actual="$(upstream_sha256 "$url")"; then
        FETCH_FAILED=1
        echo "$name: could not download $url" >&2
        annotate "$name: could not download $url"
        record "$check" "$pin" "-" "FAIL: download failed"
        return
    fi
    echo "PINNED=$pin"
    echo "ACTUAL=$actual"
    if [ "$pin" = "$actual" ]; then
        echo "$name: sha256 pin matches upstream."
        record "$check" "$pin" "$actual" "pass"
    else
        DRIFT=1
        {
            echo "$name: sha256 drift detected."
            echo "  pinned: $pin"
            echo "  actual: $actual"
            echo "$hint"
        } >&2
        annotate "$name: sha256 drift detected (pinned $pin, actual $actual)"
        record "$check" "$pin" "$actual" "FAIL: drift"
    fi
}

check_upstream "install.sh" "install.sh: bootstrap.sh pin = upstream" "$BASH_PIN" "$SH_URL" \
    "Open a PR updating ANTHROPIC_INSTALLER_SHA256 in bootstrap.sh and scripts/install.sh after reviewing the upstream change. See docs/SUPPLY_CHAIN.md."
check_upstream "install.ps1" "install.ps1: bootstrap.ps1 pin = upstream" "$PS1_PIN" "$PS1_URL" \
    "Open a PR updating \$AnthropicInstallerSha256 in bootstrap.ps1 after reviewing the upstream change. See docs/SUPPLY_CHAIN.md."

if [ "$DRIFT" -eq 1 ]; then
    RC=1; MEANING="drift: review the upstream change and rotate the pin (docs/SUPPLY_CHAIN.md)"
elif [ "$UNREADABLE" -eq 1 ]; then
    RC=2; MEANING="a pin line could not be read: fix the pin line or scripts/check-installer-pins.sh"
elif [ "$FETCH_FAILED" -eq 1 ]; then
    RC=3; MEANING="an upstream installer could not be downloaded: re-run the workflow"
elif [ "$OFFLINE" -eq 1 ]; then
    RC=0; MEANING="pins readable and the bash pins agree; upstream not compared (--offline)"
else
    RC=0; MEANING="all pins match"
fi

echo "Result: exit $RC, $MEANING."

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "## Anthropic installer pins"
        echo ""
        echo "| Check | Pinned | Compared with | Result |"
        echo "|-------|--------|---------------|--------|"
        printf '%s' "$ROWS"
        echo ""
        echo "Exit $RC: $MEANING."
    } >> "$GITHUB_STEP_SUMMARY"
fi

exit "$RC"
