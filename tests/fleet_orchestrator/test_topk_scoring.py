"""Unit tests for the Top-K agent routing scorer.

Covers every case required by issue #402 acceptance criteria:

1. Docs-only PR picks documentation-writer over test-strategist at K=2.
2. Mixed TypeScript + security keyword ranks code-reviewer and
   dependency-auditor above structure-explorer.
3. Empty applies_to and empty keywords score 0 and are excluded.
4. K >= agent count selects every agent.
5. Tie-breaking is stable and alphabetical.
6. K == 0 returns an empty selection (routing disabled).
7. No positive score with a configured fallback returns that fallback.
8. Frontmatter loader round-trips applies_to and keywords lists.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO_ROOT / "scripts"))

from fleet_orchestrator.topk_scorer import (  # noqa: E402
    Agent,
    WorkItem,
    load_agent,
    load_agents,
    score_agent,
    select_top_k,
)


def _agent(name: str, applies_to: tuple[str, ...] = (), keywords: tuple[str, ...] = ()) -> Agent:
    return Agent(name=name, applies_to=applies_to, keywords=keywords)


class ScoreAgentTests(unittest.TestCase):
    def test_glob_match_contributes_two_points(self) -> None:
        agent = _agent("code-reviewer", applies_to=("**/*.ts",))
        work = WorkItem(changed_files=("src/a.ts",))
        self.assertEqual(score_agent(agent, work).score, 2)

    def test_keyword_match_contributes_one_point(self) -> None:
        agent = _agent("code-reviewer", keywords=("security",))
        work = WorkItem(title="Improve security", body="")
        self.assertEqual(score_agent(agent, work).score, 1)

    def test_case_insensitive_keyword_match(self) -> None:
        agent = _agent("code-reviewer", keywords=("Security",))
        work = WorkItem(title="", body="improve SECURITY posture")
        self.assertEqual(score_agent(agent, work).score, 1)

    def test_no_match_scores_zero(self) -> None:
        agent = _agent("code-reviewer", applies_to=("**/*.ts",), keywords=("security",))
        work = WorkItem(title="update readme", body="", changed_files=("docs/readme.md",))
        self.assertEqual(score_agent(agent, work).score, 0)

    def test_glob_matches_bare_filename(self) -> None:
        agent = _agent("code-reviewer", applies_to=("**/*.ts",))
        work = WorkItem(changed_files=("a.ts",))
        self.assertEqual(score_agent(agent, work).score, 2)

    def test_breakdown_reports_matched_items(self) -> None:
        agent = _agent(
            "code-reviewer",
            applies_to=("**/*.ts", "**/*.py"),
            keywords=("security", "refactor"),
        )
        work = WorkItem(
            title="refactor auth",
            body="tighten security boundary",
            changed_files=("src/auth.ts",),
        )
        breakdown = score_agent(agent, work)
        self.assertEqual(breakdown.score, 2 + 2)  # 1 glob, 2 keywords
        self.assertEqual(breakdown.matched_globs, ("**/*.ts",))
        self.assertEqual(set(breakdown.matched_keywords), {"security", "refactor"})


class SelectTopKTests(unittest.TestCase):
    def _canonical_agents(self) -> list[Agent]:
        return [
            _agent(
                "code-reviewer",
                applies_to=("**/*.ts", "**/*.py"),
                keywords=("security", "quality"),
            ),
            _agent(
                "dependency-auditor",
                applies_to=("**/package.json",),
                keywords=("security", "cve", "vulnerability"),
            ),
            _agent(
                "documentation-writer",
                applies_to=("**/*.md",),
                keywords=("docs", "readme"),
            ),
            _agent(
                "structure-explorer",
                applies_to=("**/Makefile",),
                keywords=("structure", "build"),
            ),
            _agent(
                "test-strategist",
                applies_to=("**/test_*.py", "**/*.test.ts"),
                keywords=("test", "coverage"),
            ),
        ]

    def test_docs_only_pr_selects_documentation_writer(self) -> None:
        agents = self._canonical_agents()
        work = WorkItem(
            title="Update README",
            body="Clarify setup steps.",
            changed_files=("README.md", "docs/setup.md"),
        )
        _, selected = select_top_k(agents, work, k=2)
        self.assertIn("documentation-writer", selected)
        self.assertNotIn("test-strategist", selected)

    def test_ts_plus_security_ranks_reviewer_and_auditor(self) -> None:
        agents = self._canonical_agents()
        work = WorkItem(
            title="security fix in auth module",
            body="patches security vulnerability",
            changed_files=("src/auth.ts", "package.json"),
        )
        _, selected = select_top_k(agents, work, k=2)
        self.assertIn("code-reviewer", selected)
        self.assertIn("dependency-auditor", selected)
        self.assertNotIn("structure-explorer", selected)

    def test_zero_score_agent_excluded(self) -> None:
        agents = [
            _agent("empty-agent"),
            _agent(
                "documentation-writer",
                applies_to=("**/*.md",),
                keywords=("docs",),
            ),
        ]
        work = WorkItem(title="update docs", changed_files=("README.md",))
        _, selected = select_top_k(agents, work, k=2)
        self.assertEqual(selected, ["documentation-writer"])

    def test_k_ge_agent_count_returns_all_positive(self) -> None:
        agents = self._canonical_agents()
        work = WorkItem(title="mixed", changed_files=("src/a.ts",))
        all_scores, selected = select_top_k(agents, work, k=99)
        # Zero-score agents are excluded regardless of K.
        positive = [s for s in all_scores if s.score > 0]
        self.assertEqual(len(selected), len(positive))
        self.assertEqual(selected[0], "code-reviewer")

    def test_tie_breaking_is_alphabetical(self) -> None:
        agents = [
            _agent("zeta", keywords=("refactor",)),
            _agent("alpha", keywords=("refactor",)),
            _agent("mid", keywords=("refactor",)),
        ]
        work = WorkItem(title="refactor widgets", body="")
        all_scores, selected = select_top_k(agents, work, k=3)
        self.assertEqual([s.agent for s in all_scores], ["alpha", "mid", "zeta"])
        self.assertEqual(selected, ["alpha", "mid", "zeta"])

    def test_k_zero_disables_routing(self) -> None:
        agents = self._canonical_agents()
        work = WorkItem(title="security fix", changed_files=("src/a.ts",))
        _, selected = select_top_k(agents, work, k=0)
        self.assertEqual(selected, [])

    def test_no_positive_score_with_fallback(self) -> None:
        agents = [_agent("empty")]
        work = WorkItem(title="unrelated", changed_files=("some.bin",))
        _, selected = select_top_k(
            agents, work, k=2, default_fallback="documentation-writer"
        )
        self.assertEqual(selected, ["documentation-writer"])


class LoadAgentTests(unittest.TestCase):
    def test_round_trip(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo.md"
            path.write_text(
                """---
name: demo
description: x
applies_to:
  - "**/*.ts"
  - "**/*.py"
keywords:
  - refactor
  - security
---

# body
""",
                encoding="utf-8",
            )
            agent = load_agent(path)
            assert agent is not None
            self.assertEqual(agent.name, "demo")
            self.assertEqual(agent.applies_to, ("**/*.ts", "**/*.py"))
            self.assertEqual(agent.keywords, ("refactor", "security"))

    def test_missing_frontmatter_returns_none(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "no-fm.md"
            path.write_text("just body\n", encoding="utf-8")
            self.assertIsNone(load_agent(path))

    def test_load_agents_sorts_by_filename(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            for n in ("b.md", "a.md"):
                (Path(tmp) / n).write_text(
                    f"---\nname: {n[:-3]}\n---\n", encoding="utf-8"
                )
            names = [a.name for a in load_agents(Path(tmp))]
            self.assertEqual(names, ["a", "b"])


if __name__ == "__main__":
    unittest.main()
