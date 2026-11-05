"""Behavior tests for scripts/token-audit/token_audit.py on synthetic transcripts.

Every transcript is built in a temporary directory with totals that can be
worked out by hand; no real session data is stored in the repository.
"""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "token-audit" / "token_audit.py"
spec = importlib.util.spec_from_file_location("token_audit", SCRIPT)
audit = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = audit
spec.loader.exec_module(audit)

PROMPT_MARK = "PROMPT-MARKER-7f3a"
TOOL_MARK = "TOOL-MARKER-9c1d"
DESC_MARK = "DESC-MARKER-2b8e"
TEAMMATE = "teammate-name-5e0f"
DOC = "/work/notes/shared-doc.md"
RULE = "/home/me/.claude/rules/coding/standards.md"


def stamp(minute, second=0):
    # Minutes past 59 roll into the next hour.
    return f"2026-01-01T{10 + minute // 60:02d}:{minute % 60:02d}:{second:02d}.000Z"


def assistant(rid, minute, cw=0, cr=0, inp=0, out=0, think=0, ttl="1h",
              blocks=None, model="claude-test"):
    usage = {
        "input_tokens": inp,
        "cache_creation_input_tokens": cw,
        "cache_read_input_tokens": cr,
        "output_tokens": out,
        "output_tokens_details": {"thinking_tokens": think},
        "cache_creation": {
            "ephemeral_1h_input_tokens": cw if ttl == "1h" else 0,
            "ephemeral_5m_input_tokens": cw if ttl == "5m" else 0,
        },
    }
    return {
        "type": "assistant", "requestId": rid, "timestamp": stamp(minute),
        "message": {"id": "msg_" + rid, "model": model, "usage": usage,
                    "content": blocks or [{"type": "text", "text": "ok"}]},
    }


def tool_use(tool_id, name, **tool_input):
    return {"type": "tool_use", "id": tool_id, "name": name, "input": tool_input}


def tool_result(tool_id, minute, content, error=False):
    block = {"type": "tool_result", "tool_use_id": tool_id, "content": content, "is_error": error}
    return {"type": "user", "timestamp": stamp(minute, 30),
            "message": {"role": "user", "content": [block]}}


def prompt(minute, text):
    return {"type": "user", "timestamp": stamp(minute), "message": {"role": "user", "content": text}}


def rule(uuid, minute, text, raw):
    body = {"path": RULE, "type": "Project", "content": text, "rawContent": raw}
    return {"type": "attachment", "uuid": uuid, "timestamp": stamp(minute, 40),
            "attachment": {"type": "nested_memory", "path": RULE, "content": body}}


def compact(minute, trigger, pre_tokens):
    return {"type": "system", "subtype": "compact_boundary", "timestamp": stamp(minute),
            "compactMetadata": {"trigger": trigger, "preTokens": pre_tokens}}


def read(rid, minute, path, chars, **read_range):
    """A Read request and its text result of the given length."""
    return [assistant(rid, minute, blocks=[tool_use("t-" + rid, "Read", file_path=path, **read_range)]),
            tool_result("t-" + rid, minute, "x" * chars)]


def write(path, records, raw_lines=()):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record) + "\n")
        for line in raw_lines:
            handle.write(line + "\n")


# r1 is logged as three lines, the way a streamed response with three
# content blocks is: same requestId and usage, output growing.
R1_LINES = [
    assistant("r1", 0, inp=10, cw=1000, out=5, think=2, blocks=[{"type": "thinking", "thinking": "plan"}]),
    assistant("r1", 0, inp=10, cw=1000, out=6, think=2, blocks=[{"type": "text", "text": "reading"}]),
    assistant("r1", 0, inp=10, cw=1000, out=7, think=2, blocks=[tool_use("t1", "Read", file_path=DOC)]),
    tool_result("t1", 0, [{"type": "text", "text": "x" * 100},
                          {"type": "image", "source": {"type": "base64", "data": "A" * 5000}}]),
    rule("u1", 0, "R" * 50, "---\npaths: ['**/*.py']\n---\n" + "R" * 50),
]


class TokenAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "projects"
        project = self.root / "proj"
        write(project / "s1.jsonl", [prompt(0, PROMPT_MARK)] + R1_LINES + [
            assistant("r2", 1, cw=200, cr=1000, out=3,
                      blocks=[tool_use("t2", "Bash", command="echo " + TOOL_MARK)]),
            tool_result("t2", 1, TOOL_MARK + " failed", error=True),
            assistant("r3", 2, cw=100, cr=1200, out=4),
            compact(3, "auto", 2300),
            assistant("r4", 4, cw=300, cr=900, out=2),
            assistant("r5", 5, model="<synthetic>"),
        ], raw_lines=["{not json"])
        agents = project / "s1" / "subagents"
        write(agents / "agent-a.jsonl", [
            prompt(10, DESC_MARK + " task text"),
            assistant("a1", 10, cw=500, out=1, ttl="5m", blocks=[tool_use("v1", "Read", file_path=DOC)]),
            tool_result("v1", 10, "y" * 300),
            assistant("a2", 11, cw=10, cr=500, out=1, ttl="5m"),
        ])
        (agents / "agent-a.meta.json").write_text(json.dumps({
            "agentType": TEAMMATE, "spawnedAgentType": "general-purpose",
            "model": "opus", "description": DESC_MARK,
        }), encoding="utf-8")
        write(agents / "agent-b.jsonl", [
            assistant("b1", 12, cw=400, ttl="5m",
                      blocks=[tool_use("w1", "Read", file_path="\\WORK\\notes\\Shared-Doc.md")]),
            tool_result("w1", 12, "z" * 200),
            assistant("b2", 13, cw=10, cr=400, ttl="5m"),
            assistant("b3", 14, cr=410, ttl="5m"),
        ])
        write(project / "s1" / "workflows" / "run1" / "agent-w.jsonl", [
            assistant("x1", 20, cw=50, ttl="5m"),
        ])
        # s2 resumes s1: it starts with verbatim copies of s1's records.
        write(project / "s2.jsonl", R1_LINES + [
            assistant("r6", 30, cw=20, cr=1010, out=1),
        ])
        write(self.root / "proj" / "memory" / "note.jsonl", [assistant("m1", 40, cw=999)])

    def run_audit(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = audit.main(["--projects-dir", str(self.root), *extra])
        return code, out.getvalue()

    def report(self, *extra):
        code, out = self.run_audit("--json", *extra)
        self.assertEqual(code, 0)
        return json.loads(out)

    def test_split_request_is_counted_once(self):
        tokens = self.report()["tokens"]["main"]
        # r1-r4 from s1 and r6 from s2; output takes the last, largest value.
        self.assertEqual(tokens["cache_write"], 1000 + 200 + 100 + 300 + 20)
        self.assertEqual(tokens["cache_write_1h"], 1620)
        self.assertEqual(tokens["cache_read"], 1000 + 1200 + 900 + 1010)
        self.assertEqual(tokens["output"], 7 + 3 + 4 + 2 + 1)
        self.assertEqual(tokens["thinking"], 2)
        self.assertEqual(tokens["input"], 10)

    def test_resumed_copy_is_counted_once(self):
        report = self.report()
        self.assertEqual(report["requests"]["main"], 5)
        self.assertEqual(report["duplicate_requests_skipped"], 1)
        self.assertEqual(report["tools"]["main"]["Read"]["calls"], 1)
        self.assertEqual(report["rules"]["rules/coding/standards.md"]["injections"], 1)
        first = report["first_request_context"]["main"]
        self.assertEqual((first["transcripts"], first["median"]), (1, 1010))

    def test_raw_content_is_ignored(self):
        stats = self.report()["rules"]["rules/coding/standards.md"]
        self.assertEqual(stats["chars"], 50)
        self.assertEqual(stats["residency"], 50 * 2)

    def test_image_blocks_are_excluded(self):
        read = self.report()["tools"]["main"]["Read"]
        self.assertEqual(read["result_chars"], 100)
        self.assertEqual(read["non_text_blocks"], 1)

    def test_residency_stops_at_compaction(self):
        report = self.report()
        # t1 lands after r1; r2 and r3 follow it before the compaction.
        self.assertEqual(report["tools"]["main"]["Read"]["residency"], 100 * 2)
        bash = report["tools"]["main"]["Bash"]
        self.assertEqual((bash["result_chars"], bash["errors"], bash["residency"]), (23, 1, 23))
        self.assertEqual(report["compactions"]["by_trigger"], {"auto": 1})
        self.assertEqual(report["compactions"]["pre_tokens_median"], 2300)

    def test_kinds_synthetic_and_bad_lines(self):
        report = self.report()
        self.assertEqual(report["files"], {"main": 2, "subagent": 2, "workflow": 1})
        self.assertEqual(report["requests"], {"main": 5, "subagent": 5, "workflow": 1})
        self.assertEqual(report["models"]["main"], {"claude-test": 5})
        self.assertEqual(report["bad_lines"], 1)
        self.assertEqual(report["tokens"]["subagent"]["cache_write_5m"], 500 + 10 + 400 + 10)
        self.assertEqual(report["agent_types"], {
            "(none)": {"transcripts": 2, "requests": 4},
            "general-purpose": {"transcripts": 1, "requests": 2},
        })

    def test_prefix_share_and_buckets(self):
        report = self.report()
        # s1: smallest context 1010 over 4 requests; s2: 1030 over 1.
        self.assertAlmostEqual(report["prefix_share"]["main"], (1010 * 4 + 1030) / (4700 + 1030))
        buckets = report["context_buckets"]["main"]
        self.assertEqual(buckets[0], {"range": "<100k", "requests": 5, "cached_share": 1.0})

    def test_time_window(self):
        late = self.report("--since", "2026-01-01T10:03:30Z")
        self.assertEqual(late["requests"]["main"], 2)
        self.assertEqual(late["compactions"]["by_trigger"], {})
        early = self.report("--until", "2026-01-01T10:01:30Z")
        self.assertEqual(early["requests"]["main"], 2)
        self.assertEqual(early["tools"]["main"]["Bash"]["residency"], 0)

    def test_exclude_session(self):
        report = self.report("--exclude-session", "s1")
        self.assertEqual(report["files"], {"main": 1, "subagent": 0, "workflow": 0})
        self.assertEqual(report["requests"]["main"], 2)
        self.assertEqual(report["duplicate_requests_skipped"], 0)

    def test_sibling_reads(self):
        reads = self.report()["sibling_reads"]
        self.assertEqual(reads["agent_read_chars"], 500)
        # agent-a: 300 chars, 1 later request; agent-b: 200 chars, 2 later.
        self.assertEqual(reads["agent_read_residency"], 300 + 400)
        self.assertEqual(reads["read_by_main_share"], 1.0)
        self.assertEqual((reads["paths_read_by_siblings"], reads["extra_readers"]), (1, 1))
        self.assertEqual((reads["extra_chars"], reads["extra_residency"]), (200, 400))
        self.assertNotIn("top_paths", reads)

    def test_output_has_no_transcript_content(self):
        for extra in ((), ("--json",)):
            code, out = self.run_audit(*extra)
            self.assertEqual(code, 0)
            for marker in (PROMPT_MARK, TOOL_MARK, DESC_MARK, TEAMMATE, "shared-doc"):
                self.assertNotIn(marker, out)
        code, out = self.run_audit("--show-paths")
        self.assertIn("shared-doc", out)

    def test_session_filter(self):
        report = self.report("--session", "s1")
        self.assertEqual(report["files"], {"main": 1, "subagent": 2, "workflow": 1})
        self.assertEqual(report["requests"], {"main": 4, "subagent": 5, "workflow": 1})
        # Without s1, the records s2 copied from it are no longer copies.
        report = self.report("--session", "s2")
        self.assertEqual(report["files"], {"main": 1, "subagent": 0, "workflow": 0})
        self.assertEqual(report["requests"]["main"], 2)
        self.assertEqual(report["duplicate_requests_skipped"], 0)
        report = self.report("--session", "s1", "--session", "s2")
        self.assertEqual(report["requests"]["main"], 5)
        report = self.report("--session", "s1", "--exclude-session", "s1")
        self.assertEqual(report["files"], {"main": 0, "subagent": 0, "workflow": 0})

    def test_compaction_causes(self):
        write(self.root / "causes" / "c.jsonl", [
            assistant("c1", 0, cw=10),
            compact(55, "auto", 300_000),   # 55 minutes after c1: idle
            assistant("c2", 56, cw=10),
            compact(57, "auto", 900_000),   # 1 minute after c2: threshold
            assistant("c3", 58, cw=10),
            compact(59, "manual", 500_000),
            assistant("c4", 60, cw=10),
            compact(61, "auto", 960_000),   # 1 minute after c4, in the next hour
        ])
        c = self.report("--project", "causes")["compactions"]
        self.assertEqual(c["by_trigger"], {"auto": 3, "manual": 1})
        self.assertEqual(c["by_cause"], {
            "idle": {"count": 1, "pre_tokens_median": 300_000},
            "manual": {"count": 1, "pre_tokens_median": 500_000},
            "threshold": {"count": 2, "pre_tokens_median": 930_000},
        })
        # The default fixture's one auto compaction follows r3 by a minute.
        c = self.report("--project", "proj")["compactions"]
        self.assertEqual(c["by_cause"], {"threshold": {"count": 1, "pre_tokens_median": 2300}})

    def test_rereads_after_compaction(self):
        marker = "/w/REREAD-MARKER-4d2c.md"
        write(self.root / "rr" / "m.jsonl", [
            *read("m1", 1, marker, 300),
            *read("m2", 1, "/w/b.md", 300),
            *read("m3", 1, "/w/c.md", 300, offset=1),
            *read("m4", 1, "/w/d.md", 300),
            compact(2, "manual", 1000),
            # Counted: same range, other spelling of the path.
            *read("m5", 3, marker.upper().replace("/", "\\"), 400),
            # Not counted: an edit of the path comes in between.
            assistant("m6", 3, blocks=[tool_use("e1", "Edit", file_path="/w/b.md")]),
            tool_result("e1", 3, "edited"),
            *read("m7", 4, "/w/b.md", 300),
            # Not counted: another range, and a short unchanged-file notice.
            *read("m8", 4, "/w/c.md", 300, offset=2),
            *read("m9", 4, "/w/d.md", 50),
            # Not counted: read twice with no compaction in between.
            *read("m10", 5, "/w/e.md", 300),
            *read("m11", 5, "/w/e.md", 300),
        ])
        write(self.root / "rr" / "m" / "subagents" / "agent-s.jsonl", [
            *read("s1", 10, "/w/s.md", 300),
            compact(11, "auto", 2000),
            *read("s2", 12, "/w/s.md", 300),
        ])
        report = self.report("--project", "rr")
        self.assertEqual(report["compactions"]["rereads"], {
            "main": {"reads": 1, "chars": 400},
            "subagent": {"reads": 1, "chars": 300},
            "workflow": {"reads": 0, "chars": 0},
        })
        for extra in ((), ("--json",)):
            code, out = self.run_audit("--project", "rr", *extra)
            self.assertEqual(code, 0)
            self.assertNotIn("REREAD-MARKER", out.upper())

    def test_missing_directory(self):
        code, _ = self.run_audit("--project", "proj")
        self.assertEqual(code, 0)
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = audit.main(["--projects-dir", str(self.root / "absent")])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
