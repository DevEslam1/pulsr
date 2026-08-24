// lib/features/auth/cubit/auth_cubit.dart
import 'dart:async';
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

  AuthCubit(this._authService, this._cloudSyncService)
      : super(AuthState(lastSyncedAt: _cloudSyncService.lastSyncTime)) {
    _init();
  }

  void _init() {
    _authSubscription = _authService.authStateChanges.listen((user) {
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
      String msg = e.toString().replaceAll('Exception: ', '');
      if (msg.contains('10') || msg.contains('ApiException: 10')) {
        msg = 'Google Sign-In needs SHA-1 fingerprint registered in Firebase Console. You can sign in with Email below!';
      }
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
      if (user != null) {
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
        await syncNow();
      }
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      ));
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    emit(state.copyWith(status: AuthStatus.authenticating, errorMessage: null));
    try {
      final user = await _authService.signUpWithEmail(email, password);
      if (user != null) {
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          errorMessage: null,
        ));
        await syncNow();
      }
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      ));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
    } catch (e) {
      emit(state.copyWith(
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      ));
    }
  }

  Future<void> syncNow() async {
    if (state.user == null) return;
    emit(state.copyWith(syncStatus: SyncStatus.syncing, syncError: null));
    final success = await _cloudSyncService.syncAll();
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
  }

  Future<void> signOut() async {
    await _authService.signOut();
    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      user: null,
      syncStatus: SyncStatus.idle,
    ));
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
