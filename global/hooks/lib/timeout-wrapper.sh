#!/bin/bash
# timeout-wrapper.sh
# Cross-platform timeout helper for hook scripts.
#
# Resolution order:
#   1. GNU timeout (Linux, BSD with coreutils)
#   2. gtimeout    (macOS Homebrew coreutils)
#   3. perl alarm  (universal fallback — perl ships with macOS by default)
#
# Exit-code contract matches GNU timeout:
#   - 124 when the wall-clock budget is exceeded
#   - otherwise the wrapped command's exit code
#
# Usage:
#   . "$LIB_DIR/timeout-wrapper.sh"
#   if OUTPUT=$(_run_with_timeout 10 gh pr checks "$PR_NUM" --json bucket); then
#       ...
#   else
#       rc=$?
#       [ "$rc" = "124" ] && handle_timeout || handle_gh_error "$rc"
#   fi

_run_with_timeout() {
    local secs="$1"
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "${secs}" "$@"
        return $?
    fi

    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "${secs}" "$@"
        return $?
    fi

    if command -v perl >/dev/null 2>&1; then
        # perl alarm fallback. The child runs in its own process group so a
        # single negative-pid kill cleans up grandchildren too — `gh` shells
        # out and `sleep`s, and SIGTERM to the immediate child alone leaves
        # those grandchildren running, which would block waitpid for the full
        # original duration. Exit 124 matches GNU timeout semantics.
        perl -e '
            use POSIX qw(setpgid);
            my $s = shift;
            my $pid = fork();
            if (!defined $pid) { exit 125; }
            if ($pid == 0) {
                setpgid(0, 0);
                exec @ARGV;
                exit 127;
            }
            setpgid($pid, $pid);
            local $SIG{ALRM} = sub {
                kill "-TERM", $pid;
                select(undef, undef, undef, 0.5);
                kill "-KILL", $pid;
                waitpid($pid, 0);
                exit 124;
            };
            alarm $s;
            waitpid $pid, 0;
            my $rc = $? >> 8;
            exit $rc;
        ' "${secs}" "$@"
        return $?
    fi

    # Last-resort pure-bash fallback. Less precise than perl alarm because
    # `wait` does not honour signal-driven exit codes uniformly across shells,
    # but keeps the hook functional on minimal containers (busybox-style).
    "$@" &
    local cmd_pid=$!
    (
        sleep "${secs}"
        kill -TERM "$cmd_pid" 2>/dev/null
        sleep 1
        kill -KILL "$cmd_pid" 2>/dev/null
    ) &
    local timer_pid=$!
    if wait "$cmd_pid" 2>/dev/null; then
        local rc=0
    else
        local rc=$?
    fi
    kill -TERM "$timer_pid" 2>/dev/null
    wait "$timer_pid" 2>/dev/null
    # Bash sets rc=143 (128+SIGTERM) when the child was killed. Normalize to
    # 124 so callers can branch on a single sentinel value.
    [ "$rc" = "143" ] || [ "$rc" = "137" ] && rc=124
    return "$rc"
}
