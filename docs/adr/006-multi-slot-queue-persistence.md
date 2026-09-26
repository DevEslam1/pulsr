# ADR 006: Multi-Slot Queue Architecture and Schema Versioning

## Status
Accepted

## Context
Pulsr allows listeners to maintain multiple concurrent playback queues ("Queue Slots" 0 through 2) and switch seamlessly between them without losing track order, playback indices, or progress positions.

Previous implementations stored raw serialized queue documents directly in `SharedPreferences`. This posed several challenges:
1. **Schema Fragility**: Evolving track metadata (e.g. adding online stream URLs, favorite flags, or custom playback speeds) risked breaking deserialization for users updating across application releases.
2. **Crash & Inconsistency Risks**: An unexpected audio engine failure during queue swaps or item reorders could leave the visual UI and the native playback queue in conflicting states.
3. **Large Payload Overhead**: Encoding and decoding large queues (up to 5,000 items) on the UI isolate caused visible frame drops during app shutdown or restoration.

## Decision
We standardized queue management, persistence, and schema evolution around `QueueSlotCodec` and atomic controller boundaries:

### 1. Dedicated Codec & Schema Versioning
- Serialization and validation logic is centralized in `QueueSlotCodec`.
- Stored queue documents include a top-level `schemaVersion` integer (currently `1`).
- `QueueSlotCodec.decodeDocument` validates document structure and checks for future incompatible versions.
- `QueueSlotCodec.migrateDocument` provides deterministic forward migrations for legacy or unversioned (v0) documents, ensuring smooth upgrades without data loss.

### 2. Off-Isolate Serialization
- All JSON encoding and decoding is offloaded from the UI isolate using Flutter's `compute(jsonEncode, ...)` and `compute(jsonDecode, ...)`.
- Persistent writes are debounced (`debouncedPersistQueueSlots`) to coalesce rapid queue mutations (such as reordering multiple tracks) into a single write operation.

### 3. Reorder Failure Rollback and Atomic State Guarantee
- When the user modifies queue items or triggers a slot switch, the controller preserves a snapshot of the prior state.
- In `PlayerQueueController.reorderQueue()`, if the native audio handler throws an error during track repositioning, the controller automatically executes a rollback that reverts both the in-memory queue slots and the audio service queue to the previous state.
- Rollback operations are shielded with isolated error handling to guarantee terminal error reporting without leaving dangling corrupted states.

### 4. Bounded Memory Limits
- Queues are strictly bounded to `PlayerQueueController.maxQueueSize` (5,000 items).
- Individual slots exceeding capacity during restoration are truncated defensively to safeguard device RAM.

## Consequences
### Positive
- Forward and backward compatibility for persisted queues across application updates.
- Zero jank during queue persistence due to off-isolate computation and debouncing.
- Visual and native audio queue state consistency guaranteed by atomic rollback.

### Negative / Trade-offs
- Multi-isolate serialization adds minor asynchronous latency during initial app startup restoration.
