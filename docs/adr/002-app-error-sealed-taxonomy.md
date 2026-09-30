# ADR 002: AppError Sealed Class Taxonomy

## Status
Accepted

## Context
Previously, errors throughout the application were represented by raw `String? errorMessage` fields in cubit states, strings thrown in exceptions, or untyped `dynamic` exceptions caught in `catch (e)` blocks. This pattern led to:
1. **Fragile UI Mapping**: Screens had to parse string messages with regexes or `contains('403')` to decide whether to show a retry button or auth dialog.
2. **Missing Cases in Error Handling**: Adding new failure modes (e.g. proxy handshake failure or SQLite disk full) could silently fall through into generic toast notifications.
3. **No Exhaustive Matching**: Dart could not verify compile-time exhaustiveness over error handling branches.

## Decision
We introduced a sealed class hierarchy `AppError` in `lib/core/errors/app_error.dart` with 6 exhaustive domain subtypes:

```dart
sealed class AppError implements Exception {
  final String code;
  final String userMessage;
  final Object? cause;
  final StackTrace? stackTrace;
  ...
}

class NetworkError extends AppError { ... }      // connectivity, DNS, HTTP, timeouts
class StorageError extends AppError { ... }      // disk IO, SQLite/Drift, file perms
class AudioError extends AppError { ... }        // pipeline, codec, ExoPlayer/AudioService
class YtmError extends AppError { ... }          // YTM API, scraping, bot blocks, tokens
class PermissionError extends AppError { ... }   // storage, notifications, mic, background audio
class GenericAppError extends AppError { ... }   // unexpected domain failure
```

### Key Features
- **Central Resolver**: `resolveAppError(Object error, [StackTrace? st])` maps arbitrary platform exceptions, HTTP status codes, socket errors, format exceptions, and secure storage faults into their canonical `AppError` subtype (plus `YtmErrorClassifier` / `ErrorMessageResolver` for YTM and UI strings).
- **Exhaustive Matching**: UI widgets and handlers use Dart 3 `switch (error)` expressions to guarantee every error scenario is handled at compile-time:
  ```dart
  final userAction = switch (error) {
    NetworkError(:final isTimeout) => isTimeout ? showTimeoutRetry() : showOfflineBanner(),
    YtmError(:final isBotBlock) => isBotBlock ? showBotBlockWait() : triggerReLogin(),
    StorageError(:final path) => promptFreeStorage(path),
    PermissionError(:final permissionName) => requestPermission(permissionName),
    AudioError(:final trackId) => fallbackToAlternativeSource(trackId),
    GenericAppError(:final code) => logDiagnosticTelemetry(code),
  };
  ```

## Consequences
### Positive
- Compile-time error exhaustiveness: the compiler rejects missing error branches when matching on `AppError`.
- Clear semantic recovery signals (`isRecoverable`, `isOffline`, `isExpired`).
- Rich debugging metadata (`cause`, `stackTrace`) preserved without exposing raw traces to end users.
- Clean centralized mapping in `resolveAppError()`.

### Negative / Trade-offs
- Requires migrating legacy `String? errorMessage` cubit state properties toward `AppError? error`.
