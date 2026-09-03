// lib/features/auth/cubit/auth_cubit.dart
import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/bloc/base_cubit.dart';
import '../../../domain/services/auth_service.dart';
import '../../../data/services/cloud_sync_service.dart';
import 'auth_state.dart';

import '../../../core/utils/error_logger.dart';
@injectable
class AuthCubit extends PulsrCubit<AuthState> {
  final AuthService _authService;
  final CloudSyncService _cloudSyncService;

  AuthCubit(this._authService, this._cloudSyncService)
      : super(AuthState(lastSyncedAt: _cloudSyncService.lastSyncTime)) {
    _init();
  }

  void _init() {
    // autoSub owns the subscription lifetime (cancelled in super.close);
    // do NOT keep a manual cancel handle (double-cancel race).
    autoSub<User?>(_authService.authStateChanges, (user) {
      if (isClosed) return;
      if (user != null) {
        safeEmit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
          lastSyncedAt: _cloudSyncService.lastSyncTime,
        ));
        // Auto-sync in background on login
        unawaited(syncNow());
      } else {
        safeEmit(state.copyWith(
          status: AuthStatus.unauthenticated,
          user: null,
          errorMessage: null,
        ));
      }
    });
  }

  // FIX: guard concurrent taps
  bool _signInInProgress = false;
  bool _syncInProgress = false;
  Future<void> signInWithGoogle() async {
    if (_signInInProgress) return;
    if (state.status == AuthStatus.authenticating) return;
    _signInInProgress = true;
    safeEmit(state.copyWith(status: AuthStatus.authenticating, errorMessage: null));
    try {
      final user = await _authService.signInWithGoogle();
      if (isClosed) return;
      if (user != null) {
        safeEmit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
        await syncNow();
      } else {
        safeEmit(state.copyWith(status: AuthStatus.unauthenticated));
      }
    } catch (e) {
      if (isClosed) return;
      final msg = _mapAuthError(e);
      safeEmit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: msg,
      ));
    } finally {
      _signInInProgress = false;
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    final validation = _validateEmailPassword(email, password);
    if (validation != null) {
      safeEmit(state.copyWith(
          status: AuthStatus.error, errorMessage: validation));
      return;
    }
    if (_signInInProgress) return;
    _signInInProgress = true;
    safeEmit(state.copyWith(status: AuthStatus.authenticating, errorMessage: null));
    try {
      final user = await _authService.signInWithEmail(email, password);
      if (isClosed) return;
      if (user != null) {
        safeEmit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
        await syncNow();
      } else {
        safeEmit(state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: 'Sign in failed. Please try again.',
        ));
      }
    } catch (e) {
      if (isClosed) return;
      final msg = _mapAuthError(e);
      safeEmit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: msg,
      ));
    } finally {
      _signInInProgress = false;
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    final validation = _validateEmailPassword(email, password);
    if (validation != null) {
      safeEmit(state.copyWith(
          status: AuthStatus.error, errorMessage: validation));
      return;
    }
    if (_signInInProgress) return;
    _signInInProgress = true;
    safeEmit(state.copyWith(status: AuthStatus.authenticating, errorMessage: null));
    try {
      final user = await _authService.signUpWithEmail(email, password);
      if (isClosed) return;
      if (user != null) {
        safeEmit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
        await syncNow();
      } else {
        safeEmit(state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: 'Sign up failed. Please try again.',
        ));
      }
    } catch (e) {
      if (isClosed) return;
      final msg = _mapAuthError(e);
      safeEmit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: msg,
      ));
    } finally {
      _signInInProgress = false;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      if (isClosed) return;
      // FIX: surface success so UI can distinguish sent vs failed
      safeEmit(state.copyWith(errorMessage: null));
      emitEffect(ShowToastEffect('Password reset email sent to $email'));
    } catch (e) {
      if (isClosed) return;
      final msg = _mapAuthError(e);
      safeEmit(state.copyWith(
        errorMessage: msg,
      ));
    }
  }

  String? _validateEmailPassword(String email, String password) {
    final e = email.trim();
    if (e.isEmpty) return 'Please enter your email.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      return 'Please enter a valid email address.';
    }
    if (password.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  String _mapAuthError(Object e) {
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
    if (s.contains('user-disabled') || s.contains('user disabled')) {
      return 'This account has been disabled.';
    }
    if (s.contains('too-many-requests') || s.contains('too many requests')) {
      return 'Too many attempts. Try again later.';
    }
    if (s.contains('operation-not-allowed') ||
        s.contains('operation not allowed')) {
      return 'Email sign-in is not enabled. Use Google sign-in.';
    }
    if (s.contains('network-request-failed') ||
        s.contains('network error') ||
        s.contains('socketexception')) {
      return 'Network error. Check your internet connection.';
    }
    if ((s.contains('apiexception') && s.contains('10')) ||
        s.contains('developer_error') ||
        s.contains('statuscode: 10')) {
      return 'Local build signing not authorized for Google Sign-In. You can sign in with Email below!';
    }
    return 'Sign-in failed. Please try again.';
  }

  Future<void> syncNow() async {
    if (state.user == null || isClosed) return;
    // FIX: guard overlapping syncAll() on rapid auth flips / double-tap.
    if (_syncInProgress) return;
    _syncInProgress = true;
    safeEmit(state.copyWith(syncStatus: SyncStatus.syncing, syncError: null));
    bool success = false;
    try {
      success = await _cloudSyncService.syncAll();
    } finally {
      _syncInProgress = false;
    }
    if (isClosed) return;
    if (success) {
      safeEmit(state.copyWith(
        syncStatus: SyncStatus.success,
        lastSyncedAt: _cloudSyncService.lastSyncTime,
        syncError: null,
      ));
    } else {
      safeEmit(state.copyWith(
        syncStatus: SyncStatus.failure,
        syncError: 'Failed to sync with cloud. Check internet connection.',
      ));
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    // FIX: clear per-account dedup so next login re-uploads (no bleed/skip).
    try {
      await _cloudSyncService.clearAccountState();
    } catch (e, st) {
      ErrorLogger.log('signOut failed', error: e, stackTrace: st, category: 'AuthCubit');
    }
    if (isClosed) return;
    safeEmit(state.copyWith(
      status: AuthStatus.unauthenticated,
      user: null,
      syncStatus: SyncStatus.idle,
    ));
  }

  @override
  Future<void> close() {
    // _authSubscription owned by autoSub composite — super.close() cancels it.
    return super.close();
  }
}
