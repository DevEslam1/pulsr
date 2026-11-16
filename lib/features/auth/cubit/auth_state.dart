// lib/features/auth/cubit/auth_state.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/errors/app_error.dart';

part 'auth_state.freezed.dart';

enum AuthStatus {
  initial,
  authenticating,
  authenticated,
  unauthenticated,
  error
}

enum SyncStatus { idle, syncing, success, failure }

@freezed
abstract class AuthState with _$AuthState {
  const AuthState._();

  const factory AuthState({
    @Default(AuthStatus.initial) AuthStatus status,
    User? user,
    AppError? error,
    @Default(SyncStatus.idle) SyncStatus syncStatus,
    AppError? syncError,
    DateTime? lastSyncedAt,
  }) = _AuthState;

  /// Compatibility accessors: the UI renders the typed error's user copy.
  String? get errorMessage => error?.userMessage;
  String? get syncErrorMessage => syncError?.userMessage;
}
