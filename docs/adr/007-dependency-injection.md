# ADR 007: Dependency Injection with GetIt and Injectable

## Status
Accepted

## Context
Pulsr has a broad object graph — database, HTTP clients, audio handler, cubits, platform services and stores. Constructing it by hand in `main.dart` would:
1. **Scatter wiring logic**: every entry point would need to know how to build the audio handler, the database and the caches.
2. **Break testability**: services would depend on concrete singletons created deep in the widget tree, making substitution in tests difficult.
3. **Race the startup path**: the splash screen and the first UI reads need certain singletons (audio handler, player cubit, per-song stores) to exist and be fully loaded before use.

## Decision
We use `get_it` as the service locator and `injectable` for code generation:

### 1. Registration
- `lib/core/di/injection.dart` defines the global locator `getIt = GetIt.instance` and exposes `configureDependencies()`.
- `configureDependencies()` is annotated with `@InjectableInit()` and calls the generated `getIt.init()` (`lib/core/di/injection.config.dart`).
- Dependencies are declared with annotations at their definition site: `@singleton`, `@lazySingleton`, `@factoryMethod`, plus `@module`/`@Singleton` for third-party types that cannot be annotated (`NetworkModule` for `HttpClient`/`http.Client`, `StorageModule` for `FlutterSecureStorage`).

### 2. Eager warm-up of async singletons
`getIt.init()` resolves sync singletons only. The audio handler and cubits depend on asynchronous factories and on `SharedPreferences`, so a later sync `getIt<T>()` in `main.dart` would throw `StateError` and produce a blank start. To prevent that, `configureDependencies()` pre-warms the critical graph, each under a timeout so a slow/failed subsystem cannot hang startup:

```
PulsrAudioHandler -> PlayerCubit -> YtmDownloadCubit -> FileIntentHandler
SongRatingStore.ready / PerSongEqStore.ready / PerSongVolumeStore.ready
getIt.allReady()
```

The per-song stores hydrate their in-memory maps asynchronously in their constructors; startup awaits their `ready` futures so the first UI read is authoritative rather than empty.

### 3. Startup signal and validation
- `initializationReady` (a `Completer`) completes in a `finally` block once initialization finishes or fails; the splash gates routing on that real signal instead of a fixed delay.
- `validateDependencies()` asserts the presence of `AppDatabase`, `PulsrAudioHandler`, `PlayerCubit`, `DownloadsCubit` and `YtmDownloadCubit`. This is an `assert`, so it fires in debug/profile and is compiled out in release.

### 4. Disposal
`@Singleton(dispose:)` hooks close owned resources deterministically:
- `disposeHttpClient` closes the dart `HttpClient` (`close(force: false)`).
- `disposePkgHttpClient` closes the package `http.Client`.

## Consequences
### Positive
- A single wiring surface (`injection.dart` + generated config); feature code annotates its own dependencies and stays unaware of construction.
- Test substitution is straightforward: register a fake for an interface in a test scope.
- Eager warm-up removes the `StateError`/blank-start race and the guessed splash delay.
- Resource ownership is explicit through dispose hooks.

### Negative / Trade-offs
- The generated `injection.config.dart` must be regenerated (`build_runner`) after any annotation change; forgetting leaves the graph stale.
- `validateDependencies` uses `assert` and therefore does not guard release builds.
- The locator is a global, so hidden dependencies can be introduced if a type is called through `getIt` instead of injected.
