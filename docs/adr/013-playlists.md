# ADR 013: Playlists — Static, Smart and Import/Export

## Status
Accepted

## Context
Pulsr supports two kinds of playlists that look the same in the UI but behave differently:
1. **Static playlists** — an explicit, ordered list of songs.
2. **Smart playlists** — a set of rules evaluated against the library, whose membership changes as the library changes.

Additional needs: import/export of standard playlist formats, seeded defaults so the feature is not empty on first run, and a domain boundary that keeps persistence out of the UI.

## Decision
We model playlists in the domain and delegate persistence/reactive evaluation to interfaces.

### 1. Use cases (`lib/domain/usecases/playlist_usecases.dart`)
`PlaylistUseCases` wraps the repository: `watchPlaylists`, `watchPlaylistSongs`, `createPlaylist(isSmart, smartCriteria)`, `renamePlaylist`, `updateSmartPlaylist`, `deletePlaylist`, `addSongToPlaylist`/`addSongsToPlaylist`, `removeSongFromPlaylist`, `reorderPlaylistSongs`. Static mutations return `Result<T>` (failure is a `Left`, handled by the callers) rather than throwing.

### 2. Smart playlist engine (`ISmartPlaylistEngine`)
`lib/domain/repositories/smart_playlist_engine_interface.dart` exposes:
- `evaluateCriteria(SmartCriteria)` — one-shot evaluation.
- `watchCriteria(SmartCriteria)` — reactive stream, debounced (500 ms) so library mutations coalesce into a single re-evaluation.
- `validateRules(SmartCriteria)` — reports rules that cannot be evaluated (empty required strings, bad numerics) instead of silently matching everything.

`SmartCriteria` (`lib/domain/models/smart_playlist_criteria.dart`) carries rules, `matchAll`, sort field/direction and an optional limit.

### 3. Seed defaults
`seedDefaultSmartPlaylists()` creates a curated starting set (Recently Added, Most Played, Recently Played, Long Tracks, Forgotten Gems, Top Rated) but skips any name that already exists (case-insensitive), so re-running never duplicates.

### 4. Import/export
`lib/domain/usecases/playlist_io_usecases.dart` handles standard formats (e.g. M3U/PLS/WPL parsing lives in the data layer), so round-tripping playlists in/out of Pulsr does not require the UI to know file syntax.

### 5. State
`PlaylistCubit` (`lib/features/playlists/cubit/`) holds a Freezed `PlaylistState` and drives the use cases; the smart-playlist builder screen composes `SmartCriteria` interactively.

## Consequences
### Positive
- Static and smart playlists share one UI while their different semantics stay behind a typed interface.
- Smart playlists are reactive and debounced, and validate rules up front.
- Defaults are idempotent, avoiding duplicate seeding.
- Persistence and format parsing stay out of the UI.

### Negative / Trade-offs
- Smart playlists must re-evaluate on library changes; a rule touching many fields can be expensive on very large libraries (mitigated by debounce and limits).
- `Result`-returning mutations require every caller to fold/check the outcome; ignoring it hides failures.
