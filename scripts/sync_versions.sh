#!/usr/bin/env bash
# Propagate VERSION_MAP.yml values into consumer files.
# Use after editing VERSION_MAP.yml (typically invoked by the /release skill).
#
# Consumers:
#   suite           -> README.md, README.ko.md (shields.io badge)
#   plugin          -> plugin/.claude-plugin/plugin.json
#   plugin-lite     -> plugin-lite/.claude-plugin/plugin.json
#   settings-schema -> global/settings.json, global/settings.windows.json
#
# Usage: scripts/sync_versions.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MAP_FILE="$ROOT_DIR/VERSION_MAP.yml"

if [ ! -f "$MAP_FILE" ]; then
    echo "ERROR: VERSION_MAP.yml not found at $MAP_FILE" >&2
    exit 1
fi

read_map_field() {
    local key="$1"
    local value
    value=$(grep -E "^${key}:" "$MAP_FILE" | head -1 | sed -E "s/^${key}:[[:space:]]*([^[:space:]#]+).*/\1/")
    if [ -z "$value" ]; then
        echo "ERROR: field '${key}' not found in VERSION_MAP.yml" >&2
        exit 1
    fi
    printf '%s' "$value"
}

SUITE=$(read_map_field "suite")
PLUGIN=$(read_map_field "plugin")
PLUGIN_LITE=$(read_map_field "plugin-lite")
SETTINGS_SCHEMA=$(read_map_field "settings-schema")

# Portable in-place replacement: sed -i differs between GNU and BSD.
sed_inplace() {
    local expr="$1"
    local file="$2"
    local tmp="${file}.tmp.$$"
    sed -E "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
}

set_json_version() {
    local file="$1"
    local new="$2"
    local path="$ROOT_DIR/$file"
    if [ ! -f "$path" ]; then
        echo "SKIP: $file (not found)" >&2
        return
    fi
    sed_inplace 's/("version"[[:space:]]*:[[:space:]]*")[^"]+(")/\1'"${new}"'\2/' "$path"
    echo "synced: $file -> version=$new"
}

set_readme_badge() {
    local file="$1"
    local new="$2"
    local path="$ROOT_DIR/$file"
    if [ ! -f "$path" ]; then
        echo "SKIP: $file (not found)" >&2
        return
    fi
    sed_inplace 's|(shields\.io/badge/version-)[0-9]+\.[0-9]+\.[0-9]+|\1'"${new}"'|' "$path"
    echo "synced: $file -> badge=$new"
}

set_json_version "plugin/.claude-plugin/plugin.json"       "$PLUGIN"
set_json_version "plugin-lite/.claude-plugin/plugin.json"  "$PLUGIN_LITE"
set_json_version "global/settings.json"                    "$SETTINGS_SCHEMA"
set_json_version "global/settings.windows.json"            "$SETTINGS_SCHEMA"
set_readme_badge "README.md"    "$SUITE"
set_readme_badge "README.ko.md" "$SUITE"

echo ""
echo "sync_versions: done. Run scripts/check_versions.sh to verify."
