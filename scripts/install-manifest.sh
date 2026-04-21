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

MANIFEST_PATH="${MANIFEST_PATH:-$HOME/.claude/.install-manifest.json}"
MANIFEST_SCHEMA=1

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
