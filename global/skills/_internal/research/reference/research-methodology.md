# Research Methodology Guide

Detailed guidance for each research depth level and search strategies.

## Depth Level Specifications

### Shallow

**Goal**: Quick overview for orientation or simple fact-checking.

**Search strategy**:
1. Formulate 1-2 broad queries covering the topic.
2. Scan top 3-5 results for key facts.
3. In codebase: run 1-2 targeted `Grep` searches.

**Time budget**: Under 5 minutes of active research.

**Output scope**: 4-5 sections, 200-400 lines.

**When to use**:
- Quick technology name lookups
- Verifying a single claim or version number
- Getting a high-level overview before deeper research

### Standard

**Goal**: Balanced investigation suitable for technical decisions.

**Search strategy**:
1. Formulate 3-5 queries from different angles:
   - Direct topic query
   - Comparison/alternatives query
   - Best practices/patterns query
   - Known issues/limitations query
   - Recent developments query (include current year)
2. Deep-read 3-5 authoritative pages via `WebFetch`.
3. In codebase: pattern analysis with `Grep` + `Glob`, read key files.

**Time budget**: 10-20 minutes of active research.

**Output scope**: 6-8 sections, 400-800 lines.

**When to use**:
- Technology selection decisions
- Implementation approach research
- Pre-issue research for medium features
- Security or performance pre-investigation

### Deep

**Goal**: Comprehensive investigation for critical decisions or reference documentation.

**Search strategy**:
1. Formulate 8-12 queries systematically:
   - Core concept queries (2-3)
   - Implementation/architecture queries (2-3)
   - Comparison/alternatives queries (2-3)
   - Edge cases/limitations queries (1-2)
   - Future direction/roadmap queries (1-2)
2. Deep-read 8-12 pages, including academic papers or RFCs where relevant.
3. In codebase: full architecture analysis, dependency mapping, usage patterns.

**Time budget**: 30-60 minutes of active research.

**Output scope**: 8+ sections, 800+ lines.

**When to use**:
- Architecture decisions with long-term impact
- Regulatory or compliance research
- Creating permanent reference documentation
- Competitive landscape analysis

## Search Query Formulation

### Effective Query Patterns

| Pattern | Example | When to Use |
|---------|---------|-------------|
| Direct | `"WebSocket protocol specification"` | Looking for authoritative source |
| Comparative | `"WebSocket vs SSE vs long polling comparison 2026"` | Evaluating alternatives |
| Problem-oriented | `"WebSocket scaling challenges production"` | Understanding limitations |
| Implementation | `"WebSocket implementation best practices Node.js"` | Finding practical guidance |
| Recent | `"WebSocket developments 2026"` | Time-sensitive information |

### Query Refinement

If initial queries return insufficient results:

1. **Broaden**: Remove specific qualifiers (e.g., drop version numbers).
2. **Rephrase**: Use alternative terminology (e.g., "real-time communication" instead of "WebSocket").
3. **Decompose**: Split complex topic into sub-queries.
4. **Domain-filter**: Add domain-specific terms (e.g., "medical device" for regulatory topics).

### Year-Aware Searching

For technology topics, include the current year in at least one query to capture recent developments. Avoid queries that return only outdated results.

## Codebase Research Strategies

### Pattern Discovery

```
1. Glob: Find files matching the topic (e.g., *.config.*, *auth*, *websocket*)
2. Grep: Search for topic-related keywords in source code
3. Read: Examine key files for implementation details
4. Trace: Follow imports/dependencies for architecture understanding
```

### Architecture Mapping

For `--depth deep` with `--sources code` or `--sources both`:

1. Identify entry points related to the topic.
2. Trace call chains and data flow.
3. Map dependencies (internal and external).
4. Document configuration and environment dependencies.
5. Note test coverage for the topic area.

## Parallel Research Execution

For `standard` and `deep` depths, use the `Agent` tool to parallelize independent research streams:

```
Example: Researching "gRPC vs REST for microservices"

Stream 1 (Agent): Web search for gRPC advantages, performance benchmarks
Stream 2 (Agent): Web search for REST maturity, tooling ecosystem
Stream 3 (main): Codebase analysis for existing API patterns
```

Merge results after all streams complete. Resolve any contradictions found between streams.
