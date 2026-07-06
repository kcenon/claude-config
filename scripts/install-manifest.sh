#!/bin/bash
# install-manifest.sh
# Helpers for guarded copy with SHA-256 manifest, preserving local
# customizations across re-installs of bootstrap.sh.
#
# Usage (source this file):
#   source "$INSTALL_DIR/scripts/install-manifest.sh"
#   guarded_copy "$src" "$dest" "$key"
#
# Environment:
#   MANIFEST_PATH    override manifest location
#   BOOTSTRAP_FORCE  "1" bypasses the divergence prompt and overwrites

set -euo pipefail

MANIFEST_PATH="${MANIFEST_PATH:-$HOME/.claude/.install-manifest.json}"
MANIFEST_SCHEMA=1
MANIFEST_MANAGED_KEYS=()

# Detect an available JSON tool (python3 preferred, python fallback).
_manifest_json_tool=""
if command -v python3 >/dev/null 2>&1; then
    _manifest_json_tool="python3"
elif command -v python >/dev/null 2>&1; then
    _manifest_json_tool="python"
fi

manifest_available() {
    [ -n "$_manifest_json_tool" ]
}

manifest_reset_managed_keys() {
    MANIFEST_MANAGED_KEYS=()
}

manifest_track_key() {
    local key="$1"
    [ -n "$key" ] || return 0
    MANIFEST_MANAGED_KEYS+=("$key")
}

_manifest_hash() {
    local file="$1"
    [ -f "$file" ] || return 1
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" 2>/dev/null | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}'
    else
        return 1
    fi
}

_manifest_read() {
    local key="$1"
    [ -f "$MANIFEST_PATH" ] || return 0
    MANIFEST_PATH="$MANIFEST_PATH" KEY="$key" "$_manifest_json_tool" <<'PY'
import json, os
p = os.environ["MANIFEST_PATH"]
k = os.environ["KEY"]
try:
    with open(p) as f:
        m = json.load(f)
    print(m.get("files", {}).get(k, ""), end="")
except Exception:
    pass
PY
}

_manifest_write() {
    local key="$1" sha="$2"
    mkdir -p "$(dirname "$MANIFEST_PATH")"
    MANIFEST_PATH="$MANIFEST_PATH" KEY="$key" SHA="$sha" \
    SCHEMA="$MANIFEST_SCHEMA" "$_manifest_json_tool" <<'PY'
import json, os
p = os.environ["MANIFEST_PATH"]
k = os.environ["KEY"]
v = os.environ["SHA"]
schema = int(os.environ["SCHEMA"])
try:
    with open(p) as f:
        m = json.load(f)
    if not isinstance(m, dict):
        m = {}
except Exception:
    m = {}
m["schema"] = schema
m.setdefault("files", {})[k] = v
with open(p, "w") as f:
    json.dump(m, f, indent=2, sort_keys=True)
    f.write("\n")
PY
}

# manifest_prune_removed <dest_root> <managed_key>...
# Deletes files that were tracked by a previous manifest but are absent from
# the current managed set, provided the deployed file still matches the stored
# hash. Locally edited files are preserved.
manifest_prune_removed() {
    local dest_root="$1"
    shift || true

    [ -d "$dest_root" ] || return 0
    [ -f "$MANIFEST_PATH" ] || return 0

    if [ "$#" -eq 0 ]; then
        echo "  Manifest prune skipped: no current managed files"
        return 0
    fi

    if ! manifest_available; then
        echo "  Manifest prune skipped: no JSON tool available"
        return 0
    fi

    MANIFEST_PATH="$MANIFEST_PATH" DEST_ROOT="$dest_root" "$_manifest_json_tool" - "$@" <<'PY'
import hashlib
import json
import os
import sys

manifest_path = os.environ["MANIFEST_PATH"]
dest_root = os.path.realpath(os.environ["DEST_ROOT"])
managed = set(sys.argv[1:])

try:
    with open(manifest_path) as f:
        manifest = json.load(f)
except Exception:
    print("  Manifest prune skipped: manifest unreadable")
    sys.exit(0)

files = manifest.get("files")
if not isinstance(files, dict):
    sys.exit(0)

changed = False
for key, stored_sha in sorted(list(files.items())):
    if key in managed:
        continue

    normalized = os.path.normpath(key)
    if (
        os.path.isabs(key)
        or normalized == os.pardir
        or normalized.startswith(os.pardir + os.sep)
    ):
        print("  Preserved removed managed entry with unsafe path: {}".format(key))
        continue

    dest = os.path.realpath(os.path.join(dest_root, normalized))
    if dest != dest_root and not dest.startswith(dest_root + os.sep):
        print("  Preserved removed managed entry outside install root: {}".format(key))
        continue

    if not os.path.exists(dest):
        del files[key]
        changed = True
        print("  Removed stale manifest entry for missing file: {}".format(key))
        continue

    if not os.path.isfile(dest):
        print("  Preserved removed managed path because it is not a file: {}".format(key))
        continue

    try:
        with open(dest, "rb") as f:
            current_sha = hashlib.sha256(f.read()).hexdigest()
    except OSError:
        print("  Preserved removed managed file; unable to read: {}".format(key))
        continue

    if current_sha == stored_sha:
        try:
            os.remove(dest)
        except OSError:
            print("  Preserved removed managed file; unable to delete: {}".format(key))
            continue
        del files[key]
        changed = True
        print("  Pruned removed managed file: {}".format(key))
    else:
        print("  Preserved locally edited removed managed file: {}".format(key))

if changed:
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
PY
}

manifest_prune_tracked() {
    local dest_root="$1"
    manifest_prune_removed "$dest_root" "${MANIFEST_MANAGED_KEYS[@]}"
}

_manifest_safe_dest() {
    local dest_root="$1" key="$2"
    case "$key" in
        /*|../*|*/../*|..)
            return 1
            ;;
    esac
    printf '%s/%s\n' "$dest_root" "$key"
}

# manifest_seed_retired_managed <dest_root> (<key> <sha256>)...
# Adds manifest ownership for known retired files only when the deployed file
# still byte-matches the historical upstream copy. The next prune pass can then
# remove it while locally edited retired files remain untouched.
manifest_seed_retired_managed() {
    local dest_root="$1"
    shift || true

    [ -d "$dest_root" ] || return 0
    manifest_available || return 0

    while [ "$#" -ge 2 ]; do
        local key="$1" retired_sha="$2" dest current_sha current_lf_sha stored_sha
        shift 2

        stored_sha=$(_manifest_read "$key")
        [ -n "$stored_sha" ] && continue

        dest=$(_manifest_safe_dest "$dest_root" "$key") || {
            echo "  Manifest prune: skipped unsafe retired path: $key"
            continue
        }
        [ -f "$dest" ] || continue

        current_sha=$(_manifest_hash "$dest") || current_sha=""
        current_lf_sha=""
        if command -v shasum >/dev/null 2>&1; then
            current_lf_sha=$(tr -d '\r' < "$dest" | shasum -a 256 2>/dev/null | awk '{print $1}')
        elif command -v sha256sum >/dev/null 2>&1; then
            current_lf_sha=$(tr -d '\r' < "$dest" | sha256sum 2>/dev/null | awk '{print $1}')
        fi
        if [ -n "$current_sha" ] && [ "$current_sha" = "$retired_sha" ]; then
            _manifest_write "$key" "$retired_sha"
            echo "  Manifest prune: matched retired managed file: $key"
        elif [ -n "$current_lf_sha" ] && [ "$current_lf_sha" = "$retired_sha" ]; then
            _manifest_write "$key" "$current_sha"
            echo "  Manifest prune: matched retired managed file: $key"
        else
            echo "  Manifest prune: preserved locally edited retired file: $key"
        fi
    done
}

manifest_copy_file() {
    local src="$1" dest="$2" key="$3" executable="${4:-0}"
    [ -f "$src" ] || return 0
    mkdir -p "$(dirname "$dest")"

    if guarded_copy "$src" "$dest" "$key"; then
        [ "$executable" = "1" ] && chmod +x "$dest"
        manifest_track_key "$key"
        return 0
    fi

    manifest_track_key "$key"
    return 1
}

manifest_copy_files() {
    local src_dir="$1" dest_dir="$2" key_prefix="$3" pattern="${4:-*}" executable="${5:-0}"
    local src base key dest

    [ -d "$src_dir" ] || return 0
    mkdir -p "$dest_dir"

    for src in "$src_dir"/$pattern; do
        [ -f "$src" ] || continue
        base="$(basename "$src")"
        key="${key_prefix:+$key_prefix/}$base"
        dest="$dest_dir/$base"
        manifest_copy_file "$src" "$dest" "$key" "$executable" || true
    done
}

manifest_copy_tree() {
    local src_dir="$1" dest_dir="$2" key_prefix="$3" executable="${4:-0}"
    local src rel key dest

    [ -d "$src_dir" ] || return 0
    mkdir -p "$dest_dir"

    while IFS= read -r src; do
        [ -f "$src" ] || continue
        rel="${src#$src_dir/}"
        key="${key_prefix:+$key_prefix/}$rel"
        dest="$dest_dir/$rel"
        manifest_copy_file "$src" "$dest" "$key" "$executable" || true
    done < <(find "$src_dir" -type f 2>/dev/null)
}

# guarded_copy <src> <dest> <key>
# Returns 0 when the file was copied (or no change needed), 1 when the
# local file was kept by user choice.
guarded_copy() {
    local src="$1" dest="$2" key="$3"
    [ -f "$src" ] || return 0

    # Fall back to unconditional copy if no JSON tool is available.
    if ! manifest_available; then
        cp "$src" "$dest"
        return 0
    fi

    # Destination missing — first install; copy and record.
    if [ ! -f "$dest" ]; then
        cp "$src" "$dest"
        local sha
        sha=$(_manifest_hash "$src")
        [ -n "$sha" ] && _manifest_write "$key" "$sha"
        return 0
    fi

    local src_sha dest_sha stored_sha
    src_sha=$(_manifest_hash "$src")
    dest_sha=$(_manifest_hash "$dest")
    stored_sha=$(_manifest_read "$key")

    # Nothing to do.
    if [ -n "$src_sha" ] && [ "$src_sha" = "$dest_sha" ]; then
        [ -z "$stored_sha" ] && _manifest_write "$key" "$src_sha"
        return 0
    fi

    # Destination matches stored hash → safe upgrade, no local edits.
    if [ -n "$stored_sha" ] && [ "$dest_sha" = "$stored_sha" ]; then
        cp "$src" "$dest"
        _manifest_write "$key" "$src_sha"
        return 0
    fi

    # Divergence: destination differs from both source and stored hash.
    if [ "${BOOTSTRAP_FORCE:-0}" = "1" ]; then
        cp "$src" "$dest"
        _manifest_write "$key" "$src_sha"
        return 0
    fi

    echo ""
    echo "  Local changes detected in: $dest"
    echo "  Incoming version differs from both local and the last install."
    if command -v diff >/dev/null 2>&1; then
        diff -u "$dest" "$src" 2>/dev/null | head -40 || true
    fi
    local choice
    read -r -p "  [k]eep local / [o]verwrite (default: keep): " choice
    choice=${choice:-k}

    case "$choice" in
        o|O)
            cp "$src" "$dest"
            _manifest_write "$key" "$src_sha"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# guarded_template_copy <src_tmpl> <dest> <key> <display_lang>
guarded_template_copy() {
    local src_tmpl="$1" dest="$2" key="$3" display_lang="$4"
    [ -f "$src_tmpl" ] || return 0

    local tmp_lang
    tmp_lang=$(mktemp)
    # Strip the developer-only tmpl-contract comment line so it does not leak
    # into the rendered .md (issue #773, parity with the #771 render_policy_tmpl fix).
    sed -e "/tmpl-contract/d" -e "s/{{AGENT_LANGUAGE_POLICY}}/$display_lang/g" "$src_tmpl" > "$tmp_lang"
    
    local result
    if guarded_copy "$tmp_lang" "$dest" "$key"; then
        result=0
    else
        result=1
    fi
    rm -f "$tmp_lang"
    return "$result"
}

# update_claude_settings_json <settings_json_path> <agent_language> <content_language>
update_claude_settings_json() {
    local settings_path="$1" agent_lang="$2" content_lang="$3"
    [ -f "$settings_path" ] || return 0

    if command -v jq >/dev/null 2>&1; then
        local tmpfile
        tmpfile=$(mktemp)
        if [ "$content_lang" != "english" ]; then
            jq --arg v "$content_lang" --arg lang "$agent_lang" \
               '.env = (.env // {}) | .env.CLAUDE_CONTENT_LANGUAGE = $v | .language = $lang' \
               "$settings_path" > "$tmpfile"
        else
            # Idempotent reset for english policy
            jq --arg lang "$agent_lang" \
               'del(.env.CLAUDE_CONTENT_LANGUAGE) | if .env == {} then del(.env) else . end | .language = $lang' \
               "$settings_path" > "$tmpfile"
        fi
        mv "$tmpfile" "$settings_path"
        return 0
    else
        return 1
    fi
}
