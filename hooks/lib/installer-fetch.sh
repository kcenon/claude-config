#!/bin/bash
# installer-fetch.sh — shared download/verify/run helper for install entry points.
#
# Single source of truth for the supply-chain hardening contract used by:
#   - bootstrap.sh         (one-line installer)
#   - scripts/install.sh   (manual installer, ensure_claude_cli)
#   - bootstrap.ps1 calls Invoke-InstallerFetchVerifyRun in InstallerFetch.psm1
#     which mirrors this contract (#620).
#
# Contract:
#   1. Download the URL to a fresh mktemp file.
#   2. Verify sha256 against an expected pinned value.
#   3. On match: run with bash and clean up the temp file.
#   4. On mismatch / download fail / sha256sum unavailable: abort with a
#      typed exit code that callers can branch on.
#
# Exit codes:
#    0  OK           installer ran successfully
#   10  DOWNLOAD     curl/wget failed or both unavailable
#   11  CHECKSUM     sha256sum unavailable on the host
#   12  MISMATCH     sha256 did not match the pinned value
#   13  RUN          installer was launched but exited non-zero
#
# Usage:
#   source hooks/lib/installer-fetch.sh
#   installer_fetch_verify_run \
#       "https://claude.ai/install.sh" \
#       "b315b46925a9bfb9422f2503dd5aa649f680832f4c076b22d87c39d578c3d830" \
#       "claude-installer"
#
# Caller-provided UX functions (info, warning, success, error) are honored if
# defined; otherwise the lib falls back to plain printf to stderr/stdout so
# scripts that source the lib without a UI veneer still get readable output.
#
# IFV_ prefix on every internal name keeps the lib safe to source alongside
# the rest of the bootstrap state.

# Resolve UX hooks. Use parameter-substitution checks against `command -v` so
# we honor both function declarations and shell builtins/aliases the caller
# may have set up.
ifv_info()    { if command -v info    >/dev/null 2>&1; then info    "$@"; else printf '  %s\n' "$*"; fi; }
ifv_warn()    { if command -v warning >/dev/null 2>&1; then warning "$@"; else printf '  %s\n' "$*" >&2; fi; }
ifv_ok()      { if command -v success >/dev/null 2>&1; then success "$@"; else printf '  %s\n' "$*"; fi; }

# installer_fetch_verify_run <url> <expected_sha256> <label>
# Exits the calling shell only on success of the underlying installer; any
# error path returns a non-zero status the caller can act on.
installer_fetch_verify_run() {
    local url="$1"
    local expected_sha="$2"
    local label="${3:-installer}"

    if [ -z "$url" ] || [ -z "$expected_sha" ]; then
        ifv_warn "${label}: installer_fetch_verify_run requires <url> <sha256> <label>"
        return 64
    fi

    # Step 1 — download to mktemp. mktemp guarantees a unique path so two
    # parallel installs do not race on the same target.
    local tmp
    tmp="$(mktemp -t "${label}.XXXXXX")"
    # The cleanup trap fires regardless of how the function exits; the temp
    # file never lingers in /tmp even on sha mismatch or interrupt. We use a
    # subshell-local trap (RETURN) so the caller's own EXIT trap is undisturbed.
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN

    ifv_info "${label}: downloading ${url}"
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$url" -o "$tmp"; then
            ifv_warn "${label}: download failed via curl"
            return 10
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$tmp" "$url"; then
            ifv_warn "${label}: download failed via wget"
            return 10
        fi
    else
        ifv_warn "${label}: neither curl nor wget is available"
        return 10
    fi

    # Step 2 — sha256 verification. sha256sum is part of coreutils and ships
    # on every distro; macOS users without coreutils get a clear message.
    if ! command -v sha256sum >/dev/null 2>&1; then
        ifv_warn "${label}: sha256sum not found — cannot verify integrity"
        ifv_warn "  install coreutils (Linux) or 'brew install coreutils' (macOS)"
        return 11
    fi

    ifv_info "${label}: verifying sha256 (pin ${expected_sha:0:12}...)"
    if ! printf '%s  %s\n' "$expected_sha" "$tmp" | sha256sum -c - >/dev/null 2>&1; then
        local actual
        actual="$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')"
        ifv_warn "${label}: sha256 mismatch — installer aborted"
        ifv_warn "  expected: $expected_sha"
        ifv_warn "  actual:   ${actual:-<unknown>}"
        ifv_warn "  Anthropic may have rotated the script; wait for a maintainer re-pin."
        return 12
    fi
    ifv_ok "${label}: sha256 verified"

    # Step 3 — run.
    ifv_info "${label}: running installer"
    if ! bash "$tmp"; then
        ifv_warn "${label}: installer exited non-zero"
        return 13
    fi
    return 0
}
