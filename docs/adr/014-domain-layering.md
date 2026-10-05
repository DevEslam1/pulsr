# ADR 014: Domain Layering, Boundaries and Failure Semantics

## Status
Accepted

## Context
Pulsr mixes platform plumbing (MethodChannels, Android/Kotlin, SharedPreferences, native DSP), persistence (Drift) and UI (cubits/features). Without an explicit layering rule:
1. Feature code would call platform channels and preferences directly, making behaviour untestable and platform-coupled.
2. Cross-feature calls (Player ↔ Settings ↔ Library ↔ Downloads) would create circular cubit dependencies.
3. Different services would express "not found", "failure" and "no data" inconsistently (`null` vs throw vs `Result` vs a sentinel), so callers could not handle them uniformly.

## Decision
We enforce a domain layer with inverted dependencies and document failure semantics.

### 1. Layers
- `lib/domain/` — pure models, repositories/usecase interfaces and domain services. It must not import Flutter UI or `lib/features/`.
- `lib/data/` — concrete implementations (Drift database, audio engine, platform channels), implementing domain interfaces.
- `lib/core/` — cross-cutting infrastructure (DI, router, network, telemetry, responsive, services). Platform-backed services no longer live in the domain: `cast`, `hires_audio`, `room_correction`, `usb_exclusive`, `device_profile` and `settings_profiles` services, plus `backup`/`playlist_io` usecases and `download_settings`, were moved to `lib/data/services`, `lib/data/usecases` and `lib/data/models`. `lib/core/services/*.dart` remain one-line re-exports so existing call sites keep working; `lib/domain/` now imports no Flutter, `permission_handler`, `shared_preferences` or MethodChannel code.
- `lib/features/` — cubits + widgets consuming domain/data through DI.

### 2. Dependency inversion interfaces (`lib/domain/interfaces/`)
Platform-dependent capabilities are abstracted behind interfaces documented with explicit failure semantics:
- `IArtworkResolver` — `null` = not found; bounded in-memory cache (see ADR 004); `clearCache` never throws.
- `ILyricsProvider` — `null` = not found; a failed/malformed fetch is mapped to `null` and logged, never thrown, so one provider cannot abort a multi-source lookup.
- `IProxyApplier` — returns `bool` success/failure; credentials **must be redacted** from logs/telemetry (only host/port and `hasAuth` may be logged).
- `IScrobbleSink` — fire-and-forget `void`; must never throw into playback; dropped events are acceptable.
- `IWidgetPusher` — best-effort `Future<void>`; platform errors are swallowed/logged, never thrown.

### 3. Bounded context map (`lib/domain/boundaries.dart`)
Cross-feature communication is typed through boundary interfaces, not direct cubit references:
- `IPlayerSettingsBoundary` — Player reads output device, bit-perfect, DSP bypass and replay-gain preamp.
- `IPlayerLibraryBoundary` — Player toggles favorites.
- `IDownloadPlayerBoundary` — Downloads swap a streamed track for its local twin.
- `ISettingsPlayerBoundary` — Settings pushes crossfade and device changes to the Player.
Typed events (`AudioDeviceChangedEvent`, `SongReconciledEvent`) carry cross-context notifications.

### 4. Failure convention
- **`null`**: not found / no data (lyrics, artwork). A normal outcome.
- **`Result<T>` (fpdart)**: expected domain failure of an operation (DB/network), represented as `Left`; callers fold it. No throwing for anticipated failures.
- **Throw**: only for programmer errors and truly unexpected conditions; caught at the edge and mapped to a failure/telemetry.
- **`Future<bool>` / `void`**: best-effort side effects (proxy apply, widget push, scrobble) that must not throw into the caller.

### 5. Concurrency hardening inside the domain
Where the domain owns mutable state, it uses targeted guards rather than a blanket lock: queue operations and downloads use `Mutex`/`AsyncMutex` critical sections, async resolutions use monotonic generation counters. See ADR 003 for the corrected scope of mutex usage.

## Consequences
### Positive
- Platform channelling and persistence are testable via interface substitution.
- No direct cubit-to-cubit coupling; cross-feature traffic is typed and greppable.
- Callers can rely on documented `null`/`Result`/throw contracts instead of guessing.
- Secret-redaction is a stated contract on the proxy interface.

### Negative / Trade-offs
- Each new platform capability needs an interface + implementation pair (more files than calling the channel directly).
- The failure convention must be applied consistently; a `null`-returning method that also throws for transport failure blurs the line, so it is documented per-interface.
