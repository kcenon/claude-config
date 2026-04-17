#!/usr/bin/env bash
# Verify each consumer file's declared version matches VERSION_MAP.yml.
# Exits non-zero on drift. Each field tracks an independent SemVer.
#
# Consumers:
#   suite           -> README.md, README.ko.md (shields.io badge)
#   plugin          -> plugin/.claude-plugin/plugin.json
#   plugin-lite     -> plugin-lite/.claude-plugin/plugin.json
#   settings-schema -> global/settings.json, global/settings.windows.json
#
# Usage: scripts/check_versions.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MAP_FILE="$ROOT_DIR/VERSION_MAP.yml"

if [ ! -f "$MAP_FILE" ]; then
    echo "ERROR: VERSION_MAP.yml not found at $MAP_FILE" >&2
    exit 1
fi

# Extract a top-level scalar from a simple YAML file (no dependency on yq).
# Only supports `key: value` at column 0 with optional inline comment.
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

drift=0

check_json_version() {
    local file="$1"
    local expected="$2"
    local label="$3"
    local path="$ROOT_DIR/$file"
    if [ ! -f "$path" ]; then
        echo "FAIL: consumer missing: $file" >&2
        drift=1
        return
    fi
    local actual
    actual=$(grep -E '"version"[[:space:]]*:' "$path" | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $file version=$actual, VERSION_MAP[$label]=$expected" >&2
        drift=1
    fi
}

check_readme_badge() {
    local file="$1"
    local expected="$2"
    local path="$ROOT_DIR/$file"
    if [ ! -f "$path" ]; then
        echo "FAIL: consumer missing: $file" >&2
        drift=1
        return
    fi
    local actual
    actual=$(grep -oE 'shields\.io/badge/version-[0-9]+\.[0-9]+\.[0-9]+' "$path" | head -1 | sed -E 's|.*badge/version-||')
    if [ -z "$actual" ]; then
        echo "FAIL: $file has no shields.io version badge" >&2
        drift=1
        return
    fi
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $file badge=$actual, VERSION_MAP[suite]=$expected" >&2
        drift=1
    fi
}

check_json_version "plugin/.claude-plugin/plugin.json"       "$PLUGIN"          "plugin"
check_json_version "plugin-lite/.claude-plugin/plugin.json"  "$PLUGIN_LITE"     "plugin-lite"
check_json_version "global/settings.json"                    "$SETTINGS_SCHEMA" "settings-schema"
check_json_version "global/settings.windows.json"            "$SETTINGS_SCHEMA" "settings-schema"
check_readme_badge "README.md"    "$SUITE"
check_readme_badge "README.ko.md" "$SUITE"

if [ "$drift" -eq 0 ]; then
    echo "check_versions: OK"
    echo "  suite=$SUITE  plugin=$PLUGIN  plugin-lite=$PLUGIN_LITE  settings-schema=$SETTINGS_SCHEMA"
    exit 0
fi

echo "" >&2
echo "check_versions: drift detected. Update consumers to match VERSION_MAP.yml," >&2
echo "or run scripts/sync_versions.sh to auto-propagate map values to consumers." >&2
exit 2
