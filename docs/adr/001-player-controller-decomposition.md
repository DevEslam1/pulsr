# ADR 001: Player Controller Decomposition

## Status
Accepted

## Context
Prior to this architectural refactor, `PlayerCubit` acted as a monolithic God Object exceeding 2,800 lines across 4 tightly coupled mixins (`PlayerDspMixin`, `PlayerQueueMixin`, `PlayerTransportMixin`, etc.). This structure caused several maintenance issues:
1. **Low Testability**: Isolating queue edge cases or transport race conditions required bootstrapping the entire player stack, audio handler, database, and DSP subsystems.
2. **Coupled Lifecycles**: State changes in audio effect presets or lyrics fetching triggered emissions across the combined state, creating unnecessary rebuilds.
3. **Hard Limit Violations**: Single files exceeded maintainability ceilings, making code reviews and concurrent feature development difficult.

## Decision
We decomposed `PlayerCubit` into focused, independently testable controllers wired by composition under `lib/features/player/cubit/controllers/` (13 files), plus `managers/` and mixins. `PlayerCubit` (`lib/features/player/cubit/player_cubit.dart`) remains as a facade composing them, preserving backward compatibility for UI widgets while delegating all business logic.

Current layout (facade + mixins + controllers + managers + codec):

- `player_cubit.dart` — facade; `player_transport_mixin.dart`, `player_queue_mixin.dart`, `player_dsp_mixin.dart`, `player_playback_options_mixin.dart` — God-object split seams.
- `controllers/player_transport_controller.dart` — `play`, `pause`, `stop`, `seek`, `skipNext`, `skipPrevious`, shuffle/repeat.
- `controllers/player_queue_controller.dart` + `controllers/player_queue_slots.dart` + `controllers/queue_slot_data.dart` + `queue_slot_codec.dart` — queue CRUD, **3 persisted slots (0–2, `QueueSlotCodec.maxSlotIndex = 2`)**, reordering, dynamic queue slice generation. See ADR 006 for the persistence schema.
- `controllers/player_dsp_controller.dart` + `player_dsp_effects.dart` + `player_dsp_profiles.dart` — equalizer, parametric dynamic EQ, bass boost, spatial reverb, loudness normalization, bit-perfect bypass (see ADR 005).
- `controllers/player_metadata_controller.dart` — synchronized LRC lyrics, SponsorBlock segment skipping, CUE chapter parsing, audio stream quality badge.
- `controllers/player_playback_options_controller.dart` + `player_playback_options_lyrics.dart` + `player_playback_options_quran.dart` — speed/pitch, A-B loop, sleep timer, per-song overrides, Quran-mode options.
- `controllers/player_widget_bridge.dart` + `player_widget_coordinator.dart` + `player_scrobble_coordinator.dart` + `managers/` (`player_lyrics_manager`, Quran, SponsorBlock) — widget/home-screen bridge and side-effect coordinators.
- Line budget: each controller file stays strictly < 400 lines.

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
