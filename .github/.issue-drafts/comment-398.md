Complementary harness-layer work now tracked in #439 (epic) with sub-issues #437 (phase-1) and #438 (phase-2).

Scope separation:
- This epic (#398) — skills layer: tier presets, halt conditions, input injection inside individual skills.
- #439 — harness layer: `global/CLAUDE.md` routing-only discipline + extended `validate_skills.sh` to prevent drift.

Same motivation (less always-on token cost), different layer. The two can progress independently; the only coupling is that #438 extends the validator already relied on by skill-frontmatter contracts introduced in #401 and #403.
