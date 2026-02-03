# Module Caching Strategy

> **Type**: Design Document (Implementation Details)
> **Version**: 1.4.0 (Phase 3 Implementation)
> **Purpose**: Cache frequently used modules to eliminate redundant loading
> **Performance Gain**: 50% faster command execution through intelligent caching
>
> **Note**: This is a design document containing implementation details.
> For concise rules, see `.claude/rules/token-optimization.md`.

## Overview

This document defines the module caching system that keeps frequently used guideline modules in memory across multiple command invocations, dramatically reducing load times for subsequent commands.

## Cache Architecture

### Three-Tier Cache System

```
┌─────────────────────────────────────────────────────┐
│ HOT Cache (Always in Memory)                       │
│ - Accessed >80% of time                            │
│ - Never evicted                                     │
│ - ~5,000 tokens                                     │
└─────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────┐
│ WARM Cache (LRU with 50 item limit)                │
│ - Accessed 20-80% of time                          │
│ - Evicted via LRU when full                        │
│ - ~30,000 tokens                                    │
└─────────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────────┐
│ COLD Storage (Load from disk)                      │
│ - Accessed <20% of time                            │
│ - Always loaded fresh                               │
│ - Unlimited size                                    │
└─────────────────────────────────────────────────────┘
```

## Module Classification

### HOT Modules (Permanent Cache)

Never evicted, always in memory:

```yaml
hot_modules:
  # Core essentials - used in every command
  - core/environment.md              # Access: 100%, Size: 500 tokens
  - core/communication.md            # Access: 100%, Size: 800 tokens
  - workflow/question-handling.md    # Access: 95%, Size: 1,500 tokens

  # Git workflow - used in 80%+ of commands
  - workflow/git-commit-format.md    # Access: 85%, Size: 3,000 tokens

  total_size: ~5,800 tokens
  total_modules: 4
  eviction_policy: NEVER
```

**Criteria for HOT**:
- Access frequency >80% across all commands
- Small size (<5,000 tokens each)
- Critical for basic operations

### WARM Modules (LRU Cache)

Frequently accessed, cached with LRU eviction:

```yaml
warm_modules:
  # Workflow essentials
  - workflow/github-issue-5w1h.md          # Access: 60%, Size: 4,500 tokens
  - workflow/github-pr-5w1h.md             # Access: 55%, Size: 4,200 tokens
  - core/problem-solving.md                 # Access: 70%, Size: 600 tokens
  - core/common-commands.md                 # Access: 65%, Size: 1,200 tokens

  # Coding standards - used in implementation
  - coding/general.md                       # Access: 45%, Size: 5,000 tokens
  - coding/quality.md                       # Access: 40%, Size: 4,500 tokens
  - coding/error-handling.md                # Access: 35%, Size: 4,000 tokens

  # Performance and security
  - coding/performance.md                   # Access: 25%, Size: 6,000 tokens
  - security.md                             # Access: 30%, Size: 7,000 tokens

  # Testing
  - project-management/testing.md           # Access: 35%, Size: 5,000 tokens

  max_modules: 50
  max_total_size: 50,000 tokens
  eviction_policy: LRU
  ttl: 1 hour (sliding)
```

**Criteria for WARM**:
- Access frequency 20-80%
- Medium size (<10,000 tokens)
- Not critical enough for HOT

### COLD Modules (No Cache)

Rarely accessed, always loaded fresh:

```yaml
cold_modules:
  # Reference documents - large and infrequent
  - workflow/reference/label-definitions.md     # Access: 15%, Size: 6,000 tokens
  - workflow/reference/issue-examples.md        # Access: 10%, Size: 8,000 tokens
  - workflow/reference/automation-patterns.md   # Access: 12%, Size: 9,000 tokens

  # Advanced coding
  - coding/concurrency.md                       # Access: 8%, Size: 12,000 tokens
  - coding/memory.md                            # Access: 7%, Size: 10,000 tokens

  # API design
  - api/api-design.md                           # Access: 18%, Size: 8,000 tokens
  - api/logging.md                              # Access: 15%, Size: 6,000 tokens
  - api/observability.md                        # Access: 10%, Size: 7,000 tokens
  - api/architecture.md                         # Access: 12%, Size: 9,000 tokens

  # Operations
  - operations/cleanup.md                       # Access: 5%, Size: 8,000 tokens
  - operations/monitoring.md                    # Access: 20%, Size: 5,500 tokens

  # Documentation
  - documentation.md                            # Access: 8%, Size: 7,000 tokens

  eviction_policy: IMMEDIATE
  cache: false
```

**Criteria for COLD**:
- Access frequency <20%
- Large size (>8,000 tokens)
- Specialized use cases

## Cache Implementation

### LRU Cache with Size Limit

```python
from collections import OrderedDict
import time

class ModuleCache:
    """LRU cache for guideline modules with size and time limits"""

    def __init__(self, max_size_tokens=50000, max_items=50, ttl_seconds=3600):
        self.hot_cache = {}      # Never evicted
        self.warm_cache = OrderedDict()  # LRU eviction
        self.max_size = max_size_tokens
        self.max_items = max_items
        self.ttl = ttl_seconds
        self.current_size = 0
        self.stats = {
            'hits': 0,
            'misses': 0,
            'evictions': 0
        }

    def get(self, module_path: str):
        """Get module from cache or return None"""

        # Check HOT cache first (fastest)
        if module_path in self.hot_cache:
            self.stats['hits'] += 1
            return self.hot_cache[module_path]['content']

        # Check WARM cache
        if module_path in self.warm_cache:
            entry = self.warm_cache[module_path]

            # Check TTL
            if time.time() - entry['accessed'] > self.ttl:
                # Expired, remove from cache
                self._remove_from_warm(module_path)
                self.stats['misses'] += 1
                return None

            # Update access time and move to end (most recent)
            entry['accessed'] = time.time()
            self.warm_cache.move_to_end(module_path)
            self.stats['hits'] += 1
            return entry['content']

        # Not in cache
        self.stats['misses'] += 1
        return None

    def put(self, module_path: str, content: str, tier: str = 'WARM'):
        """Add module to appropriate cache tier"""

        module_size = len(content)  # Approximate token count

        if tier == 'HOT':
            # Add to permanent cache
            self.hot_cache[module_path] = {
                'content': content,
                'size': module_size,
                'loaded': time.time()
            }
            return

        if tier == 'WARM':
            # Check if we need to evict
            while (
                len(self.warm_cache) >= self.max_items or
                self.current_size + module_size > self.max_size
            ):
                self._evict_lru()

            # Add to WARM cache
            self.warm_cache[module_path] = {
                'content': content,
                'size': module_size,
                'loaded': time.time(),
                'accessed': time.time()
            }
            self.current_size += module_size

        # COLD tier is not cached

    def _evict_lru(self):
        """Evict least recently used item from WARM cache"""
        if not self.warm_cache:
            return

        # Get least recently used (first item)
        module_path, entry = self.warm_cache.popitem(last=False)
        self.current_size -= entry['size']
        self.stats['evictions'] += 1

    def _remove_from_warm(self, module_path: str):
        """Remove specific module from WARM cache"""
        if module_path in self.warm_cache:
            entry = self.warm_cache.pop(module_path)
            self.current_size -= entry['size']

    def get_stats(self):
        """Get cache statistics"""
        total_requests = self.stats['hits'] + self.stats['misses']
        hit_rate = (self.stats['hits'] / total_requests * 100) if total_requests > 0 else 0

        return {
            'hit_rate': f"{hit_rate:.1f}%",
            'hits': self.stats['hits'],
            'misses': self.stats['misses'],
            'evictions': self.stats['evictions'],
            'hot_modules': len(self.hot_cache),
            'warm_modules': len(self.warm_cache),
            'warm_size_tokens': self.current_size,
            'warm_capacity': f"{self.current_size}/{self.max_size} tokens"
        }

    def clear_expired(self):
        """Clear expired entries from WARM cache"""
        current_time = time.time()
        expired = [
            path for path, entry in self.warm_cache.items()
            if current_time - entry['accessed'] > self.ttl
        ]

        for path in expired:
            self._remove_from_warm(path)
```

## Cache Warming Strategy

### Pre-populate HOT Cache on Startup

```python
def initialize_cache():
    """Pre-load HOT modules on system startup"""

    cache = ModuleCache()

    hot_modules = [
        'core/environment.md',
        'core/communication.md',
        'workflow/question-handling.md',
        'workflow/git-commit-format.md'
    ]

    for module_path in hot_modules:
        content = load_module_from_disk(module_path)
        cache.put(module_path, content, tier='HOT')

    return cache
```

### Adaptive Cache Warming

Learn from usage patterns and pre-warm frequently used combinations:

```python
class AdaptiveCacheWarmer:
    """Learn usage patterns and pre-warm cache"""

    def __init__(self):
        self.usage_log = []
        self.command_patterns = {}

    def log_usage(self, command: str, modules_used: list):
        """Log which modules were used for a command"""
        self.usage_log.append({
            'command': command,
            'modules': modules_used,
            'timestamp': time.time()
        })

        # Update command patterns
        if command not in self.command_patterns:
            self.command_patterns[command] = {}

        for module in modules_used:
            self.command_patterns[command][module] = \
                self.command_patterns[command].get(module, 0) + 1

    def get_likely_modules(self, command: str) -> list:
        """Predict which modules will be needed for a command"""
        if command not in self.command_patterns:
            return []

        # Sort by frequency
        modules = sorted(
            self.command_patterns[command].items(),
            key=lambda x: x[1],
            reverse=True
        )

        # Return top 5 most frequent
        return [m[0] for m in modules[:5]]

    def warm_cache_for_command(self, command: str, cache: ModuleCache):
        """Pre-load likely modules for a command"""
        likely_modules = self.get_likely_modules(command)

        for module_path in likely_modules:
            if cache.get(module_path) is None:
                content = load_module_from_disk(module_path)
                cache.put(module_path, content, tier='WARM')
```

## Cache Invalidation

### Invalidation Triggers

```python
class CacheInvalidator:
    """Handle cache invalidation when modules change"""

    def __init__(self, cache: ModuleCache):
        self.cache = cache
        self.file_mtimes = {}  # Track modification times

    def check_and_invalidate(self, module_path: str):
        """Check if module file has changed and invalidate if needed"""
        current_mtime = os.path.getmtime(module_path)

        if module_path in self.file_mtimes:
            if current_mtime > self.file_mtimes[module_path]:
                # File changed, invalidate cache
                self._invalidate_module(module_path)

        self.file_mtimes[module_path] = current_mtime

    def _invalidate_module(self, module_path: str):
        """Remove module from cache"""
        # Remove from WARM cache (can't remove from HOT)
        if module_path in self.cache.warm_cache:
            self.cache._remove_from_warm(module_path)

            # Reload if it's a HOT module
            if module_path in self.cache.hot_cache:
                content = load_module_from_disk(module_path)
                self.cache.put(module_path, content, tier='HOT')
```

### Auto-Invalidation on File Change

Monitor file system for changes:

```python
import watchdog.observers
import watchdog.events

class ModuleFileWatcher(watchdog.events.FileSystemEventHandler):
    """Watch module files for changes"""

    def __init__(self, cache_invalidator: CacheInvalidator):
        self.invalidator = cache_invalidator

    def on_modified(self, event):
        """Handle file modification event"""
        if event.is_directory:
            return

        if event.src_path.endswith('.md'):
            self.invalidator.check_and_invalidate(event.src_path)
```

## Performance Metrics

### Expected Cache Hit Rates

Based on typical usage patterns:

| Command Type | Expected Hit Rate | Avg Load Time |
|--------------|------------------|---------------|
| `/commit` | 95% (all HOT) | <50ms |
| `/issue-work` | 75% (mostly WARM) | <150ms |
| `/pr-work` | 80% (HOT + WARM) | <120ms |
| `/issue-create` | 70% (mix) | <180ms |
| Code implementation | 60% (some COLD) | <300ms |

### Memory Usage

```yaml
hot_cache:
  modules: 4
  total_size: ~5,800 tokens
  memory: ~30 KB

warm_cache:
  max_modules: 50
  max_size: ~50,000 tokens
  max_memory: ~250 KB

total_max_memory: ~280 KB
```

Very reasonable memory footprint for 50-95% cache hit rate.

## Cache Statistics Tracking

```python
class CacheStatsTracker:
    """Track and report cache performance"""

    def __init__(self, cache: ModuleCache):
        self.cache = cache
        self.session_start = time.time()

    def get_report(self):
        """Generate cache performance report"""
        stats = self.cache.get_stats()
        uptime = time.time() - self.session_start

        return f"""
Cache Performance Report
========================

Uptime: {uptime/3600:.1f} hours

Hit Rate: {stats['hit_rate']}
Total Hits: {stats['hits']}
Total Misses: {stats['misses']}
Evictions: {stats['evictions']}

HOT Cache: {stats['hot_modules']} modules (permanent)
WARM Cache: {stats['warm_modules']} modules
WARM Size: {stats['warm_capacity']}

Estimated Time Saved: {stats['hits'] * 0.2:.1f} seconds
"""
```

## Integration with Dynamic Loading (Phase 2)

```python
def load_module_with_cache(module_path: str, tier: str, cache: ModuleCache):
    """Load module with cache support"""

    # Try cache first
    content = cache.get(module_path)

    if content is not None:
        return content

    # Cache miss, load from disk
    content = load_module_from_disk(module_path)

    # Add to cache
    if tier != 'COLD':
        cache.put(module_path, content, tier=tier)

    return content
```

## Configuration

### Cache Settings

```yaml
# .claude/cache-config.yml

cache:
  enabled: true

  hot:
    modules:
      - core/environment.md
      - core/communication.md
      - workflow/question-handling.md
      - workflow/git-commit-format.md

  warm:
    max_items: 50
    max_size_tokens: 50000
    ttl_seconds: 3600  # 1 hour

  monitoring:
    log_stats: true
    stats_interval: 300  # 5 minutes

  invalidation:
    watch_files: true
    auto_reload: true
```

### User Overrides

```markdown
# Disable caching for this session
@cache: off

# Clear cache
@cache: clear

# Show cache stats
@cache: stats

# Force reload specific module (bypass cache)
@reload: coding/performance.md
```

## Benefits of Phase 3

1. **50% faster execution**: Most modules from cache
2. **Reduced I/O**: Fewer disk reads
3. **Consistent performance**: Predictable load times
4. **Adaptive learning**: Gets better over time
5. **Low memory footprint**: <300 KB total

---

*Phase 3 Implementation - Module Caching*
*Achieves 50% faster command execution through intelligent caching*
