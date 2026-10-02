# ADR 003: Mutex Synchronization and Monotonic Generation Concurrency

## Status
Accepted

## Context
High-frequency async operations in Pulsr (rapid next/previous skipping, background metadata resolution, downloaded-file reconciliation, and multi-slot queue switching) previously suffered from race conditions:
1. **Out-of-Order In-Flight Responses**: If a user quickly skipped tracks A -> B -> C, metadata or stream resolution for A could resolve after C, overwriting C's state with A's metadata.
2. **Concurrent Writes**: Rapid slot saves or reordering operations could interleave async disk writes, resulting in corrupted or truncated queue states in `SharedPreferences`.
3. **Double Invocations & Audio Overlaps**: Initiating playback on player A while player B was crossfading could leave both audio pipelines active simultaneously.

## Decision
We implemented two concurrency hardening mechanisms. Note that the mutex is **not** a broad/global synchronization primitive: it is applied only at specific single-writer critical sections listed below. Most cross-cutting race protection is done with monotonic generation tokens.

### 1. Monotonic Generation Counters
For async operations where only the latest request's outcome is valid, monotonic integer counters invalidate stale results. These are the primary mechanism used across the player/queue pipeline:
- `_mediaItemResolutionGen`: Incremented before each track transition. When an async resolution completes, it compares its captured generation against the active counter; if mismatched, the result is discarded silently.
- `_localMatchSwapGen`: Dedicated generation token for offline twin swaps, preventing background local file swaps from overwriting subsequent tracks when skipping rapidly.
- `_queueRestorationDone`: Guard flag ensuring that in-flight queue restoration tasks immediately abort if a user explicitly selects a track or switches slots.

### 2. Targeted Mutex / Lock Serialization
A `Mutex` is used only where a genuine single-writer read-modify-write or non-atomic check-then-set exists. As of this writing those sites are:
- `PlayerQueueController._queueMutex` — serializes queue slot persistence/reordering (`player_queue_slots.dart`).
- `DownloadsCubit._deleteMutex` — serializes tombstone/delete mutations (`downloads_cubit.dart`).
- `SettingsCubit._migrationMutex` and `_loadMutex` — serialize settings migration and load.
- `CrossfadeManager._fadeMutex`, `TripleBufferPipeline._claimMutex`, `PlayerDspController._followSampleRateMutex` — single-purpose critical sections in the audio pipeline.
- `EqualizerManager` uses an `AsyncLock` for effect-state changes.
- Async equivalents exist where the critical section crosses awaits: `ScrobblerService._submitMutex`, `YtmCacheManager._fileMutex` and `YtmRateLimiter._nativeMutex` use `AsyncMutex`.
- Domain services added later (`SettingsProfilesService`, `DeviceProfileService`) use a `Mutex` to serialize their `SharedPreferences` read-modify-write. Smart playlist cache evaluation is debounced/stream-based rather than mutex-guarded.

Every site declares its own lock; there is no shared global mutex, and unrelated pipelines do not contend.

## Consequences
### Positive
- Zero stale state overwrites during rapid user interactions (generation tokens verified under 100-rapid-fire events in `test/concurrency/concurrency_hardening_test.dart`).
- The specific single-writer resources named above are thread-safe and deterministic.
- Because locks are scoped per resource, unrelated pipelines never contend on one global lock.

### Negative / Trade-offs
- Developers must remember to increment and capture generation tokens when adding new asynchronous multi-stage pipelines.
- Mutex coverage is intentionally narrow; a new read-modify-write that is not listed above is **not** protected and must add its own guard.
