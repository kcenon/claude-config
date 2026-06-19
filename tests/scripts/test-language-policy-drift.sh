#!/bin/bash
# test-language-policy-drift.sh
# Drift regression for issues #411 and #761.
#
# This test binds to the REAL template renderer (render_policy_tmpl /
# render_policy_tmpls_in_dir, single-sourced into scripts/lib/install-prompts.sh
# by #760) instead of a hand-rolled sed mock. Exercising the production
# renderer is the whole point: a mock can silently diverge from the code the
# installers actually run, which is exactly the drift this suite guards.
#
# Coverage:
#
#   1. Render matrix — for each *.md.tmpl twin and each of the three shipped
#      language-profile presets (english / Korean / Hybrid), render through
#      render_policy_tmpl and assert:
#        a. the expected policy / agent phrases are present, and
#        b. ZERO leftover {{PLACEHOLDER}} tokens survive (zero-residue gate).
#
#   2. Canonical drift — for every template that ships a committed .md twin,
#      the english-preset render must equal that canonical .md. Editing the
#      .md without the .tmpl (or vice versa) would let the installer overwrite
#      the doc with a stale phrase on a non-english policy; this catches it.
#      The renderer now strips the template-only tmpl-contract comment line
#      during render (issue #771), so the rendered output already equals the
#      committed .md with no test-side workaround — only CRLF is normalized.
#
#   2b. No-marker gate — for every template and preset, the rendered output
#      must contain ZERO tmpl-contract markers. This is the regression guard
#      for #771: the renderer, not the test, is responsible for stripping the
#      developer-only comment so it never leaks into the installed .md.
#
#   3. Directory render — copy project/.claude/rules to a tempdir, run
#      render_policy_tmpls_in_dir over it, and assert no {{...}} residue and
#      no *.md.tmpl files survive (the bootstrap bulk-render path).
#
# Run: bash tests/scripts/test-language-policy-drift.sh
# Exit: 0 on all-pass, 1 on any drift or rendering failure.
#
# NOTE (PowerShell parity, #761): the PowerShell renderer
# (Invoke-PolicyTemplate / Invoke-PolicyTemplatesInDir in
# scripts/lib/InstallPrompts.psm1) is intentionally NOT exercised here — a
# psm1 import unit test is deferred to a follow-up. The bash/PowerShell phrase
# tables and policy lists are kept in lockstep by
# tests/scripts/test-installer-prompt-drift.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the REAL renderer and phrase table from the installer lib. The lib is
# load-guarded (INSTALL_PROMPTS_SH_LOADED) and only defines functions on
# source — it auto-runs nothing — so sourcing has no side effects.
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/install-prompts.sh"

# Marker substring for the template-only canonical-contract comment. The
# renderer strips any line containing it (issue #771); the test asserts the
# rendered output carries none, rather than stripping it before comparison.
CONTRACT_MARKER='tmpl-contract'

# All shipped templates. The .md column is the committed canonical twin, or
# "-" for bootstrap-only templates that render straight into ~/.claude with no
# in-repo .md (e.g. conversation-language).
#   format: <tmpl> | <canonical .md or -> | <space-separated expected-substring keys>
TEMPLATES=(
    "global/commit-settings.md.tmpl|global/commit-settings.md|content"
    "global/conversation-language.md.tmpl|-|agent"
    "project/.claude/rules/core/communication.md.tmpl|project/.claude/rules/core/communication.md|content agent agentlang"
    "project/.claude/rules/workflow/git-commit-format.md.tmpl|project/.claude/rules/workflow/git-commit-format.md|content"
)

# Presets: name | CONTENT_LANGUAGE | AGENT_DISPLAY_LANG | AGENT_LANGUAGE
PRESETS=(
    "english|english|English|english"
    "Korean|exclusive_bilingual|Korean|korean"
    "Hybrid|english|Korean|korean"
)

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# normalize_lf <file>  — emit file with CR stripped (the repo carries mixed
# CRLF/LF on Windows clones). The contract comment is no longer stripped here:
# the renderer removes it, so the rendered output must already match the .md.
normalize_lf() {
    tr -d '\r' < "$1"
}

echo "=== Content-language policy drift test (#411, #761) ==="
echo ""

# ---------------------------------------------------------------------------
# 1 + 2: per-template render matrix and canonical drift.
# ---------------------------------------------------------------------------
for entry in "${TEMPLATES[@]}"; do
    IFS='|' read -r tmpl_rel md_rel keys <<<"$entry"
    tmpl="$REPO_ROOT/$tmpl_rel"
    name="$(basename "$tmpl_rel")"

    echo "[${name}]"

    if [ ! -f "$tmpl" ]; then
        fail "template missing: $tmpl_rel"
        echo ""
        continue
    fi

    for preset in "${PRESETS[@]}"; do
        IFS='|' read -r pname cl adl al <<<"$preset"
        rendered="$(mktemp)"

        # Set the three preset vars in a subshell and render through the REAL
        # renderer. The subshell keeps ambient state from leaking across
        # presets and matches how the installers invoke render_policy_tmpl.
        (
            CONTENT_LANGUAGE="$cl"
            AGENT_DISPLAY_LANG="$adl"
            AGENT_LANGUAGE="$al"
            export CONTENT_LANGUAGE AGENT_DISPLAY_LANG AGENT_LANGUAGE
            render_policy_tmpl "$tmpl" "$rendered"
        )

        # 1a: expected-substring assertions (only the keys each tmpl uses).
        for key in $keys; do
            case "$key" in
                content)
                    want="$(get_policy_phrase "$cl")"
                    if grep -qF "$want" "$rendered"; then
                        pass "${pname}: content phrase '${want}' present"
                    else
                        fail "${pname}: content phrase '${want}' missing"
                    fi
                    ;;
                agent)
                    if grep -qF "$adl" "$rendered"; then
                        pass "${pname}: agent display '${adl}' present"
                    else
                        fail "${pname}: agent display '${adl}' missing"
                    fi
                    ;;
                agentlang)
                    # AGENT_LANGUAGE lands in `language: "<value>"`.
                    if grep -qF "language: \"$al\"" "$rendered"; then
                        pass "${pname}: agent language '${al}' present"
                    else
                        fail "${pname}: agent language '${al}' missing"
                    fi
                    ;;
            esac
        done

        # 1b: zero-residue gate — no {{PLACEHOLDER}} may survive.
        if grep -qE '\{\{[A-Z_]+\}\}' "$rendered"; then
            leftover="$(grep -oE '\{\{[A-Z_]+\}\}' "$rendered" | sort -u | paste -sd, -)"
            fail "${pname}: leftover placeholders survive render: ${leftover}"
        else
            pass "${pname}: no leftover {{...}} placeholders"
        fi

        # 2b: no-marker gate (#771) — the tmpl-contract comment must never
        # leak into the rendered output for any preset.
        if grep -qF "$CONTRACT_MARKER" "$rendered"; then
            fail "${pname}: tmpl-contract marker leaked into render"
        else
            pass "${pname}: no tmpl-contract marker in render"
        fi

        # 2: canonical drift — english preset must equal the committed .md.
        # The renderer strips the contract comment, so the rendered output
        # must match the .md verbatim (only CRLF normalized).
        if [ "$pname" = "english" ] && [ "$md_rel" != "-" ]; then
            md="$REPO_ROOT/$md_rel"
            if [ ! -f "$md" ]; then
                fail "canonical .md missing: $md_rel"
            elif diff -q \
                <(normalize_lf "$rendered") \
                <(normalize_lf "$md") >/dev/null 2>&1; then
                pass "canonical .md matches english render"
            else
                fail "canonical .md drifted from english render"
                echo "  --- diff (rendered vs canonical, LF-normalized) ---"
                diff <(normalize_lf "$rendered") <(normalize_lf "$md") \
                    | head -20 | sed 's/^/      /'
                echo "  ---------------------------------------------------"
            fi
        fi

        rm -f "$rendered"
    done

    echo ""
done

# ---------------------------------------------------------------------------
# 3: directory render — exercise render_policy_tmpls_in_dir on a copy of the
#    project rules tree (the bootstrap bulk-render path).
# ---------------------------------------------------------------------------
echo "[render_policy_tmpls_in_dir]"
rules_src="$REPO_ROOT/project/.claude/rules"
if [ ! -d "$rules_src" ]; then
    fail "rules source dir missing: project/.claude/rules"
else
    work="$(mktemp -d)"
    cp -r "$rules_src" "$work/rules"

    # Guard: the copy must actually contain templates, else the assertions
    # below would pass vacuously.
    n_tmpl_before="$(find "$work/rules" -type f -name '*.md.tmpl' | wc -l | tr -d ' ')"
    if [ "$n_tmpl_before" -eq 0 ]; then
        fail "no *.md.tmpl found in copied rules tree (vacuous test)"
    else
        pass "copied rules tree contains ${n_tmpl_before} template(s)"

        (
            CONTENT_LANGUAGE="english"
            AGENT_DISPLAY_LANG="English"
            AGENT_LANGUAGE="english"
            export CONTENT_LANGUAGE AGENT_DISPLAY_LANG AGENT_LANGUAGE
            render_policy_tmpls_in_dir "$work/rules"
        )

        # No *.md.tmpl may survive the bulk render (they are rendered + removed).
        if find "$work/rules" -type f -name '*.md.tmpl' | grep -q .; then
            surviving="$(find "$work/rules" -type f -name '*.md.tmpl' | sed "s|$work/||")"
            fail "*.md.tmpl survived directory render: ${surviving}"
        else
            pass "no *.md.tmpl survived directory render"
        fi

        # No {{...}} residue may survive in any rendered .md.
        if grep -rqE '\{\{[A-Z_]+\}\}' "$work/rules"; then
            fail "leftover {{...}} placeholders survive in rendered rules tree"
            grep -rnE '\{\{[A-Z_]+\}\}' "$work/rules" | head -10 | sed 's/^/      /'
        else
            pass "no leftover {{...}} placeholders in rendered rules tree"
        fi

        # No tmpl-contract marker may survive in any rendered .md (#771).
        if grep -rqF "$CONTRACT_MARKER" "$work/rules"; then
            fail "tmpl-contract marker survives in rendered rules tree"
            grep -rnF "$CONTRACT_MARKER" "$work/rules" | head -10 | sed 's/^/      /'
        else
            pass "no tmpl-contract marker in rendered rules tree"
        fi
    fi

    rm -rf "$work"
fi
echo ""

echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
