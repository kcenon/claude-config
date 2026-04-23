"""Integration check: Top-K=2 on a docs-only PR uses the real agents directory.

Verifies the acceptance-criterion telemetry requirement:

    demonstrate top-K=2 spawn for a docs-only PR avoids irrelevant agents

We read the 8 agent definitions from ``plugin/agents/`` and run the scorer
against a work item that touches only ``*.md`` files. The result MUST include
``documentation-writer`` and MUST NOT include ``test-strategist`` or
``dependency-auditor``.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO_ROOT / "scripts"))

from fleet_orchestrator.topk_scorer import (  # noqa: E402
    WorkItem,
    load_agents,
    select_top_k,
)


AGENTS_DIR = _REPO_ROOT / "plugin" / "agents"


class DocsOnlyRoutingTelemetry(unittest.TestCase):
    def test_docs_only_pr_excludes_irrelevant_agents(self) -> None:
        agents = load_agents(AGENTS_DIR)
        self.assertEqual(
            len(agents), 8, f"expected 8 agents, found {len(agents)} in {AGENTS_DIR}"
        )

        work = WorkItem(
            title="docs: clarify install steps",
            body="Rewrite the README install section for macOS and Windows.",
            changed_files=("README.md", "docs/install.md"),
        )

        all_scores, selected = select_top_k(agents, work, k=2)
        # At most K agents are ever selected (may be fewer if the docs-only
        # work item scores only one agent above zero — that is the point of
        # Top-K routing: zero-score agents are pruned).
        self.assertLessEqual(len(selected), 2, f"selected={selected} scores={all_scores}")
        self.assertGreaterEqual(len(selected), 1, f"selected={selected} scores={all_scores}")
        self.assertIn("documentation-writer", selected)
        # Irrelevant agents for a docs-only PR must not be spawned.
        self.assertNotIn("test-strategist", selected)
        self.assertNotIn("dependency-auditor", selected)
        self.assertNotIn("qa-reviewer", selected)


if __name__ == "__main__":
    unittest.main()
