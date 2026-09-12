#!/bin/bash
# test-install-prompts.sh
#
# Behavioural tests for seed_git_identity() in scripts/lib/install-prompts.sh,
# the bash half of what test-install-prompts-ps1.ps1 covers for
# Set-GitIdentitySeed. Added with #916, which found three defects in a function
# that had no behavioural coverage at all.
#
# Run: bash tests/scripts/test-install-prompts.sh

set -uo pipefail

PASS=0
FAIL=0
ERRORS=()

cd "$(dirname "$0")/../.." || exit 1
# shellcheck disable=SC1091
source scripts/lib/install-prompts.sh

check() {
    local label="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $label (got '$got' want '$want')")
        echo "  FAIL: $label"
        echo "    want: $want"
        echo "    got : $got"
    fi
}

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# GIT_CONFIG_GLOBAL keeps these deterministic and lets the "no git config"
# branch run without touching the developer's real config.
saved_git_config="${GIT_CONFIG_GLOBAL:-}"
export GIT_CONFIG_GLOBAL="$TEST_DIR/fake-gitconfig"
printf '[user]\n\tname = Ada & Lovelace\n\temail = ada@example.org\n' > "$GIT_CONFIG_GLOBAL"

write_identity() {
    cat > "$1" <<'MD'
# Git Identity

The installer auto-seeds the two fields below. If either git-config
value is missing, replace the `YOUR NAME` / `YOUR EMAIL` placeholders
by hand.

name: YOUR NAME
email: YOUR EMAIL
MD
}

echo "=== seed_git_identity tests ==="
echo ""

IDENTITY="$TEST_DIR/git-identity.md"
write_identity "$IDENTITY"
seed_git_identity "$IDENTITY"
check "seeder reports success"        "$?"                                   "0"
check "seeds the name field"          "$(sed -n '7p' "$IDENTITY")"           "name: Ada & Lovelace"
check "seeds the email field"         "$(sed -n '8p' "$IDENTITY")"           "email: ada@example.org"
# The defect: an unanchored s|YOUR NAME|...|g also rewrote the sentence that
# names the placeholders, leaving it pointing at the substituted values.
check "leaves the explanatory sentence intact" \
    "$(sed -n '4p' "$IDENTITY")" \
    'value is missing, replace the `YOUR NAME` / `YOUR EMAIL` placeholders'
# sed replacement metacharacters must not be interpreted: `&` means "the whole
# match" unless escaped.
check "inserts an ampersand literally" \
    "$(grep -c 'Ada & Lovelace' "$IDENTITY")" "1"
check "exports the seeded name"       "$SEED_GIT_IDENTITY_NAME"              "Ada & Lovelace"
check "exports the seeded email"      "$SEED_GIT_IDENTITY_EMAIL"             "ada@example.org"
check "leaves no .bak behind"         "$([ -e "$IDENTITY.bak" ] && echo y || echo n)" "n"

# Second run: the field lines no longer hold placeholders, so nothing is seeded
# even though the sentence still mentions the tokens. An unanchored presence
# check would report a seeding that did nothing.
before_hash="$(sha256sum < "$IDENTITY")"
seed_git_identity "$IDENTITY"
check "second run reports nothing seeded" "$?" "1"
check "second run leaves the file byte-identical" "$(sha256sum < "$IDENTITY")" "$before_hash"

# No git config at all: no-op, file untouched.
: > "$GIT_CONFIG_GLOBAL"
FRESH="$TEST_DIR/git-identity-nocfg.md"
write_identity "$FRESH"
fresh_hash="$(sha256sum < "$FRESH")"
seed_git_identity "$FRESH"
check "missing git config seeds nothing" "$?" "1"
check "missing git config leaves the file untouched" "$(sha256sum < "$FRESH")" "$fresh_hash"

# Absent target.
seed_git_identity "$TEST_DIR/does-not-exist.md"
check "absent target returns 1" "$?" "1"

export GIT_CONFIG_GLOBAL="$saved_git_config"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    for err in "${ERRORS[@]}"; do echo "  $err"; done
    exit 1
fi
exit 0
