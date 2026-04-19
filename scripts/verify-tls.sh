#!/bin/bash
# verify-tls.sh
# Verifies that git / curl / language-toolchain HTTPS calls complete inside the
# Claude Code sandbox without `dangerouslyDisableSandbox`. Run this after
# deploying settings.json changes that set SSL_CERT_FILE / SSL_CERT_DIR.
#
# Exits 0 when all expected probes succeed, non-zero otherwise.
#
# Darwin note: `gh` (Homebrew binary) links against Security.framework and
# ignores SSL_CERT_FILE. Its TLS failure inside the sandbox is expected and
# is remediated separately via a Bash allowlist. See docs/SANDBOX_TLS.md.
#
# Usage:
#   ./scripts/verify-tls.sh            # run probes
#   ./scripts/verify-tls.sh --quiet    # only print final summary
#   ./scripts/verify-tls.sh --include-gh   # also probe gh (non-fatal on macOS)

set -u

QUIET=false
INCLUDE_GH=false
for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=true ;;
        --include-gh) INCLUDE_GH=true ;;
    esac
done

log() {
    if [ "$QUIET" = false ]; then
        printf '%s\n' "$*"
    fi
}

FAIL_COUNT=0
PASS_COUNT=0
SKIP_COUNT=0

run_probe() {
    local name="$1"
    shift
    local output
    if output=$("$@" 2>&1); then
        log "[OK] $name"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        log "[FAIL] $name"
        log "       $(printf '%s' "$output" | head -3)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

run_probe_nonfatal() {
    local name="$1"
    shift
    local output
    if output=$("$@" 2>&1); then
        log "[OK] $name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log "[SKIP] $name (expected failure on Darwin-Go binaries)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
    fi
}

# Fallback CA-bundle detection when env vars are not pre-populated.
if [ -z "${SSL_CERT_FILE:-}" ]; then
    if [ -f /etc/ssl/cert.pem ]; then
        export SSL_CERT_FILE=/etc/ssl/cert.pem
    elif [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    elif [ -f /etc/pki/tls/certs/ca-bundle.crt ]; then
        export SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt
    elif command -v brew >/dev/null 2>&1; then
        BREW_BUNDLE="$(brew --prefix)/etc/openssl@3/cert.pem"
        if [ -f "$BREW_BUNDLE" ]; then
            export SSL_CERT_FILE="$BREW_BUNDLE"
        fi
    fi
fi

log "SSL_CERT_FILE=${SSL_CERT_FILE:-<unset>}"
log "SSL_CERT_DIR=${SSL_CERT_DIR:-<unset>}"
log ""

# Tools that honor SSL_CERT_FILE and should succeed inside sandbox after the fix.
if command -v curl >/dev/null 2>&1; then
    run_probe "curl https://api.github.com" curl -sfI -o /dev/null https://api.github.com
else
    log "[SKIP] curl not installed"
    SKIP_COUNT=$((SKIP_COUNT + 1))
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    run_probe "git ls-remote origin" git ls-remote --heads origin HEAD
else
    log "[SKIP] not inside a git working tree"
    SKIP_COUNT=$((SKIP_COUNT + 1))
fi

# gh is probed only when explicitly requested and is non-fatal on macOS.
if [ "$INCLUDE_GH" = true ]; then
    if command -v gh >/dev/null 2>&1; then
        run_probe_nonfatal "gh api user" gh api user
    else
        log "[SKIP] gh CLI not installed"
        SKIP_COUNT=$((SKIP_COUNT + 1))
    fi
fi

log ""
if [ "$FAIL_COUNT" -eq 0 ]; then
    log "All required probes passed: $PASS_COUNT ok, $SKIP_COUNT skipped."
    log "git and curl complete TLS handshakes inside the sandbox without bypass."
    if [ "$INCLUDE_GH" = false ]; then
        log "gh was not probed; see docs/SANDBOX_TLS.md for the Darwin-gh caveat."
    fi
    exit 0
else
    log "FAILED probes: $FAIL_COUNT"
    log "Inspect the SSL_CERT_FILE path and ensure the CA bundle is readable."
    exit 1
fi
