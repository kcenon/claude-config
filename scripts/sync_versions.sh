#!/usr/bin/env bash
# Propagate VERSION_MAP.yml values into consumer files.
# Use after editing VERSION_MAP.yml (typically invoked by the /release skill).
#
# Consumers:
#   suite           -> README.md, README.ko.md (shields.io badge and
#                      GITHUB_REF pins), bootstrap.sh, bootstrap.ps1
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
    # The substitution below is global; it is correct only while each target has
    # exactly one "version" key. Assert that invariant so a second key fails
    # loudly here instead of being silently clobbered (matches check_versions.sh,
    # which reads the first match via `head -1`).
    local version_keys
    version_keys=$(grep -cE '"version"[[:space:]]*:' "$path")
    if [ "$version_keys" -gt 1 ]; then
        echo "ERROR: $file has $version_keys \"version\" keys; set_json_version assumes exactly one." >&2
        return 1
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

set_bootstrap_ref_sh() {
    local file="$1"
    local new="$2"
    local path="$ROOT_DIR/$file"
    if [ ! -f "$path" ]; then
        echo "SKIP: $file (not found)" >&2
        return
    fi
    sed_inplace 's/(GITHUB_REF="\$\{GITHUB_REF:-)v[0-9]+\.[0-9]+\.[0-9]+(\}")/\1v'"${new}"'\2/' "$path"
    echo "synced: $file -> GITHUB_REF=v$new"
}

set_bootstrap_ref_ps1() {
    local file="$1"
    local new="$2"
    local path="$ROOT_DIR/$file"
    if [ ! -f "$path" ]; then
        echo "SKIP: $file (not found)" >&2
        return
    fi
    sed_inplace "s/(else[[:space:]]*[{][[:space:]]*')v[0-9]+\.[0-9]+\.[0-9]+('[[:space:]]*[}])/\1v${new}\2/" "$path"
    echo "synced: $file -> GITHUB_REF=v$new"
}

set_readme_github_ref_pins() {
    local file="$1"
    local new="$2"
    local path="$ROOT_DIR/$file"
    if [ ! -f "$path" ]; then
        echo "SKIP: $file (not found)" >&2
        return
    fi
    sed_inplace 's/(GITHUB_REF=)v[0-9]+\.[0-9]+\.[0-9]+/\1v'"${new}"'/g' "$path"
    sed_inplace 's/((e\.g\.|예:) `)v[0-9]+\.[0-9]+\.[0-9]+/\1v'"${new}"'/g' "$path"
    echo "synced: $file -> GITHUB_REF=v$new"
}

set_json_version "plugin/.claude-plugin/plugin.json"       "$PLUGIN"
set_json_version "plugin-lite/.claude-plugin/plugin.json"  "$PLUGIN_LITE"
set_json_version "global/settings.json"                    "$SETTINGS_SCHEMA"
set_json_version "global/settings.windows.json"            "$SETTINGS_SCHEMA"
set_readme_badge "README.md"    "$SUITE"
set_readme_badge "README.ko.md" "$SUITE"
set_bootstrap_ref_sh "bootstrap.sh"     "$SUITE"
set_bootstrap_ref_ps1 "bootstrap.ps1"   "$SUITE"
set_readme_github_ref_pins "README.md"    "$SUITE"
set_readme_github_ref_pins "README.ko.md" "$SUITE"

echo ""
echo "sync_versions: done. Run scripts/check_versions.sh to verify."
