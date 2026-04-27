"""Top-K agent routing scorer for fleet-orchestrator.

Implements the scoring algorithm specified in
``global/skills/_internal/fleet-orchestrator/SKILL.md`` Phase 2.5.

The module is intentionally pure (no I/O side effects beyond reading agent
frontmatter YAML files when the helper ``load_agents`` is used) so the
scoring function can be unit-tested in isolation.

Canonical spec:

    score(agent, work_item) =
        2 * count(glob in agent.applies_to that matches any changed_file)
      + 1 * count(keyword in agent.keywords that appears in title+body text)

- Glob matches use ``fnmatch`` gitignore-style matching. ``**/*.ts`` matches
  ``src/a.ts`` and ``a.ts``.
- Keyword matches are case-insensitive substring matches against the
  concatenation of the work item's title and body.
- Agents with a score of ``0`` are never selected.
- Tie-breaking uses the agent's ``name`` alphabetically (stable ordering).

This module is the authoritative implementation; the markdown spec references
it for exact behavior.
"""

from __future__ import annotations

import fnmatch
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


@dataclass(frozen=True)
class Agent:
    """An agent definition loaded from frontmatter."""

    name: str
    applies_to: tuple[str, ...] = ()
    keywords: tuple[str, ...] = ()


@dataclass(frozen=True)
class WorkItem:
    """A single work item (issue + optional PR) used for routing."""

    title: str = ""
    body: str = ""
    changed_files: tuple[str, ...] = ()


@dataclass(frozen=True)
class ScoreBreakdown:
    """Per-agent scoring result. Exposed for the telemetry artifact."""

    agent: str
    score: int
    matched_globs: tuple[str, ...]
    matched_keywords: tuple[str, ...]


def _match_glob(pattern: str, path: str) -> bool:
    """Gitignore-style glob matching.

    ``fnmatch`` alone does not honor the ``**`` semantics most developers
    expect (match across directory boundaries). We normalize ``**/`` to match
    zero or more path segments by trying both the original pattern and a
    variant with ``**/`` stripped.
    """

    if fnmatch.fnmatchcase(path, pattern):
        return True
    if pattern.startswith("**/"):
        return fnmatch.fnmatchcase(path, pattern[3:])
    return False


def _matched_globs(globs: Sequence[str], files: Sequence[str]) -> tuple[str, ...]:
    """Return the subset of ``globs`` that match at least one file in ``files``."""

    out: list[str] = []
    for g in globs:
        if any(_match_glob(g, f) for f in files):
            out.append(g)
    return tuple(out)


def _matched_keywords(keywords: Sequence[str], text: str) -> tuple[str, ...]:
    """Return the subset of ``keywords`` found (case-insensitive substring) in ``text``."""

    haystack = text.lower()
    return tuple(k for k in keywords if k.lower() in haystack)


def score_agent(agent: Agent, work_item: WorkItem) -> ScoreBreakdown:
    """Compute the Top-K score for a single agent/work-item pair."""

    globs = _matched_globs(agent.applies_to, work_item.changed_files)
    kws = _matched_keywords(agent.keywords, f"{work_item.title}\n{work_item.body}")
    score = 2 * len(globs) + len(kws)
    return ScoreBreakdown(
        agent=agent.name,
        score=score,
        matched_globs=globs,
        matched_keywords=kws,
    )


def select_top_k(
    agents: Sequence[Agent],
    work_item: WorkItem,
    k: int,
    *,
    default_fallback: str | None = None,
) -> tuple[list[ScoreBreakdown], list[str]]:
    """Score every agent, then select the top K.

    Returns a ``(all_scores, selected_names)`` pair.

    Selection rules (mirrors SKILL.md Phase 2.5):

    - ``k == 0``: routing disabled. Returns an empty ``selected_names`` list
      (callers fall back to legacy behavior).
    - ``k >= len(agents)``: covers the whole pool, equivalent to pre-Top-K
      behavior. Returns all agents ordered by score descending.
    - Agents with score ``0`` are excluded from selection regardless of K.
    - If no agent scores above zero and ``default_fallback`` is provided,
      selection returns ``[default_fallback]``.
    - Ties are broken by agent name alphabetically (stable).
    """

    all_scores = [score_agent(a, work_item) for a in agents]
    all_scores.sort(key=lambda s: (-s.score, s.agent))

    if k <= 0:
        return all_scores, []

    positive = [s for s in all_scores if s.score > 0]

    if not positive:
        return all_scores, [default_fallback] if default_fallback else []

    # ``k >= len(agents)`` covers the whole scored pool (still excluding zeros,
    # since the spec says zero-score agents are never selected regardless of K).
    selected = [s.agent for s in positive[:k]]
    return all_scores, selected


# ---------------------------------------------------------------------------
# Helpers for loading agent definitions from disk. Kept separate from the
# pure scoring function so tests can exercise scoring without touching the
# filesystem.
# ---------------------------------------------------------------------------


_FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---", re.DOTALL)


def _parse_yaml_list(block: str, key: str) -> list[str]:
    """Minimal YAML extractor for ``key:`` blocks followed by ``- item`` lines."""

    pattern = re.compile(
        rf"^{re.escape(key)}:\s*\n((?:\s*-\s*.+\n?)+)", re.MULTILINE
    )
    m = pattern.search(block)
    if not m:
        return []
    items: list[str] = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line.startswith("-"):
            continue
        value = line[1:].strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        elif value.startswith("'") and value.endswith("'"):
            value = value[1:-1]
        items.append(value)
    return items


def _parse_yaml_scalar(block: str, key: str) -> str | None:
    m = re.search(rf"^{re.escape(key)}:\s*(.+)$", block, re.MULTILINE)
    if not m:
        return None
    value = m.group(1).strip()
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
    elif value.startswith("'") and value.endswith("'"):
        value = value[1:-1]
    return value


def load_agent(path: Path) -> Agent | None:
    """Load a single agent definition from a markdown file with frontmatter.

    Returns ``None`` if the file has no frontmatter or no ``name`` field.
    Missing ``applies_to`` / ``keywords`` is treated as an empty list.
    """

    text = path.read_text(encoding="utf-8")
    m = _FRONTMATTER_RE.match(text)
    if not m:
        return None
    block = m.group(1)
    name = _parse_yaml_scalar(block, "name")
    if not name:
        return None
    return Agent(
        name=name,
        applies_to=tuple(_parse_yaml_list(block, "applies_to")),
        keywords=tuple(_parse_yaml_list(block, "keywords")),
    )


def load_agents(directory: Path) -> list[Agent]:
    """Load all agent definitions from ``directory`` (non-recursive)."""

    agents: list[Agent] = []
    for path in sorted(directory.glob("*.md")):
        agent = load_agent(path)
        if agent is not None:
            agents.append(agent)
    return agents
