# ADR 003: Mutex Synchronization and Monotonic Generation Concurrency

## Status
Accepted

## Context
High-frequency async operations in Pulsr (rapid next/previous skipping, background metadata resolution, downloaded-file reconciliation, and multi-slot queue switching) previously suffered from race conditions:
1. **Out-of-Order In-Flight Responses**: If a user quickly skipped tracks A -> B -> C, metadata or stream resolution for A could resolve after C, overwriting C's state with A's metadata.
2. **Concurrent Queue Writes**: Rapid slot saves or reordering operations could interleave async disk writes, resulting in corrupted or truncated queue states in `SharedPreferences`.
3. **Double Invocations & Audio Overlaps**: Initiating playback on player A while player B was crossfading could leave both audio pipelines active simultaneously.

## Decision
We implemented two concurrency hardening mechanisms across the audio, queue, and networking pipelines:

### 1. Monotonic Generation Counters
For async operations where only the latest request's outcome is valid, monotonic integer counters invalidate stale results:
- `_mediaItemResolutionGen`: Incremented before each track transition. When an async resolution completes, it compares its captured generation against the active counter; if mismatched, the result is discarded silently.
- `_localMatchSwapGen`: Dedicated generation token for offline twin swaps, preventing background local file swaps from overwriting subsequent tracks when skipping rapidly.
- `_queueRestorationDone`: Guard flag ensuring that in-flight queue restoration tasks immediately abort if a user explicitly selects a track or switches slots.

### 2. Mutex / Lock Serialization
For critical sections requiring strictly serial execution:
- Replaced non-atomic check-then-set logic with synchronized mutex blocks for queue slot persistence and smart playlist cache evaluations.
- Atomic state emissions ensuring no half-initialized state transitions are visible to listeners.

## Consequences
### Positive
- Zero stale state overwrites during rapid user interactions (verified under 100-rapid-fire events in `test/concurrency/concurrency_hardening_test.dart`).
- Queue slot persistence is thread-safe and deterministic.
- Audio pipeline transitions are strictly serialized, preventing sound leaks or double-playback.

### Negative / Trade-offs
- Developers must remember to increment and capture generation tokens when adding new asynchronous multi-stage pipelines.
