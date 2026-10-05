// lib/core/utils/result.dart
//
// Legacy import path. Pulsr previously shipped two unrelated types named
// `Result`: an `Either<AppFailure, T>` typedef (errors/failures.dart) used by
// production, and a sealed `Result` class here used by one audit test. They
// have been unified into the single canonical `Result<T>` from
// `errors/failures.dart`; this file is now only a compatibility re-export.
export '../errors/failures.dart' show Result;

import '../errors/failures.dart' show Result;

/// Backwards-compatible alias for [Result].
typedef AppResult<T> = Result<T>;
