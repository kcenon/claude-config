# Module Priority and Loading Strategy

> ⚠️ **CUSTOM EXTENSION / DESIGN CONCEPT**
>
> This document describes a **design concept** that is **NOT implemented** by Claude Code.
> It serves as architectural reference only. Claude Code does not have built-in priority-based
> module loading or dynamic loading capabilities as described here.
>
> For official token optimization methods, see [TOKEN_OPTIMIZATION.md](../TOKEN_OPTIMIZATION.md).

> **Type**: Design Document (Conceptual Architecture)
> **Version**: 1.3.0 (Phase 2 Design)
> **Purpose**: Conceptual design for priority-based module loading
> **Status**: Design concept only - not implemented

## Overview

This document defines the priority-based module loading system that enables dynamic, incremental loading of guideline modules based on actual need during command execution.

## Priority Levels

### Level 0: Critical (Always Load Immediately)

Load before any processing begins:

```yaml
level_0_critical:
  - core/environment.md          # 500 tokens - Timezone, locale
  - core/communication.md        # 800 tokens - Language settings

  total: ~1,300 tokens
  load_time: <100ms
```

**Why critical**: Required for basic user interaction and context understanding.

### Level 1: Essential (Load on Command Parse)

Load after command is identified:

```yaml
level_1_essential:
  # Git workflow commands
  git_commands:
    - workflow/git-commit-format.md     # 3,000 tokens

  # GitHub issue commands
  issue_commands:
    - workflow/github-issue-5w1h.md    # 4,500 tokens

  # GitHub PR commands
  pr_commands:
    - workflow/github-pr-5w1h.md       # 4,200 tokens

  # All commands
  all_commands:
    - core/problem-solving.md          # 600 tokens
    - core/common-commands.md          # 1,200 tokens

  load_time: <200ms
```

**Why essential**: Core functionality for the identified command type.

### Level 2: Contextual (Load on Intent Analysis)

Load after analyzing user intent and context:

```yaml
level_2_contextual:
  # Code implementation tasks
  code_implementation:
    - coding/general.md              # 5,000 tokens
    - coding/quality.md              # 4,500 tokens
    - coding/error-handling.md       # 4,000 tokens

  # Performance tasks
  performance_optimization:
    - coding/performance.md          # 6,000 tokens
    - operations/monitoring.md       # 5,500 tokens

  # Security tasks
  security_review:
    - security.md                    # 7,000 tokens

  # Testing tasks
  test_development:
    - project-management/testing.md  # 5,000 tokens

  load_time: <300ms
```

**Why contextual**: Only needed for specific task types.

### Level 3: Reference (Load on Explicit Need)

Load only when explicitly required:

```yaml
level_3_reference:
  # Issue management
  issue_management:
    - workflow/reference/label-definitions.md      # 6,000 tokens
    - workflow/reference/issue-examples.md         # 8,000 tokens
    - workflow/reference/automation-patterns.md    # 9,000 tokens

  # Advanced patterns
  advanced_coding:
    - coding/concurrency.md          # 12,000 tokens
    - coding/memory.md               # 10,000 tokens

  # API design
  api_development:
    - api/api-design.md              # 8,000 tokens
    - api/logging.md                 # 6,000 tokens
    - api/observability.md           # 7,000 tokens

  load_time: <500ms (lazy load)
```

**Why reference**: Large documents needed only for specific scenarios.

### Level 4: Archive (Never Auto-Load)

Load only via explicit `@load:` directive:

```yaml
level_4_archive:
  - operations/cleanup.md            # 8,000 tokens
  - project-management/build.md      # 9,000 tokens
  - documentation.md                 # 7,000 tokens

  # Load via: @load: operations/cleanup
```

**Why archive**: Rarely needed, user can explicitly request.

## Dynamic Loading Algorithm

### Phase 2 Implementation

```python
class DynamicModuleLoader:
    """Implements incremental module loading"""

    def __init__(self):
        self.loaded_modules = {}
        self.priority_cache = {}

    def load_for_command(self, command: str, user_message: str):
        """Load modules dynamically based on command and context"""

        # Stage 1: Load Critical (Level 0)
        # Always loaded, ~1,300 tokens
        modules = self.load_level_0()

        # Stage 2: Parse Command
        command_type = self.parse_command(command)

        # Stage 3: Load Essential (Level 1)
        # Command-specific essentials, ~5,000 tokens
        modules += self.load_level_1(command_type)

        # Stage 4: Analyze Intent
        intent = self.analyze_intent(user_message, modules)

        # Stage 5: Load Contextual (Level 2) if needed
        # Task-specific modules, ~5,000-7,000 tokens
        if intent.requires_additional_context:
            modules += self.load_level_2(intent)

        # Stage 6: Reference modules (Level 3) loaded on-demand
        # Only when processing requires them
        # Implemented via lazy loading during response generation

        return modules

    def load_level_0(self):
        """Load critical modules immediately"""
        return [
            'core/environment.md',
            'core/communication.md'
        ]

    def load_level_1(self, command_type):
        """Load essential modules for command type"""
        command_modules = {
            'commit': ['workflow/git-commit-format.md'],
            'issue': [
                'workflow/github-issue-5w1h.md',
                'core/problem-solving.md',
                'core/common-commands.md'
            ],
            'pr': [
                'workflow/github-pr-5w1h.md',
                'workflow/git-commit-format.md',
                'core/problem-solving.md'
            ],
            # ... other command types
        }

        return command_modules.get(command_type, [])

    def load_level_2(self, intent):
        """Load contextual modules based on intent"""
        contextual_modules = []

        if intent.is_code_implementation:
            contextual_modules += [
                'coding/general.md',
                'coding/quality.md',
                'coding/error-handling.md'
            ]

        if intent.is_performance_task:
            contextual_modules += [
                'coding/performance.md',
                'operations/monitoring.md'
            ]

        if intent.is_security_task:
            contextual_modules.append('security.md')

        return contextual_modules

    def lazy_load(self, module_path):
        """Load reference modules only when needed"""
        if module_path not in self.loaded_modules:
            self.loaded_modules[module_path] = load_module(module_path)

        return self.loaded_modules[module_path]
```

## Intent Analysis Rules

### Code Implementation Intent

Triggers Level 2 loading of coding standards:

```python
def detect_code_implementation(message: str) -> bool:
    """Detect if user wants to write/modify code"""

    implementation_keywords = [
        'implement', 'write', 'create', 'add function',
        'add method', 'add class', 'modify', 'change code',
        'refactor', 'update implementation'
    ]

    # Check for file patterns
    code_file_patterns = [
        r'\.\w+$',  # Any file extension
        r'\.py$', r'\.js$', r'\.ts$', r'\.cpp$', r'\.h$'
    ]

    return (
        any(kw in message.lower() for kw in implementation_keywords) or
        any(re.search(pattern, message) for pattern in code_file_patterns)
    )
```

### Performance Task Intent

Triggers Level 2 loading of performance modules:

```python
def detect_performance_task(message: str) -> bool:
    """Detect if user wants performance optimization"""

    performance_keywords = [
        'optimize', 'performance', 'slow', 'faster', 'speed up',
        'bottleneck', 'latency', 'throughput', 'benchmark',
        'profile', 'memory leak', 'cpu usage', 'cache'
    ]

    return any(kw in message.lower() for kw in performance_keywords)
```

### Security Task Intent

Triggers Level 2 loading of security modules:

```python
def detect_security_task(message: str) -> bool:
    """Detect if user has security concerns"""

    security_keywords = [
        'security', 'vulnerability', 'auth', 'authentication',
        'authorization', 'token', 'password', 'encrypt',
        'xss', 'csrf', 'injection', 'sanitize', 'validate input'
    ]

    return any(kw in message.lower() for kw in security_keywords)
```

## Command-Specific Loading Profiles

### `/issue-work` Dynamic Loading

```yaml
stage_1_critical:
  - core/environment.md              # 500 tokens
  - core/communication.md            # 800 tokens
  total: 1,300 tokens

stage_2_essential:
  - workflow/git-commit-format.md    # 3,000 tokens
  - workflow/github-issue-5w1h.md    # 4,500 tokens
  - workflow/github-pr-5w1h.md       # 4,200 tokens
  - core/problem-solving.md          # 600 tokens
  - core/common-commands.md          # 1,200 tokens
  total: 13,500 tokens

stage_3_contextual:
  # Only if issue description mentions implementation
  if_code_implementation:
    - coding/general.md              # 5,000 tokens

  # Only if issue mentions labeling
  if_labeling:
    - workflow/reference/label-definitions.md  # 6,000 tokens

  # Only if large issue needs splitting
  if_splitting:
    - workflow/reference/issue-examples.md     # 8,000 tokens

total_minimum: 14,800 tokens (89% better than v1.1.0)
total_maximum: 34,800 tokens (still 30% better than v1.1.0)
```

### `/commit` Dynamic Loading

```yaml
stage_1_critical:
  - core/environment.md              # 500 tokens
  - core/communication.md            # 800 tokens
  total: 1,300 tokens

stage_2_essential:
  - workflow/git-commit-format.md    # 3,000 tokens
  - workflow/question-handling.md    # 1,500 tokens
  total: 4,500 tokens

stage_3_contextual:
  # None needed for simple commits

total: 5,800 tokens (88% better than v1.1.0)
```

## Lazy Loading Reference Documents

Reference documents (Level 3) are loaded only when processing needs them:

```python
class LazyReferenceLoader:
    """Load reference docs only when needed during response generation"""

    def __init__(self):
        self.reference_cache = {}

    def get_label_definitions(self):
        """Load label definitions only when mentioning labels"""
        if 'label-definitions' not in self.reference_cache:
            self.reference_cache['label-definitions'] = load(
                'workflow/reference/label-definitions.md'
            )
        return self.reference_cache['label-definitions']

    def get_issue_examples(self):
        """Load issue examples only when splitting issues"""
        if 'issue-examples' not in self.reference_cache:
            self.reference_cache['issue-examples'] = load(
                'workflow/reference/issue-examples.md'
            )
        return self.reference_cache['issue-examples']
```

## Streaming Response with Dynamic Loading

```python
def generate_response_with_dynamic_loading(user_message: str):
    """Generate response while loading additional modules as needed"""

    # Start with minimal context
    response = ""

    # Phase 1: Immediate response with Level 0
    response += analyze_question(user_message)  # Uses only critical modules

    # Phase 2: Load Level 1 based on detected intent
    if requires_workflow_guidance(user_message):
        load_level_1_modules()
        response += provide_workflow_guidance()

    # Phase 3: Load Level 2 if needed
    if requires_implementation_details(user_message):
        load_level_2_modules()
        response += provide_implementation_details()

    # Phase 4: Lazy load Level 3 references
    if mentions_specific_concept(user_message, 'labels'):
        reference = lazy_load('workflow/reference/label-definitions.md')
        response += provide_label_guidance(reference)

    return response
```

## Performance Metrics

### Token Usage Comparison

| Scenario | v1.1.0 | v1.2.0 | v1.3.0 (Phase 2) | Improvement |
|----------|--------|--------|------------------|-------------|
| `/commit` (simple) | 50,000 | 8,000 | 5,800 | **88%** |
| `/issue-work` (no impl) | 50,000 | 18,000 | 14,800 | **70%** |
| `/issue-work` (with impl) | 50,000 | 18,000 | 19,800 | **60%** |
| `/issue-create` (simple) | 50,000 | 12,000 | 6,300 | **87%** |

### Loading Time Comparison

| Phase | Load Time | Token Count | Cumulative |
|-------|-----------|-------------|------------|
| Critical (L0) | <100ms | 1,300 | 1,300 |
| Essential (L1) | <200ms | 5,000-13,000 | 6,300-14,300 |
| Contextual (L2) | <300ms | 5,000-7,000 | 11,300-21,300 |
| Reference (L3) | <500ms | On-demand | Variable |

## Implementation in .claudeignore

Update to support priority levels:

```gitignore
# LEVEL 0: CRITICAL (never exclude)
# core/environment.md
# core/communication.md

# LEVEL 1: ESSENTIAL (exclude, load on command detection)
# Command-specific essentials loaded dynamically

# LEVEL 2: CONTEXTUAL (exclude, load on intent analysis)
rules/coding/general.md
rules/coding/quality.md
rules/coding/error-handling.md
rules/coding/performance.md
rules/operations/monitoring.md
rules/security.md
rules/project-management/testing.md

# LEVEL 3: REFERENCE (exclude, lazy load on demand)
rules/workflow/reference/label-definitions.md
rules/workflow/reference/issue-examples.md
rules/workflow/reference/automation-patterns.md
rules/coding/concurrency.md
rules/coding/memory.md
rules/api/

# LEVEL 4: ARCHIVE (exclude, load only via @load directive)
rules/operations/cleanup.md
rules/project-management/build.md
rules/documentation.md
```

## User Control

Users can override dynamic loading:

```markdown
# Force load specific level
@priority: level-2

# Force load specific modules
@load: coding/concurrency, coding/memory

# Disable dynamic loading (load all)
@dynamic-loading: off
```

## Benefits of Phase 2

1. **Reduced initial load**: Only 1,300 tokens to start
2. **Faster response start**: Begin responding in <100ms
3. **Progressive enhancement**: Load more as needed
4. **Better accuracy**: Only relevant context loaded
5. **Lower peak usage**: Average 60-70% better than v1.1.0

---

*Phase 2 Implementation - Dynamic Module Loading*
*Achieves additional 20-30% token savings over Phase 1*
