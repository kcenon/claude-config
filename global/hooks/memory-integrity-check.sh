#!/usr/bin/env bash
# memory-integrity-check.sh
# SessionStart hook: prints a brief memory health summary at session start.
# Reads ~/.claude/memory-shared/ metadata only -- no network, no validators.
#
# Hook Type: SessionStart (sync)
# Exit codes: 0 always (SessionStart must never block the session)
# Output prefix: [memory]
#
# Silent (no stdout) when the system is healthy AND no recent activity AND
# no unread alerts AND last sync within 24 hours.
#
# Performance budget: < 300ms typical; hard cap 500ms with warning.
# Bash 3.2 compatible (macOS default): no mapfile, no associative arrays,
# BASH_REMATCH save-then-use, ${var:-0} guards, wc output normalization.
#
# Issue: kcenon/claude-config#522 (Phase D engine).

set -u

# --- Constants ---------------------------------------------------------------

MEMORY_SHARED_DIR="${MEMORY_SHARED_DIR:-${HOME}/.claude/memory-shared}"
MEMORIES_DIR="${MEMORY_SHARED_DIR}/memories"
QUARANTINE_DIR="${MEMORY_SHARED_DIR}/quarantine"
ALERTS_LOG="${MEMORY_ALERTS_LOG:-${HOME}/.claude/logs/memory-alerts.log}"
ALERTS_READ_MARK="${MEMORY_ALERTS_READ_MARK:-${HOME}/.claude/.memory-alerts-read-mark}"

# Thresholds (seconds).
RECENT_SECS=86400          # 24h
STALE_SECS=7776000         # 90d
SYNC_STALE_SECS=86400      # 24h triggers warning per epic R1 mitigation
PERF_WARN_MS=500           # hard cap

# --- Setup -------------------------------------------------------------------

# SessionStart hook receives JSON on stdin; ignore it (the hook does not need
# event payload to compute memory health). Drain stdin to avoid SIGPIPE on
# very small inputs from the harness.
if [ -t 0 ]; then
    : # no stdin
else
    cat >/dev/null 2>&1 || true
fi

# Capture start time for performance budget.
if command -v date >/dev/null 2>&1; then
    START_EPOCH="$(date +%s 2>/dev/null || echo 0)"
else
    START_EPOCH=0
fi

# Bail silently if the memory system is not deployed yet (first-ever session
# before #525 migration).
if [ ! -d "$MEMORY_SHARED_DIR" ]; then
    exit 0
fi

# --- Helpers -----------------------------------------------------------------

# Read a single-line YAML field from frontmatter text. Echoes the raw value
# (without the `key:` prefix); empty string when the key is absent.
get_field() {
    local fm="$1"
    local key="$2"
    printf '%s\n' "$fm" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//"
}

# Strip surrounding double or single quotes from a YAML scalar value.
strip_quotes() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    if [[ "$v" =~ ^\"(.*)\"$ ]]; then
        local m="${BASH_REMATCH[1]}"
        v="$m"
    elif [[ "$v" =~ ^\'(.*)\'$ ]]; then
        local m="${BASH_REMATCH[1]}"
        v="$m"
    fi
    printf '%s' "$v"
}

# Convert ISO 8601 (UTC) date-time to epoch seconds. Echoes empty on failure.
# Accepts: 2026-04-30T12:34:56Z, 2026-04-30, 2026-04-30 12:34:56.
iso_to_epoch() {
    local iso="$1"
    [ -z "$iso" ] && { printf ''; return; }
    iso="$(strip_quotes "$iso")"
    # Normalize: strip trailing Z, replace T with space.
    iso="${iso%Z}"
    iso="${iso/T/ }"
    # GNU date (Linux) understands -d; BSD date (macOS) needs -j -f.
    local epoch=""
    epoch="$(date -u -d "$iso" +%s 2>/dev/null)" || true
    if [ -z "$epoch" ]; then
        # Try macOS BSD date with explicit format. Two common formats.
        epoch="$(date -u -j -f '%Y-%m-%d %H:%M:%S' "$iso" +%s 2>/dev/null)" || true
        if [ -z "$epoch" ]; then
            epoch="$(date -u -j -f '%Y-%m-%d' "${iso% *}" +%s 2>/dev/null)" || true
        fi
    fi
    printf '%s' "$epoch"
}

# Format seconds as a human-readable "ago" string.
time_ago() {
    local secs="${1:-0}"
    if [ "$secs" -lt 60 ]; then
        printf '%d sec ago' "$secs"
    elif [ "$secs" -lt 3600 ]; then
        printf '%d min ago' "$((secs / 60))"
    elif [ "$secs" -lt 86400 ]; then
        printf '%d hr ago' "$((secs / 3600))"
    else
        printf '%d days ago' "$((secs / 86400))"
    fi
}

# Read a memory file's frontmatter into stdout. Echoes empty on failure.
read_frontmatter() {
    local f="$1"
    [ -f "$f" ] || { printf ''; return; }
    [ -r "$f" ] || { printf ''; return; }
    local first_line
    first_line="$(head -1 "$f" 2>/dev/null)"
    [ "$first_line" = "---" ] || { printf ''; return; }
    local fm_end
    fm_end="$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR; exit}' "$f" 2>/dev/null)"
    fm_end="${fm_end:-}"
    [ -n "$fm_end" ] || { printf ''; return; }
    sed -n "2,$((fm_end - 1))p" "$f" 2>/dev/null
}

# --- Counts by trust-level ---------------------------------------------------

count_verified=0
count_inferred=0
count_other=0   # files in memories/ with missing or unrecognized trust-level
count_quarantined=0
count_total=0
recent_names=()
stale_names=()

now_epoch="${START_EPOCH:-0}"
[ "$now_epoch" = "0" ] && now_epoch="$(date +%s 2>/dev/null || echo 0)"

if [ -d "$MEMORIES_DIR" ]; then
    # Bash 3.2: no nullglob; guard against literal pattern when empty.
    for f in "$MEMORIES_DIR"/*.md; do
        [ -f "$f" ] || continue
        # Skip MEMORY.md auto-generated index per spec.
        local_base="$(basename "$f")"
        [ "$local_base" = "MEMORY.md" ] && continue

        count_total=$((count_total + 1))
        fm="$(read_frontmatter "$f")"
        if [ -z "$fm" ]; then
            # Frontmatter parse failure: log to stderr (not stdout) and skip
            # in counts. Hook must never pollute session start with errors.
            printf '[memory] warning: cannot parse frontmatter: %s\n' "$local_base" >&2
            continue
        fi

        tl="$(get_field "$fm" "trust-level")"
        tl="$(strip_quotes "$tl")"
        case "$tl" in
            verified)   count_verified=$((count_verified + 1)) ;;
            inferred)   count_inferred=$((count_inferred + 1)) ;;
            quarantined) count_quarantined=$((count_quarantined + 1)) ;;
            *)          count_other=$((count_other + 1)) ;;
        esac

        # Recent: created-at within last 24h.
        ca="$(get_field "$fm" "created-at")"
        if [ -n "$ca" ]; then
            ca_epoch="$(iso_to_epoch "$ca")"
            if [ -n "$ca_epoch" ] && [ "$now_epoch" != "0" ]; then
                age=$((now_epoch - ca_epoch))
                if [ "$age" -ge 0 ] && [ "$age" -lt "$RECENT_SECS" ]; then
                    # Use filename stem without .md as the human label.
                    rec_name="${local_base%.md}"
                    recent_names+=("$rec_name")
                fi
            fi
        fi

        # Stale: verified memory whose last-verified > 90d ago. Per spec,
        # missing last-verified on a verified memory counts as stale.
        if [ "$tl" = "verified" ]; then
            lv="$(get_field "$fm" "last-verified")"
            stale_name="${local_base%.md}"
            if [ -z "$lv" ]; then
                stale_names+=("$stale_name")
            else
                lv_epoch="$(iso_to_epoch "$lv")"
                if [ -n "$lv_epoch" ] && [ "$now_epoch" != "0" ]; then
                    if [ $((now_epoch - lv_epoch)) -ge "$STALE_SECS" ]; then
                        stale_names+=("$stale_name")
                    fi
                fi
            fi
        fi
    done
fi

# Count files in quarantine/ directory in addition to in-tree quarantined.
if [ -d "$QUARANTINE_DIR" ]; then
    for f in "$QUARANTINE_DIR"/*.md; do
        [ -f "$f" ] || continue
        count_quarantined=$((count_quarantined + 1))
    done
fi

# --- Last-sync time + source machine via git log -----------------------------

sync_secs_ago=""
sync_host=""
sync_warn=0
git_failed=0
if command -v git >/dev/null 2>&1 && [ -d "${MEMORY_SHARED_DIR}/.git" ]; then
    # %ct = committer timestamp (epoch); %an = author name (used as host hint
    # when commits set user.name = host name, which is the convention #520 uses).
    sync_line="$(git -C "$MEMORY_SHARED_DIR" log -1 --format='%ct|%an' 2>/dev/null)"
    if [ -n "$sync_line" ] && [[ "$sync_line" =~ ^([0-9]+)\|(.*)$ ]]; then
        sync_epoch="${BASH_REMATCH[1]}"
        sync_host="${BASH_REMATCH[2]}"
        if [ "$now_epoch" != "0" ]; then
            sync_secs_ago=$((now_epoch - sync_epoch))
            if [ "$sync_secs_ago" -ge "$SYNC_STALE_SECS" ]; then
                sync_warn=1
            fi
        fi
    else
        git_failed=1
    fi
else
    # Memory-shared exists but is not a git clone; treat as readable-but-no-sync.
    git_failed=1
fi

# --- Unread alerts -----------------------------------------------------------

unread_count=0
unread_recent_msg=""
if [ -f "$ALERTS_LOG" ] && [ -r "$ALERTS_LOG" ]; then
    # Read-mark file holds an epoch second; missing => everything is unread.
    read_mark_epoch=0
    if [ -f "$ALERTS_READ_MARK" ] && [ -r "$ALERTS_READ_MARK" ]; then
        rm_raw="$(head -1 "$ALERTS_READ_MARK" 2>/dev/null)"
        # Accept either bare epoch or ISO datetime.
        if [[ "$rm_raw" =~ ^[0-9]+$ ]]; then
            read_mark_epoch="$rm_raw"
        else
            converted="$(iso_to_epoch "$rm_raw")"
            [ -n "$converted" ] && read_mark_epoch="$converted"
        fi
    fi

    # Each log line per #524 spec:
    #   <ISO timestamp> <severity> <hash> <message>
    # Tail the last 200 lines (alerts log is small) and count unread entries.
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # Parse ISO timestamp (first whitespace-separated token).
        ts_token="${line%% *}"
        rest="${line#* }"
        ts_epoch="$(iso_to_epoch "$ts_token")"
        if [ -z "$ts_epoch" ]; then
            continue
        fi
        if [ "$ts_epoch" -gt "$read_mark_epoch" ]; then
            unread_count=$((unread_count + 1))
            # The "rest" begins with severity, then hash, then message.
            sev="${rest%% *}"
            after_sev="${rest#* }"
            hash_token="${after_sev%% *}"
            msg="${after_sev#* }"
            # Best-effort: keep latest message for headline.
            unread_recent_msg="$msg"
            # Suppress unused-var warnings for sev/hash_token under set -u.
            : "$sev" "$hash_token"
        fi
    done < <(tail -n 200 "$ALERTS_LOG" 2>/dev/null)
fi

# --- Decide whether to emit summary ------------------------------------------

emit=0
if [ ${#recent_names[@]} -gt 0 ]; then emit=1; fi
if [ ${#stale_names[@]} -gt 0 ]; then emit=1; fi
if [ "$sync_warn" = "1" ]; then emit=1; fi
if [ "$unread_count" -gt 0 ]; then emit=1; fi
if [ "$count_quarantined" -gt 0 ]; then emit=1; fi
if [ "$git_failed" = "1" ] && [ "$count_total" -gt 0 ]; then emit=1; fi

if [ "$emit" = "0" ]; then
    # Healthy and recent: silent exit.
    exit 0
fi

# --- Build summary block -----------------------------------------------------

# Line 1: counts.
printf '[memory] %d entries (verified:%d, inferred:%d, quarantined:%d)\n' \
    "$count_total" "$count_verified" "$count_inferred" "$count_quarantined"

# Line 2: last-sync info.
if [ "$git_failed" = "1" ]; then
    printf '[memory] cannot read git log; check %s\n' "$MEMORY_SHARED_DIR"
elif [ -n "$sync_secs_ago" ]; then
    if [ "$sync_warn" = "1" ]; then
        printf '[memory] WARN last sync %s (host: %s) -- sync may be stuck\n' \
            "$(time_ago "$sync_secs_ago")" "${sync_host:-unknown}"
    else
        printf '[memory] last sync %s (host: %s)\n' \
            "$(time_ago "$sync_secs_ago")" "${sync_host:-unknown}"
    fi
fi

# Line 3: recent activity.
if [ ${#recent_names[@]} -gt 0 ]; then
    # Cap displayed names at first 3 to avoid noise.
    recent_display=""
    i=0
    for n in "${recent_names[@]}"; do
        if [ "$i" -lt 3 ]; then
            if [ -z "$recent_display" ]; then
                recent_display="$n"
            else
                recent_display="${recent_display}, ${n}"
            fi
        fi
        i=$((i + 1))
    done
    if [ "${#recent_names[@]}" -gt 3 ]; then
        recent_display="${recent_display} (+$(( ${#recent_names[@]} - 3 )) more)"
    fi
    printf '[memory] %d added in last 24h: %s -- review with /memory-review\n' \
        "${#recent_names[@]}" "$recent_display"
fi

# Line 4: stale memories.
if [ ${#stale_names[@]} -gt 0 ]; then
    stale_display=""
    i=0
    for n in "${stale_names[@]}"; do
        if [ "$i" -lt 3 ]; then
            if [ -z "$stale_display" ]; then
                stale_display="$n"
            else
                stale_display="${stale_display}, ${n}"
            fi
        fi
        i=$((i + 1))
    done
    if [ "${#stale_names[@]}" -gt 3 ]; then
        stale_display="${stale_display} (+$(( ${#stale_names[@]} - 3 )) more)"
    fi
    printf '[memory] %d stale (last-verified > 90d): %s -- review with /memory-review\n' \
        "${#stale_names[@]}" "$stale_display"
fi

# Line 5: unread alerts.
if [ "$unread_count" -gt 0 ]; then
    if [ -n "$unread_recent_msg" ]; then
        # Truncate long messages.
        msg_short="$unread_recent_msg"
        if [ "${#msg_short}" -gt 80 ]; then
            msg_short="${msg_short:0:77}..."
        fi
        printf '[memory] WARN %d unread alert(s); latest: %s\n' \
            "$unread_count" "$msg_short"
    else
        printf '[memory] WARN %d unread alert(s)\n' "$unread_count"
    fi
    printf '[memory]   run /memory-review or check %s\n' "$ALERTS_LOG"
fi

# --- Performance budget enforcement ------------------------------------------

if [ "$START_EPOCH" != "0" ] && command -v date >/dev/null 2>&1; then
    end_epoch="$(date +%s 2>/dev/null || echo 0)"
    if [ "$end_epoch" != "0" ]; then
        elapsed_secs=$((end_epoch - START_EPOCH))
        # Whole-second resolution; warn only when clearly over the budget.
        if [ "$elapsed_secs" -ge 1 ]; then
            elapsed_ms=$((elapsed_secs * 1000))
            if [ "$elapsed_ms" -ge "$PERF_WARN_MS" ]; then
                printf '[memory] note: hook took ~%dms (>%dms budget)\n' \
                    "$elapsed_ms" "$PERF_WARN_MS" >&2
            fi
        fi
    fi
fi

exit 0
