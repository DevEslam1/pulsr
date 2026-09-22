# ADR 001: Player Controller Decomposition

## Status
Accepted

## Context
Prior to this architectural refactor, `PlayerCubit` acted as a monolithic God Object exceeding 2,800 lines across 4 tightly coupled mixins (`PlayerDspMixin`, `PlayerQueueMixin`, `PlayerTransportMixin`, etc.). This structure caused several maintenance issues:
1. **Low Testability**: Isolating queue edge cases or transport race conditions required bootstrapping the entire player stack, audio handler, database, and DSP subsystems.
2. **Coupled Lifecycles**: State changes in audio effect presets or lyrics fetching triggered emissions across the combined state, creating unnecessary rebuilds.
3. **Hard Limit Violations**: Single files exceeded maintainability ceilings, making code reviews and concurrent feature development difficult.

## Decision
We decomposed `PlayerCubit` into 5 focused, independently testable controllers wired by composition under `lib/features/player/cubit/controllers/`:

1. **`PlayerTransportController`** (`player_transport_controller.dart`):
   - Scope: `play`, `pause`, `stop`, `seek`, `skipNext`, `skipPrevious`, shuffle mode, repeat mode.
   - Line budget: strictly < 400 lines (currently ~232 lines).
2. **`PlayerQueueController`** (`player_queue_controller.dart`):
   - Scope: Queue CRUD, multi-slot persistence (slots 1–9 via `QueueSlotData`), reordering, dynamic queue slice generation.
   - Line budget: strictly < 400 lines (currently ~373 lines).
3. **`PlayerDspController`** (`player_dsp_controller.dart`):
   - Scope: Equalizer, parametric dynamic EQ, bass boost, spatial reverb, loudness normalization, bit-perfect bypass.
   - Line budget: strictly < 400 lines (currently ~79 lines).
4. **`PlayerMetadataController`** (`player_metadata_controller.dart`):
   - Scope: Synchronized LRC lyrics, SponsorBlock segment skipping, CUE chapter parsing, audio stream quality badge.
   - Line budget: strictly < 400 lines (currently ~120 lines).
5. **`PlayerDeviceController`** (`player_device_controller.dart`):
   - Scope: Output device routing (Bluetooth, USB DAC, Headset), bit-perfect sample rate matching, route change detection.
   - Line budget: strictly < 400 lines.

### Coordination Pattern
- The controllers interact with the underlying domain via domain boundary interfaces (`lib/domain/boundaries.dart`, `lib/domain/interfaces/`).
- Shared atomic operations are guarded by explicit locks and monotonic generation tokens (`_queueRestorationDone`, `_mediaItemResolutionGen`).
- `PlayerCubit` acts as a facade that composes the 5 controllers, preserving backward compatibility for UI widgets while delegating all business logic.

## Consequences
### Positive
- Every controller is strictly < 400 lines, enforcing Single Responsibility.
- Test suites can instantiate individual controllers without spinning up the entire audio engine or database (`test/architecture/player_controller_decomposition_test.dart`).
- Clear bounded context boundaries eliminate circular cubit-to-cubit dependencies.

### Negative / Trade-offs
- Requires passing coordinate callbacks or boundary delegates to controllers during initialization.
