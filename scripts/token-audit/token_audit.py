#!/usr/bin/env python3
"""Measure where Claude Code tokens go, from local session transcripts.

Reads the JSONL transcripts that Claude Code keeps under ~/.claude/projects/
and prints aggregates only. No prompt, tool result, file content or task
description is printed, and file paths appear only with --show-paths.

Characters are never converted to tokens. The ratio depends on language and
content, so a converted figure would not be a measurement.

Usage:
  python3 scripts/token-audit/token_audit.py [--projects-dir DIR]
      [--project NAME] [--since ISO] [--until ISO]
      [--exclude-session ID ...] [--json] [--show-paths]
"""

import argparse
import json
import os
import statistics
import sys
from collections import defaultdict
from datetime import datetime, timezone

KINDS = ("main", "subagent", "workflow")
AGENT_KINDS = ("subagent", "workflow")
BUCKETS = (
    (0, 100_000, "<100k"),
    (100_000, 200_000, "100-200k"),
    (200_000, 300_000, "200-300k"),
    (300_000, 500_000, "300-500k"),
    (500_000, 700_000, "500-700k"),
    (700_000, None, ">=700k"),
)
TOKEN_FIELDS = ("input", "cache_write", "cache_write_1h", "cache_write_5m",
                "cache_read", "output", "thinking")
SYNTHETIC_MODEL = "<synthetic>"
TOP_PATHS = 10


def parse_time(value):
    """Parse an ISO 8601 timestamp; a value without a zone is taken as UTC."""
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def classify(parts):
    """Return (kind, session) for a transcript path relative to its project dir."""
    if len(parts) == 1:
        return "main", parts[0][:-len(".jsonl")]
    if "workflows" in parts:
        return "workflow", parts[0]
    return "subagent", parts[0]


def iter_transcripts(projects_dir, project=None):
    """Yield (parts, path) for every transcript, main transcripts first."""
    for name in sorted(os.listdir(projects_dir)):
        root = os.path.join(projects_dir, name)
        if not os.path.isdir(root) or (project and name != project):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            # memory/ holds notes, not transcripts.
            dirnames[:] = sorted(d for d in dirnames if d != "memory")
            for filename in sorted(filenames):
                if filename.endswith(".jsonl"):
                    path = os.path.join(dirpath, filename)
                    rel = os.path.relpath(path, root).replace(os.sep, "/")
                    yield rel.split("/"), path


def normalize_path(path):
    return (path or "").replace("\\", "/").lower()


def rule_key(path):
    """Name an injected rule by its path under .claude/, else by file name."""
    norm = (path or "").replace("\\", "/")
    index = norm.lower().rfind("/.claude/")
    if index >= 0:
        return norm[index + len("/.claude/"):]
    return norm.rsplit("/", 1)[-1] or "(unknown)"


def result_size(content):
    """Return (text characters, non-text blocks) of a tool_result content."""
    if isinstance(content, str):
        return len(content), 0
    chars = other = 0
    for block in content or []:
        if isinstance(block, dict) and block.get("type") == "text":
            chars += len(block.get("text") or "")
        else:
            # Image and document blocks: their token cost does not follow
            # the base64 length, so they are counted, not measured.
            other += 1
    return chars, other


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return None
    return ordered[min(len(ordered) - 1, int(fraction * len(ordered)))]


def read_meta(path):
    """Agent definition name and model from a subagent .meta.json, if any."""
    meta_path = path[:-len(".jsonl")] + ".meta.json"
    try:
        with open(meta_path, encoding="utf-8") as handle:
            meta = json.load(handle)
    except (OSError, ValueError):
        return "(none)"
    # spawnedAgentType names the definition; agentType can be a teammate
    # name chosen for one task, which is not printed.
    return meta.get("spawnedAgentType") or meta.get("agentType") or "(none)"


class Transcript:
    """Per-file state while one transcript is read in line order."""

    def __init__(self, kind, session, path):
        self.kind = kind
        self.session = session
        self.path = path
        self.requests = {}      # requestId -> counted request dict, or None
        self.count = 0          # counted requests so far
        self.segment = 0
        self.segment_end = []   # request count at the end of each segment
        self.pending = []       # (segment, count at event, chars, target)
        self.tool_uses = {}     # tool_use_id -> (name, read path or None)
        self.first = None       # first counted-or-not request of the file
        self.resumed = False    # copied requests came before the first new one
        self.contexts = []
        self.cached = 0         # cache read + cache write of counted requests


class Audit:
    def __init__(self, since=None, until=None, show_paths=False):
        self.since = since
        self.until = until
        self.show_paths = show_paths
        self.seen_requests = set()
        self.seen_attachments = set()
        self.files = defaultdict(int)
        self.bad_lines = 0
        self.duplicate_requests = 0
        self.first_ts = None
        self.last_ts = None
        self.tokens = {k: dict.fromkeys(TOKEN_FIELDS, 0) for k in KINDS}
        self.requests = dict.fromkeys(KINDS, 0)
        self.models = {k: defaultdict(int) for k in KINDS}
        self.agent_types = defaultdict(lambda: {"transcripts": 0, "requests": 0})
        self.buckets = {k: [[0, 0] for _ in BUCKETS] for k in KINDS}
        self.prefix = {k: [0, 0] for k in KINDS}
        self.first_contexts = {k: [] for k in KINDS}
        self.tools = {k: defaultdict(lambda: defaultdict(int)) for k in KINDS}
        self.rules = defaultdict(lambda: defaultdict(int))
        self.compactions = defaultdict(int)
        self.pre_tokens = []
        self.agent_reads = defaultdict(lambda: defaultdict(dict))
        self.main_reads = defaultdict(set)

    def in_window(self, ts):
        if self.since is None and self.until is None:
            return True
        if ts is None:
            return False
        if self.since is not None and ts < self.since:
            return False
        return self.until is None or ts < self.until

    # -- reading ---------------------------------------------------------

    def add_transcript(self, kind, session, path):
        self.files[kind] += 1
        state = Transcript(kind, session, path)
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                try:
                    record = json.loads(line)
                except ValueError:
                    self.bad_lines += 1
                    continue
                if isinstance(record, dict):
                    self._dispatch(state, record)
        self._finish(state)

    def _dispatch(self, state, record):
        kind = record.get("type")
        if kind == "assistant":
            self._assistant(state, record)
        elif kind == "user":
            self._user(state, record)
        elif kind == "attachment":
            self._attachment(state, record)
        elif kind == "system" and record.get("subtype") == "compact_boundary":
            self._compaction(state, record)

    def _assistant(self, state, record):
        message = record.get("message") or {}
        usage = message.get("usage") or {}
        request_id = record.get("requestId") or message.get("id")
        if request_id in state.requests:
            request = state.requests[request_id]
        else:
            request = self._new_request(state, record, message, usage, request_id)
        if request is None:
            return
        # A request is logged once per content block, each line repeating
        # the usage; output grows while the response streams.
        details = usage.get("output_tokens_details") or {}
        request["output"] = max(request["output"], usage.get("output_tokens") or 0)
        request["thinking"] = max(request["thinking"], details.get("thinking_tokens") or 0)
        for block in message.get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                self._tool_use(state, block)

    def _new_request(self, state, record, message, usage, request_id):
        if request_id in self.seen_requests:
            # A resumed session copies its parent's requests verbatim.
            self.duplicate_requests += 1
            state.requests[request_id] = None
            if state.first is None:
                state.resumed = True
            return None
        if message.get("model") == SYNTHETIC_MODEL:
            state.requests[request_id] = None
            return None
        self.seen_requests.add(request_id)
        created = usage.get("cache_creation") or {}
        request = {
            "kind": state.kind,
            "input": usage.get("input_tokens") or 0,
            "cache_write": usage.get("cache_creation_input_tokens") or 0,
            "cache_write_1h": created.get("ephemeral_1h_input_tokens") or 0,
            "cache_write_5m": created.get("ephemeral_5m_input_tokens") or 0,
            "cache_read": usage.get("cache_read_input_tokens") or 0,
            "output": 0,
            "thinking": 0,
            "model": message.get("model") or "(unknown)",
        }
        request["context"] = request["input"] + request["cache_write"] + request["cache_read"]
        timestamp = parse_time(record.get("timestamp"))
        counted = self.in_window(timestamp)
        if state.first is None:
            state.first = (request["context"], counted)
        if not counted:
            state.requests[request_id] = None
            return None
        state.requests[request_id] = request
        state.count += 1
        state.contexts.append(request["context"])
        state.cached += request["cache_read"] + request["cache_write"]
        self.requests[state.kind] += 1
        self.models[state.kind][request["model"]] += 1
        if timestamp is not None:
            self.first_ts = min(self.first_ts or timestamp, timestamp)
            self.last_ts = max(self.last_ts or timestamp, timestamp)
        return request

    def _tool_use(self, state, block):
        name = block.get("name") or "(unknown)"
        tool_input = block.get("input") or {}
        read_path = tool_input.get("file_path") if name == "Read" else None
        state.tool_uses[block.get("id")] = (name, read_path)
        self.tools[state.kind][name]["calls"] += 1

    def _user(self, state, record):
        content = (record.get("message") or {}).get("content")
        if not isinstance(content, list):
            return
        for block in content:
            if not (isinstance(block, dict) and block.get("type") == "tool_result"):
                continue
            # Only results of counted requests are measured.
            issued = state.tool_uses.pop(block.get("tool_use_id"), None)
            if issued is None:
                continue
            name, read_path = issued
            chars, other = result_size(block.get("content"))
            stats = self.tools[state.kind][name]
            stats["result_chars"] += chars
            stats["non_text_blocks"] += other
            failed = bool(block.get("is_error"))
            stats["errors"] += failed
            state.pending.append((state.segment, state.count, chars, stats))
            if read_path and not failed:
                self._read(state, read_path, chars)

    def _read(self, state, read_path, chars):
        path = normalize_path(read_path)
        if state.kind == "main":
            self.main_reads[state.session].add(path)
            return
        per_file = self.agent_reads[state.session][path]
        entry = per_file.setdefault(state.path, {"chars": 0, "residency": 0})
        entry["chars"] += chars
        state.pending.append((state.segment, state.count, chars, entry))

    def _attachment(self, state, record):
        attachment = record.get("attachment") or {}
        if attachment.get("type") != "nested_memory":
            return
        uuid = record.get("uuid")
        if uuid is not None:
            if uuid in self.seen_attachments:
                return
            self.seen_attachments.add(uuid)
        if not self.in_window(parse_time(record.get("timestamp"))):
            return
        body = attachment.get("content")
        path = attachment.get("path")
        if isinstance(body, dict):
            path = path or body.get("path")
            # rawContent repeats the file with its frontmatter; only
            # content is sent to the model.
            text = body.get("content") or ""
        else:
            text = body if isinstance(body, str) else ""
        stats = self.rules[rule_key(path)]
        stats["injections"] += 1
        stats["chars"] += len(text)
        state.pending.append((state.segment, state.count, len(text), stats))

    def _compaction(self, state, record):
        if self.in_window(parse_time(record.get("timestamp"))):
            meta = record.get("compactMetadata") or {}
            self.compactions[meta.get("trigger") or "unknown"] += 1
            if meta.get("preTokens"):
                self.pre_tokens.append(meta["preTokens"])
        state.segment_end.append(state.count)
        state.segment += 1

    def _finish(self, state):
        state.segment_end.append(state.count)
        for segment, count, chars, target in state.pending:
            target["residency"] += chars * (state.segment_end[segment] - count)
        for request in state.requests.values():
            if request is not None:
                self._add_request(state.kind, request)
        if state.contexts:
            self.prefix[state.kind][0] += min(state.contexts) * len(state.contexts)
            self.prefix[state.kind][1] += state.cached
        # A resumed session starts with its parent's whole history, so its
        # first new request does not show the fixed prefix.
        if state.first is not None and state.first[1] and not state.resumed:
            self.first_contexts[state.kind].append(state.first[0])
        if state.kind != "main":
            agent = self.agent_types[read_meta(state.path)]
            agent["transcripts"] += 1
            agent["requests"] += state.count

    def _add_request(self, kind, request):
        totals = self.tokens[kind]
        for field in TOKEN_FIELDS:
            totals[field] += request[field]
        cached = request["cache_read"] + request["cache_write"]
        for index, (low, high, _) in enumerate(BUCKETS):
            if request["context"] >= low and (high is None or request["context"] < high):
                self.buckets[kind][index][0] += 1
                self.buckets[kind][index][1] += cached
                break

    # -- reporting -------------------------------------------------------

    def report(self):
        return {
            "window": {
                "since": self.since.isoformat() if self.since else None,
                "until": self.until.isoformat() if self.until else None,
                "first_request": self.first_ts.isoformat() if self.first_ts else None,
                "last_request": self.last_ts.isoformat() if self.last_ts else None,
            },
            "files": {k: self.files[k] for k in KINDS},
            "bad_lines": self.bad_lines,
            "duplicate_requests_skipped": self.duplicate_requests,
            "requests": dict(self.requests),
            "tokens": self.tokens,
            "models": {k: dict(v) for k, v in self.models.items()},
            "agent_types": {k: dict(v) for k, v in sorted(self.agent_types.items())},
            "first_request_context": self._first_request_report(),
            "prefix_share": self._prefix_report(),
            "context_buckets": self._bucket_report(),
            "tools": {k: {name: dict(stats) for name, stats in sorted(v.items())}
                      for k, v in self.tools.items()},
            "rules": {k: dict(v) for k, v in sorted(self.rules.items())},
            "sibling_reads": self._sibling_report(),
            "compactions": {
                "by_trigger": dict(self.compactions),
                "pre_tokens_median": statistics.median(self.pre_tokens) if self.pre_tokens else None,
            },
        }

    def _first_request_report(self):
        out = {}
        for kind in KINDS:
            values = self.first_contexts[kind]
            out[kind] = {
                "transcripts": len(values),
                "median": statistics.median(values) if values else None,
                "p10": percentile(values, 0.1),
                "p90": percentile(values, 0.9),
            }
        return out

    def _prefix_report(self):
        out = {}
        for kind in KINDS:
            numerator, cached = self.prefix[kind]
            out[kind] = numerator / cached if cached else None
        numerator = sum(v[0] for v in self.prefix.values())
        cached = sum(v[1] for v in self.prefix.values())
        out["all"] = numerator / cached if cached else None
        return out

    def _bucket_report(self):
        out = {}
        for kind in KINDS:
            total = sum(cached for _, cached in self.buckets[kind])
            out[kind] = [
                {"range": label, "requests": count, "cached_share": cached / total if total else None}
                for (_, _, label), (count, cached) in zip(BUCKETS, self.buckets[kind])
            ]
        return out

    def _sibling_report(self):
        read_chars = read_residency = by_main = 0
        extra_chars = extra_residency = paths = extra_readers = 0
        top = []
        for session, by_path in self.agent_reads.items():
            for path, by_file in by_path.items():
                chars = sum(e["chars"] for e in by_file.values())
                residency = sum(e["residency"] for e in by_file.values())
                read_chars += chars
                read_residency += residency
                if path in self.main_reads[session]:
                    by_main += chars
                if len(by_file) < 2:
                    continue
                keep = max(by_file.values(), key=lambda e: e["chars"])
                extra_chars += chars - keep["chars"]
                extra_residency += residency - keep["residency"]
                paths += 1
                extra_readers += len(by_file) - 1
                top.append((residency - keep["residency"], len(by_file), chars - keep["chars"], path))
        report = {
            "agent_read_chars": read_chars,
            "agent_read_residency": read_residency,
            "read_by_main_share": by_main / read_chars if read_chars else None,
            "paths_read_by_siblings": paths,
            "extra_readers": extra_readers,
            "extra_chars": extra_chars,
            "extra_residency": extra_residency,
        }
        if self.show_paths:
            top.sort(reverse=True)
            report["top_paths"] = [
                {"path": p, "readers": n, "extra_chars": c, "extra_residency": r}
                for r, n, c, p in top[:TOP_PATHS]
            ]
        return report


def number(value):
    if value is None:
        return "-"
    if isinstance(value, float) and not value.is_integer():
        return f"{value:,.1f}"
    return f"{int(value):,}"


def share(value):
    return "-" if value is None else f"{value:.1%}"


def render_text(report):
    lines = []
    window = report["window"]
    lines.append(f"Requests from {window['first_request'] or '-'} to {window['last_request'] or '-'}")
    lines.append("Files: " + ", ".join(f"{k} {v}" for k, v in report["files"].items())
                 + f"; unreadable lines {report['bad_lines']}; copied requests skipped {report['duplicate_requests_skipped']}")
    lines.append("")
    lines.append("Tokens by kind")
    for kind in KINDS:
        t = report["tokens"][kind]
        lines.append(f"  {kind:<9} requests {number(report['requests'][kind]):>9}  cache read {number(t['cache_read']):>16}"
                     f"  cache write {number(t['cache_write']):>13} (1h {number(t['cache_write_1h'])}, 5m {number(t['cache_write_5m'])})"
                     f"  output {number(t['output']):>12} (thinking {number(t['thinking'])})  input {number(t['input'])}")
    lines.append("")
    lines.append("First-request context (tokens) and prefix share of cached input")
    for kind in KINDS:
        f = report["first_request_context"][kind]
        lines.append(f"  {kind:<9} transcripts {f['transcripts']:>5}  median {number(f['median']):>9}  p10 {number(f['p10']):>9}"
                     f"  p90 {number(f['p90']):>9}  prefix share {share(report['prefix_share'][kind])}")
    lines.append(f"  all prefix share {share(report['prefix_share']['all'])}")
    lines.append("")
    lines.append("Context-size buckets (requests, share of cached input)")
    for kind in KINDS:
        cells = "  ".join(f"{b['range']} {number(b['requests'])} ({share(b['cached_share'])})"
                          for b in report["context_buckets"][kind])
        lines.append(f"  {kind:<9} {cells}")
    lines.append("")
    lines.append("Tools (calls, result chars, chars x later requests, errors)")
    for kind in KINDS:
        tools = sorted(report["tools"][kind].items(), key=lambda kv: -kv[1].get("residency", 0))
        for name, s in tools:
            lines.append(f"  {kind:<9} {name:<28} {number(s.get('calls', 0)):>8} {number(s.get('result_chars', 0)):>14}"
                         f" {number(s.get('residency', 0)):>18} {number(s.get('errors', 0)):>6}")
    lines.append("")
    lines.append("Path-triggered rules (injections, chars, chars x later requests)")
    for rule, s in sorted(report["rules"].items(), key=lambda kv: -kv[1].get("residency", 0)):
        lines.append(f"  {rule:<52} {number(s['injections']):>6} {number(s['chars']):>12} {number(s.get('residency', 0)):>16}")
    lines.append("")
    s = report["sibling_reads"]
    lines.append("Reads by subagents and workflows")
    lines.append(f"  read chars {number(s['agent_read_chars'])}, chars x later requests {number(s['agent_read_residency'])},"
                 f" share of chars also read by the parent session {share(s['read_by_main_share'])}")
    lines.append(f"  paths read by more than one sibling {number(s['paths_read_by_siblings'])}, extra readers {number(s['extra_readers'])},"
                 f" extra chars {number(s['extra_chars'])}, extra chars x later requests {number(s['extra_residency'])}")
    for entry in s.get("top_paths", []):
        lines.append(f"    {entry['readers']:>3} readers  extra {number(entry['extra_chars']):>11}  {entry['path']}")
    lines.append("")
    c = report["compactions"]
    lines.append("Compactions: " + (", ".join(f"{k} {v}" for k, v in sorted(c["by_trigger"].items())) or "none")
                 + f"; median tokens before compaction {number(c['pre_tokens_median'])}")
    return "\n".join(lines)


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Aggregate token use from Claude Code transcripts.")
    parser.add_argument("--projects-dir", default=os.path.join("~", ".claude", "projects"))
    parser.add_argument("--project", help="one folder under the projects dir (default: all)")
    parser.add_argument("--since", help="count requests at or after this UTC ISO 8601 time")
    parser.add_argument("--until", help="count requests before this UTC ISO 8601 time")
    parser.add_argument("--exclude-session", action="append", default=[], metavar="ID")
    parser.add_argument("--json", action="store_true", help="print the report as JSON")
    parser.add_argument("--show-paths", action="store_true", help="list file paths read by sibling subagents")
    return parser.parse_args(argv)


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        # A cp949 console cannot encode every character of a report.
        sys.stdout.reconfigure(encoding="utf-8")
    args = parse_args(argv)
    projects_dir = os.path.expanduser(args.projects_dir)
    if not os.path.isdir(projects_dir):
        print(f"token_audit: no such directory: {projects_dir}", file=sys.stderr)
        return 2
    since, until = parse_time(args.since), parse_time(args.until)
    if (args.since and since is None) or (args.until and until is None):
        print("token_audit: --since/--until must be ISO 8601 times", file=sys.stderr)
        return 2
    audit = Audit(since=since, until=until, show_paths=args.show_paths)
    excluded = set(args.exclude_session)
    for parts, path in iter_transcripts(projects_dir, args.project):
        kind, session = classify(parts)
        if session not in excluded:
            audit.add_transcript(kind, session, path)
    report = audit.report()
    print(json.dumps(report, indent=2) if args.json else render_text(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
