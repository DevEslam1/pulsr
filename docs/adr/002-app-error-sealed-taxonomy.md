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
sealed class AppError {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
  final bool isRecoverable;
  ...
}

class NetworkError extends AppError { ... }
class PlaybackError extends AppError { ... }
class StorageError extends AppError { ... }
class AuthError extends AppError { ... }
class ParsingError extends AppError { ... }
class SecurityError extends AppError { ... }
```

### Key Features
- **Central Resolver**: `resolveAppError(Object error, [StackTrace? st])` maps arbitrary platform exceptions, HTTP status codes, socket errors, format exceptions, and secure storage faults into their canonical `AppError` subtype.
- **Exhaustive Matching**: UI widgets and handlers use Dart 3 `switch (error)` expressions to guarantee every error scenario is handled at compile-time:
  ```dart
  final userAction = switch (error) {
    NetworkError(:final isOffline) => isOffline ? showOfflineBanner() : retryRequest(),
    AuthError(:final isExpired) => triggerReLogin(),
    StorageError(:final isDiskFull) => promptFreeStorage(),
    SecurityError() => alertSecurityViolation(),
    PlaybackError() => fallbackToAlternativeSource(),
    ParsingError() => logDiagnosticTelemetry(),
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
