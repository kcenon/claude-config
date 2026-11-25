#!/bin/sh
# mktemp-sandbox-shim.sh
# A stand-in for mktemp that behaves like a sandbox which allows writes under
# $TMPDIR and denies the per-user temp directory (#1056). A suite copies it to
# a scratch directory as `mktemp` and puts that directory first on PATH.
#
#   - A call without a template, and a call with -t, fail as they do there:
#     on macOS both use /var/folders/<..>/T/ even when TMPDIR is set.
#   - A template under $TMPDIR goes to the real mktemp.
#   - With MKTEMP_SHIM_DENY_ALL=1 every call fails, as where even $TMPDIR is
#     not writable.
#
# MKTEMP_SHIM_REAL names the real mktemp. Each call is appended to
# MKTEMP_SHIM_LOG when that is set, so a suite can tell that the shim was used.

deny() {
    echo "mktemp: mkstemp failed on $1: Operation not permitted" >&2
    exit 1
}

[ -z "${MKTEMP_SHIM_LOG:-}" ] || echo "mktemp $*" >> "$MKTEMP_SHIM_LOG"

template=""
for arg in "$@"; do
    case "$arg" in
        -t*) deny "/var/folders/shim/T/tmp.XXXXXXXXXX" ;;
        -*) ;;
        *) template="$arg" ;;
    esac
done

[ -n "$template" ] || deny "/var/folders/shim/T/tmp.XXXXXXXXXX"
[ "${MKTEMP_SHIM_DENY_ALL:-}" != "1" ] || deny "$template"

tmpdir="${TMPDIR:-/tmp}"
case "$template" in
    "${tmpdir%/}"/*) exec "${MKTEMP_SHIM_REAL:?}" "$@" ;;
esac
deny "$template"
