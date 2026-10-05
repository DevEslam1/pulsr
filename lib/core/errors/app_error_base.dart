// lib/core/errors/app_error_base.dart
//
// Platform-agnostic base of the Pulsr error taxonomy.
//
// Kept in its own library, free of Flutter/drift imports, so pure-Dart domain
// code and the legacy [AppFailure] hierarchy can share a single error type
// without dragging platform dependencies into `lib/domain`. The canonical
// subtypes and the [resolveAppError] classifier live in `app_error.dart`,
// which re-exports this base.
abstract class AppError implements Exception {
  final String code;
  final String userMessage;
  final Object? cause;
  final StackTrace? stackTrace;

  const AppError({
    required this.code,
    required this.userMessage,
    this.cause,
    this.stackTrace,
  });

  /// Legacy alias for [userMessage]; pre-unification call sites used `.message`.
  String get message => userMessage;

  /// Legacy alias for [cause]; pre-unification call sites used `.error`.
  Object? get error => cause;

  @override
  String toString() => '$runtimeType($code): $userMessage';
}
