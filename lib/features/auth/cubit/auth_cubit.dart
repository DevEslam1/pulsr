// lib/features/auth/cubit/auth_cubit.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/cloud_sync_service.dart';
import 'auth_state.dart';

@injectable
class AuthCubit extends Cubit<AuthState> {
  final AuthService _authService;
  final CloudSyncService _cloudSyncService;
  StreamSubscription? _authSubscription;
  bool _syncing = false;
  DateTime? _lastSyncAttemptAt;
  static const Duration _syncDedupeWindow = Duration(seconds: 2);

  AuthCubit(this._authService, this._cloudSyncService)
      : super(AuthState(lastSyncedAt: _cloudSyncService.lastSyncTime)) {
    _init();
  }

  void _init() {
    _authSubscription = _authService.authStateChanges.listen((user) {
      if (isClosed) return;
      if (user != null) {
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
          lastSyncedAt: _cloudSyncService.lastSyncTime,
        ));
        // Auto-sync in background on login
        syncNow();
      } else {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          user: null,
          errorMessage: null,
        ));
      }
    });
  }

  Future<void> signInWithGoogle() async {
    emit(state.copyWith(status: AuthStatus.authenticating, errorMessage: null));
    try {
      final user = await _authService.signInWithGoogle();
      if (isClosed) return;
      if (user != null) {
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
        await syncNow();
      } else {
        emit(state.copyWith(status: AuthStatus.unauthenticated));
      }
    } catch (e) {
      if (isClosed) return;
      final msg = _mapAuthError(e);
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: msg,
      ));
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    emit(state.copyWith(status: AuthStatus.authenticating, errorMessage: null));
    try {
      final user = await _authService.signInWithEmail(email, password);
      if (isClosed) return;
      if (user != null) {
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
        await syncNow();
      } else {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: 'Sign in failed. Please try again.',
        ));
      }
    } catch (e) {
      if (isClosed) return;
      final msg = _mapAuthError(e);
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: msg,
      ));
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    emit(state.copyWith(status: AuthStatus.authenticating, errorMessage: null));
    try {
      final user = await _authService.signUpWithEmail(email, password);
      if (isClosed) return;
      if (user != null) {
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
        await syncNow();
      } else {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: 'Sign up failed. Please try again.',
        ));
      }
    } catch (e) {
      if (isClosed) return;
      final msg = _mapAuthError(e);
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: msg,
      ));
    }
  }

  /// Returns true when the reset email was accepted by the backend.
  /// Emits [errorMessage] on failure so the sheet can surface it instead of
  /// an optimistic "sent" snackbar.
  Future<bool> sendPasswordReset(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      if (isClosed) return true;
      emit(state.copyWith(errorMessage: null));
      return true;
    } catch (e) {
      if (isClosed) return false;
      final msg = _mapAuthError(e);
      emit(state.copyWith(
        errorMessage: msg,
      ));
      return false;
    }
  }

  String _mapAuthError(Object e) {
    // Prefer the typed Firebase error code over parsing `toString()`; the
    // message wording is not a stable API and the code is exhaustive.
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'user-not-found':
          return 'No account found with this email.';
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-email':
          return 'Incorrect email or password.';
        case 'email-already-in-use':
          return 'This email is already registered.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'network-request-failed':
          return 'Network error. Check your internet connection.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'operation-not-allowed':
          return 'Email sign-in is not enabled for this app.';
        default:
          final message = e.message?.trim();
          if (message != null && message.isNotEmpty) return message;
          return 'Sign-in failed. Please try again.';
      }
    }

    // Fallback for non-Firebase errors (Google Sign-In, PlatformException,
    // wrapped exceptions) where only the string form is available.
    final s = e.toString().toLowerCase();
    if (s.contains('user-not-found') || s.contains('user not found')) {
      return 'No account found with this email.';
    }
    if (s.contains('wrong-password') ||
        s.contains('wrong password') ||
        s.contains('invalid-credential') ||
        s.contains('invalid-email')) {
      return 'Incorrect email or password.';
    }
    if (s.contains('email-already-in-use') ||
        s.contains('email already in use')) {
      return 'This email is already registered.';
    }
    if (s.contains('weak-password') || s.contains('weak password')) {
      return 'Password must be at least 6 characters.';
    }
    if (s.contains('network-request-failed') ||
        s.contains('network error') ||
        s.contains('socketexception')) {
      return 'Network error. Check your internet connection.';
    }
    if (s.contains('apiexception') && s.contains('10')) {
      return 'Google Sign-In needs SHA-1 fingerprint registered in Firebase Console. You can sign in with Email below!';
    }
    return 'Sign-in failed. Please try again.';
  }

  Future<void> syncNow() async {
    if (state.user == null || _syncing) return;
    // The authStateChanges listener and every sign-in path both trigger a sync
    // for the same login; without this window they run back-to-back and
    // duplicate the whole sync for no benefit.
    final now = DateTime.now();
    final lastAttempt = _lastSyncAttemptAt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _syncDedupeWindow) {
      return;
    }
    _lastSyncAttemptAt = now;
    _syncing = true;
    emit(state.copyWith(syncStatus: SyncStatus.syncing, syncError: null));
    try {
      final success = await _cloudSyncService.syncAll();
      if (isClosed) return;
      if (success) {
        emit(state.copyWith(
          syncStatus: SyncStatus.success,
          lastSyncedAt: _cloudSyncService.lastSyncTime,
          syncError: null,
        ));
      } else {
        emit(state.copyWith(
          syncStatus: SyncStatus.failure,
          syncError: 'Failed to sync with cloud. Check internet connection.',
        ));
      }
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(
        syncStatus: SyncStatus.failure,
        syncError: 'Failed to sync with cloud. Check internet connection.',
      ));
    } finally {
      _syncing = false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    if (isClosed) return;
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
